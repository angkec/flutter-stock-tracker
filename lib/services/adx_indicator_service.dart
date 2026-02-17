import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/models/adx_config.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class _AdxMemoryEntry {
  final AdxConfig config;
  final String sourceSignature;
  final List<AdxPoint> points;

  const _AdxMemoryEntry({
    required this.config,
    required this.sourceSignature,
    required this.points,
  });
}

class AdxIndicatorService extends ChangeNotifier {
  static const String configStorageKey = 'adx_indicator_config_v1';
  static const String weeklyConfigStorageKey = 'adx_indicator_weekly_config_v1';
  static const String dailyPrewarmSnapshotStorageKey =
      'adx_prewarm_daily_snapshot_v1';
  static const String weeklyPrewarmSnapshotStorageKey =
      'adx_prewarm_weekly_snapshot_v1';

  static const int _defaultMaxConcurrentPrewarm = 6;
  static const int _defaultPersistBatchSize = 120;
  static const int _defaultRepositoryPrewarmBatchSize = 240;
  static const int _defaultFirstRepositoryPrewarmBatchSize = 40;

  final DataRepository _repository;
  final AdxCacheStore _cacheStore;
  final Map<String, _AdxMemoryEntry> _memoryCache = <String, _AdxMemoryEntry>{};

  AdxConfig _dailyConfig = AdxConfig.defaults;
  AdxConfig _weeklyConfig = AdxConfig.defaults;

  AdxIndicatorService({
    required DataRepository repository,
    AdxCacheStore? cacheStore,
  }) : _repository = repository,
       _cacheStore = cacheStore ?? AdxCacheStore();

  AdxConfig get dailyConfig => _dailyConfig;
  AdxConfig get weeklyConfig => _weeklyConfig;

