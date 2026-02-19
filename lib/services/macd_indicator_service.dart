import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';

class _MacdMemoryEntry {
  final MacdConfig config;
  final String sourceSignature;
  final List<MacdPoint> points;

  const _MacdMemoryEntry({
    required this.config,
    required this.sourceSignature,
    required this.points,
  });
}

class MacdIndicatorService extends ChangeNotifier {
  static const String configStorageKey = 'macd_indicator_config_v1';
  static const String weeklyConfigStorageKey =
      'macd_indicator_weekly_config_v1';
  static const String dailyPrewarmSnapshotStorageKey =
      'macd_prewarm_daily_snapshot_v1';
  static const String weeklyPrewarmSnapshotStorageKey =
      'macd_prewarm_weekly_snapshot_v1';
  static const MacdConfig weeklyDefaultConfig = MacdConfig(
    fastPeriod: 12,
    slowPeriod: 26,
    signalPeriod: 9,
    windowMonths: 12,
  );
  static const int _defaultMaxConcurrentPrewarm = 6;
  static const int _defaultPersistBatchSize = 120;
  static const int _defaultRepositoryPrewarmBatchSize = 240;
  static const int _defaultFirstRepositoryPrewarmBatchSize = 40;

  final DataRepository _repository;
  final MacdCacheStore _cacheStore;
  final Map<String, _MacdMemoryEntry> _memoryCache =
      <String, _MacdMemoryEntry>{};

  MacdConfig _dailyConfig = MacdConfig.defaults;
  MacdConfig _weeklyConfig = weeklyDefaultConfig;

  MacdIndicatorService({
    required DataRepository repository,
    MacdCacheStore? cacheStore,
  }) : _repository = repository,
       _cacheStore = cacheStore ?? MacdCacheStore();

  MacdConfig get config => _dailyConfig;
  MacdConfig get dailyConfig => _dailyConfig;
  MacdConfig get weeklyConfig => _weeklyConfig;

