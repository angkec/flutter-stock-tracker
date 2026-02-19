import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/models/ema_config.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class _EmaMemoryEntry {
  final EmaConfig config;
  final String sourceSignature;
  final List<EmaPoint> points;

  const _EmaMemoryEntry({
    required this.config,
    required this.sourceSignature,
    required this.points,
  });
}

class EmaIndicatorService extends ChangeNotifier {
  static const String configStorageKey = 'ema_indicator_config_v1';
  static const String weeklyConfigStorageKey = 'ema_indicator_weekly_config_v1';
  static const String dailyPrewarmSnapshotStorageKey =
      'ema_prewarm_daily_snapshot_v1';
  static const String weeklyPrewarmSnapshotStorageKey =
      'ema_prewarm_weekly_snapshot_v1';

  static const int _defaultMaxConcurrentPrewarm = 6;
  static const int _defaultPersistBatchSize = 120;
  static const int _defaultRepositoryPrewarmBatchSize = 240;
  static const int _defaultFirstRepositoryPrewarmBatchSize = 40;

  final DataRepository _repository;
  final EmaCacheStore _cacheStore;
  final Map<String, _EmaMemoryEntry> _memoryCache = <String, _EmaMemoryEntry>{};

  EmaConfig _dailyConfig = EmaConfig.dailyDefaults;
  EmaConfig _weeklyConfig = EmaConfig.weeklyDefaults;

  EmaIndicatorService({
    required DataRepository repository,
    EmaCacheStore? cacheStore,
  }) : _repository = repository,
       _cacheStore = cacheStore ?? EmaCacheStore();

  EmaConfig get dailyConfig => _dailyConfig;
  EmaConfig get weeklyConfig => _weeklyConfig;