  AdxConfig configFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly ? _weeklyConfig : _dailyConfig;
  }

  static AdxConfig defaultConfigFor(KLineDataType dataType) {
    return AdxConfig.defaults;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dailyConfig = _decodeConfig(
        prefs.getString(configStorageKey),
        fallback: AdxConfig.defaults,
      );
      _weeklyConfig = _decodeConfig(
        prefs.getString(weeklyConfigStorageKey),
        fallback: AdxConfig.defaults,
      );
    } catch (_) {
      _dailyConfig = AdxConfig.defaults;
      _weeklyConfig = AdxConfig.defaults;
    }
  }

  Future<void> updateConfigFor({
    required KLineDataType dataType,
    required AdxConfig newConfig,
  }) async {
    if (!newConfig.isValid) {
      throw ArgumentError('Invalid ADX config');
    }
    if (dataType == KLineDataType.weekly) {
      _weeklyConfig = newConfig;
    } else {
      _dailyConfig = newConfig;
    }
    _clearMemoryForDataType(dataType);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _configStorageKeyFor(dataType),
      jsonEncode(newConfig),
    );
    notifyListeners();
  }

  Future<void> resetConfigFor(KLineDataType dataType) async {
    await updateConfigFor(
      dataType: dataType,
      newConfig: defaultConfigFor(dataType),
    );
  }

  Future<List<AdxPoint>> getOrComputeFromRepository({
    required String stockCode,
    required KLineDataType dataType,
    required DateRange dateRange,
  }) async {
    final barsByStock = await _repository.getKlines(
      stockCodes: [stockCode],
      dateRange: dateRange,
      dataType: dataType,
    );
    return getOrComputeFromBars(
      stockCode: stockCode,
      dataType: dataType,
      bars: barsByStock[stockCode] ?? const <KLine>[],
    );
  }

  Future<List<AdxPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
    bool persistToDisk = true,
    void Function(AdxCacheSeries series)? onSeriesComputed,
  }) async {
    if (bars.isEmpty) {
      return const <AdxPoint>[];
    }

    final config = configFor(dataType);
    final sortedBars = _normalizeBarsOrder(bars);
    final signature = _buildSourceSignature(sortedBars, config);
    final cacheKey = _seriesKey(stockCode, dataType);

    if (!forceRecompute) {
      final memory = _memoryCache[cacheKey];
      if (memory != null &&
          memory.sourceSignature == signature &&
          memory.config == config) {
        return memory.points;
      }

      final disk = await _cacheStore.loadSeries(
        stockCode: stockCode,
        dataType: dataType,
      );
      if (disk != null &&
          disk.sourceSignature == signature &&
          disk.config == config) {
        _memoryCache[cacheKey] = _AdxMemoryEntry(
          config: disk.config,
          sourceSignature: disk.sourceSignature,
          points: disk.points,
        );
        return disk.points;
      }
    }

    final computed = _computeAdxSeries(sortedBars, config);
    final computedSeries = AdxCacheSeries(
      stockCode: stockCode,
      dataType: dataType,
      config: config,
      sourceSignature: signature,
      points: computed,
    );

    if (persistToDisk) {
      await _cacheStore.saveSeries(
        stockCode: stockCode,
        dataType: dataType,
        config: config,
        sourceSignature: signature,
        points: computed,
      );
    } else {
      onSeriesComputed?.call(computedSeries);
    }

    _memoryCache[cacheKey] = _AdxMemoryEntry(
      config: config,
      sourceSignature: signature,
      points: computed,
    );
    return computed;
  }

  Future<void> prewarmFromBars({
    required KLineDataType dataType,
    required Map<String, List<KLine>> barsByStockCode,
    bool forceRecompute = false,
    int? maxConcurrentTasks,
    int? maxConcurrentPersistWrites,
    int? persistBatchSize,
    void Function(int current, int total)? onProgress,
  }) async {
    if (barsByStockCode.isEmpty) {
      onProgress?.call(1, 1);
      return;
    }

    final entries = barsByStockCode.entries.toList(growable: false);
    final total = entries.length;
    final workerCount = min(
      max(1, maxConcurrentTasks ?? _defaultMaxConcurrentPrewarm),
      total,
    );
    final batchSize = max(1, persistBatchSize ?? _defaultPersistBatchSize);
    final cachedStockCodes = forceRecompute
        ? const <String>{}
        : await _cacheStore.listStockCodes(dataType: dataType);

    var nextIndex = 0;
    var computeCompleted = 0;
    var writeCompleted = 0;
    final progressTotal = total * 2;

    void emitProgress() {
      onProgress?.call(computeCompleted + writeCompleted, progressTotal);
    }

    Future<void> flushLocalWrites(List<AdxCacheSeries> localPending) async {
      if (localPending.isEmpty) {
        return;
      }

      final batch = List<AdxCacheSeries>.from(localPending, growable: false);
      localPending.clear();

      await _cacheStore.saveAll(
        batch,
        maxConcurrentWrites:
            maxConcurrentPersistWrites ??
            _cacheStore.defaultMaxConcurrentWrites,
      );
      writeCompleted += batch.length;
      emitProgress();
    }

    Future<void> runWorker() async {
      final localPending = <AdxCacheSeries>[];

      while (true) {
        final index = nextIndex;
        if (index >= total) {
          await flushLocalWrites(localPending);
          return;
        }
        nextIndex++;

        final entry = entries[index];
        AdxCacheSeries? computedSeries;
        final shouldForceForMissingCache =
            !forceRecompute && !cachedStockCodes.contains(entry.key);

        await getOrComputeFromBars(
          stockCode: entry.key,
          dataType: dataType,
          bars: entry.value,
          forceRecompute: forceRecompute || shouldForceForMissingCache,
          persistToDisk: false,
          onSeriesComputed: (series) {
            computedSeries = series;
          },
        );

        computeCompleted++;
        emitProgress();

        if (computedSeries != null) {
          localPending.add(computedSeries!);
          if (localPending.length >= batchSize) {
            await flushLocalWrites(localPending);
          }
        } else {
          writeCompleted++;
          emitProgress();
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => runWorker()),
    );
  }

  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    if (stockCodes.isEmpty) {
      onProgress?.call(1, 1);
      return;
    }

    final deduplicatedStockCodes = stockCodes.toSet().toList(growable: false);
    final stockScopeSignature = _buildStockScopeSignature(
      deduplicatedStockCodes,
    );
    final configSignature = _buildConfigSignature(configFor(dataType));

    int? currentDataVersion;
    if (!forceRecompute) {
      try {
        currentDataVersion = await _repository.getCurrentVersion();
        final prewarmSnapshot = await _loadPrewarmSnapshot(dataType);
        final canSkip =
            prewarmSnapshot != null &&
            prewarmSnapshot.version == currentDataVersion &&
            prewarmSnapshot.configSignature == configSignature &&
            prewarmSnapshot.stockScopeSignature == stockScopeSignature;
        if (canSkip) {
          final cachedStockCodes = await _cacheStore.listStockCodes(
            dataType: dataType,
          );
          final cachedStockCodeSet = cachedStockCodes.toSet();
          final hasCompleteCache = deduplicatedStockCodes.every(
            cachedStockCodeSet.contains,
          );
          if (hasCompleteCache) {
            onProgress?.call(1, 1);
            return;
          }
        }
      } catch (_) {
        // Continue with full prewarm when snapshot check fails.
      }
    }

    final batchSize = max(
      1,
      fetchBatchSize ?? _defaultRepositoryPrewarmBatchSize,
    );
    final firstBatchSize = min(
      batchSize,
      _defaultFirstRepositoryPrewarmBatchSize,
    );
    final totalProgress = deduplicatedStockCodes.length * 2;
    var completedProgress = 0;
    var cursor = 0;

    List<String> nextChunk({required int chunkSize}) {
      if (cursor >= deduplicatedStockCodes.length) {
        return const <String>[];
      }
      final end = min(cursor + chunkSize, deduplicatedStockCodes.length);
      final chunk = deduplicatedStockCodes.sublist(cursor, end);
      cursor = end;
      return chunk;
    }

    var currentChunkStockCodes = nextChunk(chunkSize: firstBatchSize);
    if (currentChunkStockCodes.isEmpty) {
      onProgress?.call(1, 1);
      return;
    }

    Future<Map<String, List<KLine>>> currentChunkFetchFuture = _repository
        .getKlines(
          stockCodes: currentChunkStockCodes,
          dateRange: dateRange,
          dataType: dataType,
        );

    while (true) {
      final nextChunkStockCodes = nextChunk(chunkSize: batchSize);
      final Future<Map<String, List<KLine>>>? nextChunkFetchFuture =
          nextChunkStockCodes.isEmpty
          ? null
          : _repository.getKlines(
              stockCodes: nextChunkStockCodes,
              dateRange: dateRange,
              dataType: dataType,
            );

      final barsByStock = await currentChunkFetchFuture;

      await prewarmFromBars(
        dataType: dataType,
        barsByStockCode: barsByStock,
        forceRecompute: forceRecompute,
        maxConcurrentPersistWrites: maxConcurrentPersistWrites,
        onProgress: (current, total) {
          final mappedCurrent = (completedProgress + current).clamp(
            0,
            totalProgress,
          );
          onProgress?.call(mappedCurrent, totalProgress);
        },
      );

      completedProgress += currentChunkStockCodes.length * 2;
      onProgress?.call(
        completedProgress.clamp(0, totalProgress),
        totalProgress,
      );

      if (nextChunkFetchFuture == null) {
        break;
      }

      currentChunkStockCodes = nextChunkStockCodes;
      currentChunkFetchFuture = nextChunkFetchFuture;
    }

    if (!forceRecompute && currentDataVersion != null) {
      await _savePrewarmSnapshot(
        dataType: dataType,
        snapshot: (
          version: currentDataVersion,
          configSignature: configSignature,
          stockScopeSignature: stockScopeSignature,
        ),
      );
    }
  }

  static List<AdxPoint> _computeAdxSeries(List<KLine> bars, AdxConfig config) {
    if (bars.length < config.period + 1) {
      return const <AdxPoint>[];
    }

    final period = config.period;
    final tr = List<double>.filled(bars.length, 0);
    final plusDm = List<double>.filled(bars.length, 0);
    final minusDm = List<double>.filled(bars.length, 0);

    for (var i = 1; i < bars.length; i++) {
      final current = bars[i];
      final previous = bars[i - 1];
      final upMove = current.high - previous.high;
      final downMove = previous.low - current.low;

      final rawTr = max(
        current.high - current.low,
        max(
          (current.high - previous.close).abs(),
          (current.low - previous.close).abs(),
        ),
      );
      tr[i] = rawTr;

      if (upMove > downMove && upMove > 0) {
        plusDm[i] = upMove;
      }
      if (downMove > upMove && downMove > 0) {
        minusDm[i] = downMove;
      }
    }

    var smoothedTr = 0.0;
    var smoothedPlusDm = 0.0;
    var smoothedMinusDm = 0.0;
    for (var i = 1; i <= period && i < bars.length; i++) {
      smoothedTr += tr[i];
      smoothedPlusDm += plusDm[i];
      smoothedMinusDm += minusDm[i];
    }

    if (smoothedTr <= 0) {
      return const <AdxPoint>[];
    }

    final dxWindow = <double>[];
    final points = <AdxPoint>[];
    double? adx;

    for (var i = period; i < bars.length; i++) {
      if (i > period) {
        smoothedTr = smoothedTr - (smoothedTr / period) + tr[i];
        smoothedPlusDm = smoothedPlusDm - (smoothedPlusDm / period) + plusDm[i];
        smoothedMinusDm =
            smoothedMinusDm - (smoothedMinusDm / period) + minusDm[i];
      }

      final plusDi = smoothedTr <= 0
          ? 0.0
          : (100.0 * smoothedPlusDm / smoothedTr);
      final minusDi = smoothedTr <= 0
          ? 0.0
          : (100.0 * smoothedMinusDm / smoothedTr);
      final diSum = plusDi + minusDi;
      final dx = diSum <= 0 ? 0.0 : (100.0 * (plusDi - minusDi).abs() / diSum);

      if (adx == null) {
        dxWindow.add(dx);
        if (dxWindow.length < period) {
          continue;
        }
        adx = dxWindow.reduce((a, b) => a + b) / dxWindow.length;
      } else {
        adx = ((adx * (period - 1)) + dx) / period;
      }

      points.add(
        AdxPoint(
          datetime: bars[i].datetime,
          adx: adx,
          plusDi: plusDi,
          minusDi: minusDi,
        ),
      );
    }

    return points;
  }

  List<KLine> _normalizeBarsOrder(List<KLine> bars) {
    if (bars.length < 2) {
      return bars;
    }

    for (var i = 1; i < bars.length; i++) {
      if (bars[i - 1].datetime.isAfter(bars[i].datetime)) {
        final sorted = List<KLine>.from(bars);
        sorted.sort((a, b) => a.datetime.compareTo(b.datetime));
        return sorted;
      }
    }

    return bars;
  }

  String _buildSourceSignature(List<KLine> bars, AdxConfig config) {
    var rolling = 17;
    for (final bar in bars) {
      final ts = bar.datetime.millisecondsSinceEpoch;
      final highScaled = (bar.high * 10000).round();
      final lowScaled = (bar.low * 10000).round();
      final closeScaled = (bar.close * 10000).round();

      rolling = _mixInt(rolling, ts);
      rolling = _mixInt(rolling, highScaled);
      rolling = _mixInt(rolling, lowScaled);
      rolling = _mixInt(rolling, closeScaled);
    }

    final length = bars.length;
    final firstTs = bars.first.datetime.millisecondsSinceEpoch;
    final lastTs = bars.last.datetime.millisecondsSinceEpoch;
    return '${config.period}|${config.threshold.toStringAsFixed(4)}|'
        '$length|$firstTs|$lastTs|$rolling';
  }

  AdxConfig _decodeConfig(String? raw, {required AdxConfig fallback}) {
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return AdxConfig.fromJson(json);
  }

  String _configStorageKeyFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly
        ? weeklyConfigStorageKey
        : configStorageKey;
  }

  String _prewarmSnapshotStorageKeyFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly
        ? weeklyPrewarmSnapshotStorageKey
        : dailyPrewarmSnapshotStorageKey;
  }

  void _clearMemoryForDataType(KLineDataType dataType) {
    final suffix = '_${dataType.name}';
    _memoryCache.removeWhere((key, _) => key.endsWith(suffix));
  }

  String _buildConfigSignature(AdxConfig config) {
    return '${config.period}|${config.threshold.toStringAsFixed(4)}';
  }

  String _buildStockScopeSignature(List<String> stockCodes) {
    if (stockCodes.isEmpty) {
      return '0|0';
    }
    final sortedCodes = List<String>.from(stockCodes)..sort();
    var rolling = 23;
    for (final code in sortedCodes) {
      for (final rune in code.runes) {
        rolling = _mixInt(rolling, rune);
      }
    }
    return '${sortedCodes.length}|$rolling';
  }

  Future<({int version, String configSignature, String stockScopeSignature})?>
  _loadPrewarmSnapshot(KLineDataType dataType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prewarmSnapshotStorageKeyFor(dataType));
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['version'] as int?;
      final configSignature = json['configSignature'] as String?;
      final stockScopeSignature = json['stockScopeSignature'] as String?;
      if (version == null ||
          configSignature == null ||
          stockScopeSignature == null) {
        return null;
      }

      return (
        version: version,
        configSignature: configSignature,
        stockScopeSignature: stockScopeSignature,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePrewarmSnapshot({
    required KLineDataType dataType,
    required ({int version, String configSignature, String stockScopeSignature})
    snapshot,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prewarmSnapshotStorageKeyFor(dataType),
        jsonEncode({
          'version': snapshot.version,
          'configSignature': snapshot.configSignature,
          'stockScopeSignature': snapshot.stockScopeSignature,
        }),
      );
    } catch (_) {
      // Do not break prewarm flow due to snapshot persistence failures.
    }
  }

  int _mixInt(int seed, int value) {
    return ((seed * 1315423911) ^ value) & 0x7fffffff;
  }

  String _seriesKey(String stockCode, KLineDataType dataType) {
    return '${stockCode}_${dataType.name}';
  }
}