  MacdConfig configFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly ? _weeklyConfig : _dailyConfig;
  }

  static MacdConfig defaultConfigFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly
        ? weeklyDefaultConfig
        : MacdConfig.defaults;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dailyConfig = _decodeConfig(
        prefs.getString(configStorageKey),
        fallback: MacdConfig.defaults,
      );
      final weeklyLoaded = _decodeConfig(
        prefs.getString(weeklyConfigStorageKey),
        fallback: weeklyDefaultConfig,
      );
      _weeklyConfig = _normalizeConfigForDataType(
        KLineDataType.weekly,
        weeklyLoaded,
      );
      if (_weeklyConfig != weeklyLoaded) {
        await prefs.setString(
          weeklyConfigStorageKey,
          jsonEncode(_weeklyConfig.toJson()),
        );
      }
    } catch (_) {
      _dailyConfig = MacdConfig.defaults;
      _weeklyConfig = weeklyDefaultConfig;
    }
  }

  Future<void> updateConfig(MacdConfig newConfig) async {
    await updateConfigFor(dataType: KLineDataType.daily, newConfig: newConfig);
  }

  Future<void> updateConfigFor({
    required KLineDataType dataType,
    required MacdConfig newConfig,
  }) async {
    if (!newConfig.isValid) {
      throw ArgumentError('Invalid MACD config');
    }
    final normalizedConfig = _normalizeConfigForDataType(dataType, newConfig);
    if (dataType == KLineDataType.weekly) {
      _weeklyConfig = normalizedConfig;
    } else {
      _dailyConfig = normalizedConfig;
    }
    _clearMemoryForDataType(dataType);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _configStorageKeyFor(dataType),
      jsonEncode(normalizedConfig.toJson()),
    );
    notifyListeners();
  }

  Future<void> resetConfig() async {
    await resetConfigFor(KLineDataType.daily);
  }

  Future<void> resetConfigFor(KLineDataType dataType) async {
    await updateConfigFor(
      dataType: dataType,
      newConfig: defaultConfigFor(dataType),
    );
  }

  Future<List<MacdPoint>> getOrComputeFromRepository({
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

  Future<List<MacdPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
    bool persistToDisk = true,
    void Function(MacdCacheSeries series)? onSeriesComputed,
  }) async {
    if (bars.isEmpty) {
      return const <MacdPoint>[];
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
        _memoryCache[cacheKey] = _MacdMemoryEntry(
          config: disk.config,
          sourceSignature: disk.sourceSignature,
          points: disk.points,
        );
        return disk.points;
      }
    }

    final computed = _computeMacdSeries(sortedBars, config);
    final computedSeries = MacdCacheSeries(
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

    _memoryCache[cacheKey] = _MacdMemoryEntry(
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
      debugPrint(
        '[MACD] prewarmFromBars dataType=$dataType entries=${barsByStockCode.length} force=$forceRecompute',
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

    var nextIndex = 0;
    var computeCompleted = 0;
    var writeCompleted = 0;
    final progressTotal = total * 2;

    void emitProgress() {
      onProgress?.call(computeCompleted + writeCompleted, progressTotal);
    }

    Future<void> flushLocalWrites(List<MacdCacheSeries> localPending) async {
      if (localPending.isEmpty) {
        return;
      }

      final batch = List<MacdCacheSeries>.from(localPending, growable: false);
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
      final localPending = <MacdCacheSeries>[];

      while (true) {
        final index = nextIndex;
        if (index >= total) {
          await flushLocalWrites(localPending);
          return;
        }
        nextIndex++;

        final entry = entries[index];
        MacdCacheSeries? computedSeries;
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
    bool ignoreSnapshot = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[MACD] prewarmFromRepository force=$forceRecompute ignoreSnapshot=$ignoreSnapshot stocks=${stockCodes.length}',
      );
    }
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
          if (kDebugMode) {
            debugPrint('[MACD] prewarmFromRepository skipSnapshot=true');
          }
          onProgress?.call(1, 1);
          return;
        }
      } catch (_) {
        // Ignore version snapshot failures and continue with full prewarm.
      }
    }
    if (kDebugMode) {
      debugPrint('[MACD] prewarmFromRepository skipSnapshot=false');
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

  static List<MacdPoint> _computeMacdSeries(
    List<KLine> bars,
    MacdConfig config,
  ) {
    if (bars.isEmpty) return const <MacdPoint>[];

    final alphaFast = 2 / (config.fastPeriod + 1);
    final alphaSlow = 2 / (config.slowPeriod + 1);
    final alphaSignal = 2 / (config.signalPeriod + 1);

    var emaFast = bars.first.close;
    var emaSlow = bars.first.close;
    var dea = 0.0;
    final allPoints = <MacdPoint>[];

    for (var index = 0; index < bars.length; index++) {
      final close = bars[index].close;

      if (index > 0) {
        emaFast = emaFast + alphaFast * (close - emaFast);
        emaSlow = emaSlow + alphaSlow * (close - emaSlow);
      }

      final dif = emaFast - emaSlow;
      if (index == 0) {
        dea = dif;
      } else {
        dea = dea + alphaSignal * (dif - dea);
      }
      final hist = (dif - dea) * 2;

      allPoints.add(
        MacdPoint(
          datetime: bars[index].datetime,
          dif: dif,
          dea: dea,
          hist: hist,
        ),
      );
    }

    final latestDate = allPoints.last.datetime;
    final cutoff = _subtractMonths(latestDate, config.windowMonths);
    return allPoints
        .where((point) => !point.datetime.isBefore(cutoff))
        .toList(growable: false);
  }

  static DateTime _subtractMonths(DateTime date, int months) {
    final totalMonths = date.year * 12 + date.month - 1 - months;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = totalMonths % 12 + 1;
    final targetDay = min(date.day, _daysInMonth(targetYear, targetMonth));
    return DateTime(
      targetYear,
      targetMonth,
      targetDay,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  static int _daysInMonth(int year, int month) {
    if (month == 12) {
      return DateTime(year + 1, 1, 0).day;
    }
    return DateTime(year, month + 1, 0).day;
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

  String _buildSourceSignature(List<KLine> bars, MacdConfig config) {
    var rolling = 17;
    for (final bar in bars) {
      final ts = bar.datetime.millisecondsSinceEpoch;
      final closeScaled = (bar.close * 10000).round();

      rolling = _mixInt(rolling, ts);
      rolling = _mixInt(rolling, closeScaled);
    }

    final length = bars.length;
    final firstTs = bars.first.datetime.millisecondsSinceEpoch;
    final lastBar = bars.last;
    final lastTs = lastBar.datetime.millisecondsSinceEpoch;
    return '${config.fastPeriod}|${config.slowPeriod}|'
        '${config.signalPeriod}|${config.windowMonths}|'
        '$length|$firstTs|$lastTs|$rolling';
  }

  MacdConfig _decodeConfig(String? raw, {required MacdConfig fallback}) {
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return MacdConfig.fromJson(json);
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

  MacdConfig _normalizeConfigForDataType(
    KLineDataType dataType,
    MacdConfig config,
  ) {
    if (dataType != KLineDataType.weekly) {
      return config;
    }
    if (config.windowMonths == weeklyDefaultConfig.windowMonths) {
      return config;
    }
    return config.copyWith(windowMonths: weeklyDefaultConfig.windowMonths);
  }

  void _clearMemoryForDataType(KLineDataType dataType) {
    final suffix = '_${dataType.name}';
    _memoryCache.removeWhere((key, _) => key.endsWith(suffix));
  }

  String _buildConfigSignature(MacdConfig config) {
    return '${config.fastPeriod}|${config.slowPeriod}|'
        '${config.signalPeriod}|${config.windowMonths}';
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
      // Swallow snapshot persistence errors; they should not break prewarm flow.
    }
  }

  int _mixInt(int seed, int value) {
    return ((seed * 1315423911) ^ value) & 0x7fffffff;
  }

  String _seriesKey(String stockCode, KLineDataType dataType) {
    return '${stockCode}_${dataType.name}';
  }
}