  EmaConfig configFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly ? _weeklyConfig : _dailyConfig;
  }

  static EmaConfig defaultConfigFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly
        ? EmaConfig.weeklyDefaults
        : EmaConfig.dailyDefaults;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dailyConfig = _decodeConfig(
        prefs.getString(configStorageKey),
        fallback: EmaConfig.dailyDefaults,
      );
      _weeklyConfig = _decodeConfig(
        prefs.getString(weeklyConfigStorageKey),
        fallback: EmaConfig.weeklyDefaults,
      );
    } catch (_) {
      _dailyConfig = EmaConfig.dailyDefaults;
      _weeklyConfig = EmaConfig.weeklyDefaults;
    }
  }

  Future<void> updateConfigFor({
    required KLineDataType dataType,
    required EmaConfig newConfig,
  }) async {
    if (!newConfig.isValid) {
      throw ArgumentError('Invalid EMA config');
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
      jsonEncode(newConfig.toJson()),
    );
    notifyListeners();
  }

  Future<void> resetConfigFor(KLineDataType dataType) async {
    await updateConfigFor(
      dataType: dataType,
      newConfig: defaultConfigFor(dataType),
    );
  }

  Future<List<EmaPoint>> getOrComputeFromRepository({
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

  Future<List<EmaPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
    bool persistToDisk = true,
    void Function(EmaCacheSeries series)? onSeriesComputed,
  }) async {
    if (bars.isEmpty) {
      return const <EmaPoint>[];
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
        _memoryCache[cacheKey] = _EmaMemoryEntry(
          config: disk.config,
          sourceSignature: disk.sourceSignature,
          points: disk.points,
        );
        return disk.points;
      }
    }

    final computed = _computeEmaSeries(sortedBars, config);
    final computedSeries = EmaCacheSeries(
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

    _memoryCache[cacheKey] = _EmaMemoryEntry(
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
    if (kDebugMode) {
      final barsCount = barsByStockCode.values.fold<int>(
        0,
        (sum, bars) => sum + bars.length,
      );
      debugPrint(
        '[EMA] prewarmFromBars dataType=$dataType entries=${barsByStockCode.length} bars=$barsCount force=$forceRecompute',
      );
    }
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
    if (kDebugMode) {
      debugPrint(
        '[EMA] prewarmFromBars workers=$workerCount batchSize=$batchSize '
        'cached=${cachedStockCodes.length}',
      );
    }

    var nextIndex = 0;
    var computeCompleted = 0;
    var writeCompleted = 0;
    final progressTotal = total * 2;

    void emitProgress() {
      onProgress?.call(computeCompleted + writeCompleted, progressTotal);
    }

    Future<void> flushLocalWrites(List<EmaCacheSeries> localPending) async {
      if (localPending.isEmpty) return;

      final batch = List<EmaCacheSeries>.from(localPending, growable: false);
      localPending.clear();

      await _cacheStore.saveAll(
        batch,
        maxConcurrentWrites:
            maxConcurrentPersistWrites ?? _cacheStore.defaultMaxConcurrentWrites,
      );
      writeCompleted += batch.length;
      emitProgress();
    }

    Future<void> runWorker() async {
      final localPending = <EmaCacheSeries>[];

      while (true) {
        final index = nextIndex;
        if (index >= total) {
          await flushLocalWrites(localPending);
          return;
        }
        nextIndex++;

        final entry = entries[index];
        EmaCacheSeries? computedSeries;
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
    if (kDebugMode) {
      debugPrint('[EMA] prewarmFromBars done');
    }
  }

  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    bool ignoreSnapshot = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[EMA] prewarmFromRepository force=$forceRecompute ignoreSnapshot=$ignoreSnapshot stocks=${stockCodes.length}',
      );
    }
    if (stockCodes.isEmpty) {
      onProgress?.call(1, 1);
      return;
    }

    final deduplicatedStockCodes = stockCodes.toSet().toList(growable: false);
    final stockScopeSignature = _buildStockScopeSignature(deduplicatedStockCodes);
    final configSignature = buildConfigSignature(configFor(dataType));

    int? currentDataVersion;
    if (!forceRecompute && !ignoreSnapshot) {
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
            if (kDebugMode) {
              debugPrint('[EMA] prewarmFromRepository skipSnapshot=true');
            }
            onProgress?.call(1, 1);
            return;
          }
        }
      } catch (_) {
        // Continue with full prewarm when snapshot check fails.
      }
    }
    if (kDebugMode) {
      debugPrint('[EMA] prewarmFromRepository skipSnapshot=false');
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

  static List<EmaPoint> _computeEmaSeries(List<KLine> bars, EmaConfig config) {
    if (bars.isEmpty) return const <EmaPoint>[];

    final alphaShort = 2.0 / (config.shortPeriod + 1);
    final alphaLong = 2.0 / (config.longPeriod + 1);

    var emaShort = bars.first.close;
    var emaLong = bars.first.close;
    final points = <EmaPoint>[];

    for (var i = 0; i < bars.length; i++) {
      final close = bars[i].close;
      if (i > 0) {
        emaShort = emaShort + alphaShort * (close - emaShort);
        emaLong = emaLong + alphaLong * (close - emaLong);
      }
      points.add(EmaPoint(
        datetime: bars[i].datetime,
        emaShort: emaShort,
        emaLong: emaLong,
      ));
    }

    return points;
  }

  List<KLine> _normalizeBarsOrder(List<KLine> bars) {
    if (bars.length < 2) return bars;
    for (var i = 1; i < bars.length; i++) {
      if (bars[i - 1].datetime.isAfter(bars[i].datetime)) {
        final sorted = List<KLine>.from(bars);
        sorted.sort((a, b) => a.datetime.compareTo(b.datetime));
        return sorted;
      }
    }
    return bars;
  }

  String _buildSourceSignature(List<KLine> bars, EmaConfig config) {
    var rolling = 17;
    for (final bar in bars) {
      final ts = bar.datetime.millisecondsSinceEpoch;
      final closeScaled = (bar.close * 10000).round();
      rolling = _mixInt(rolling, ts);
      rolling = _mixInt(rolling, closeScaled);
    }
    final length = bars.length;
    final firstTs = bars.first.datetime.millisecondsSinceEpoch;
    final lastTs = bars.last.datetime.millisecondsSinceEpoch;
    return '${config.shortPeriod}|${config.longPeriod}|$length|$firstTs|$lastTs|$rolling';
  }

  String buildConfigSignature(EmaConfig config) {
    return '${config.shortPeriod}|${config.longPeriod}';
  }

  String _buildStockScopeSignature(List<String> stockCodes) {
    if (stockCodes.isEmpty) return '0|0';
    final sortedCodes = List<String>.from(stockCodes)..sort();
    var rolling = 23;
    for (final code in sortedCodes) {
      for (final rune in code.runes) {
        rolling = _mixInt(rolling, rune);
      }
    }
    return '${sortedCodes.length}|$rolling';
  }

  EmaConfig _decodeConfig(String? raw, {required EmaConfig fallback}) {
    if (raw == null || raw.isEmpty) return fallback;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return EmaConfig.fromJson(json, defaults: fallback);
    } catch (_) {
      return fallback;
    }
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

  Future<({int version, String configSignature, String stockScopeSignature})?>
  _loadPrewarmSnapshot(KLineDataType dataType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prewarmSnapshotStorageKeyFor(dataType));
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['version'] as int?;
      final configSig = json['configSignature'] as String?;
      final stockScopeSig = json['stockScopeSignature'] as String?;
      if (version == null || configSig == null || stockScopeSig == null) {
        return null;
      }
      return (
        version: version,
        configSignature: configSig,
        stockScopeSignature: stockScopeSig,
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
