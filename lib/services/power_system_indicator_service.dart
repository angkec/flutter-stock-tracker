import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';
import 'package:stock_rtwatcher/models/power_system_point.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';

class _PowerSystemMemoryEntry {
  const _PowerSystemMemoryEntry({
    required this.sourceSignature,
    required this.points,
  });

  final String sourceSignature;
  final List<PowerSystemPoint> points;
}

class PowerSystemIndicatorService extends ChangeNotifier {
  static const String dailyPrewarmSnapshotStorageKey =
      'power_system_prewarm_daily_snapshot_v1';
  static const String weeklyPrewarmSnapshotStorageKey =
      'power_system_prewarm_weekly_snapshot_v1';
  static const int _defaultRepositoryPrewarmBatchSize = 240;
  static const int _defaultFirstRepositoryPrewarmBatchSize = 40;

  PowerSystemIndicatorService({
    required DataRepository repository,
    required EmaIndicatorService emaService,
    required MacdIndicatorService macdService,
    PowerSystemCacheStore? cacheStore,
  }) : _repository = repository,
       _emaService = emaService,
       _macdService = macdService,
       _cacheStore = cacheStore ?? PowerSystemCacheStore();

  final DataRepository _repository;
  final EmaIndicatorService _emaService;
  final MacdIndicatorService _macdService;
  final PowerSystemCacheStore _cacheStore;
  final Map<String, _PowerSystemMemoryEntry> _memoryCache =
      <String, _PowerSystemMemoryEntry>{};

  Future<List<PowerSystemPoint>> getOrComputeFromRepository({
    required String stockCode,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
  }) async {
    final barsByStock = await _repository.getKlines(
      stockCodes: <String>[stockCode],
      dateRange: dateRange,
      dataType: dataType,
    );
    return getOrComputeFromBars(
      stockCode: stockCode,
      dataType: dataType,
      bars: barsByStock[stockCode] ?? const <KLine>[],
      forceRecompute: forceRecompute,
    );
  }

  Future<List<PowerSystemPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
  }) async {
    if (bars.length < 2) {
      return const <PowerSystemPoint>[];
    }

    final sortedBars = _normalizeBarsOrder(bars);
    final signature = _buildSourceSignature(sortedBars, dataType);
    final cacheKey = _seriesKey(stockCode, dataType);

    if (!forceRecompute) {
      final memory = _memoryCache[cacheKey];
      if (memory != null && memory.sourceSignature == signature) {
        return memory.points;
      }

      final disk = await _cacheStore.loadSeries(
        stockCode: stockCode,
        dataType: dataType,
      );
      if (disk != null && disk.sourceSignature == signature) {
        _memoryCache[cacheKey] = _PowerSystemMemoryEntry(
          sourceSignature: disk.sourceSignature,
          points: disk.points,
        );
        return disk.points;
      }
    }

    final emaPoints = await _emaService.getOrComputeFromBars(
      stockCode: stockCode,
      dataType: dataType,
      bars: sortedBars,
      forceRecompute: forceRecompute,
    );
    final macdPoints = await _macdService.getOrComputeFromBars(
      stockCode: stockCode,
      dataType: dataType,
      bars: sortedBars,
      forceRecompute: forceRecompute,
    );

    final computed = _computePowerSystemSeries(
      bars: sortedBars,
      emaPoints: emaPoints,
      macdPoints: macdPoints,
    );

    await _cacheStore.saveSeries(
      stockCode: stockCode,
      dataType: dataType,
      sourceSignature: signature,
      points: computed,
    );

    _memoryCache[cacheKey] = _PowerSystemMemoryEntry(
      sourceSignature: signature,
      points: computed,
    );
    return computed;
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
    if (stockCodes.isEmpty) {
      onProgress?.call(1, 1);
      return;
    }

    final deduplicatedStockCodes = stockCodes.toSet().toList(growable: false);
    final stockScopeSignature = _buildStockScopeSignature(
      deduplicatedStockCodes,
    );
    final configSignature = _buildConfigSignature(dataType);

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
          final hasCompleteCache = deduplicatedStockCodes.every(
            cachedStockCodes.contains,
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
      for (final entry in barsByStock.entries) {
        await getOrComputeFromBars(
          stockCode: entry.key,
          dataType: dataType,
          bars: entry.value,
          forceRecompute: forceRecompute,
        );
        completedProgress += 2;
        onProgress?.call(
          completedProgress.clamp(0, totalProgress),
          totalProgress,
        );
      }

      if (nextChunkFetchFuture == null) {
        break;
      }

      currentChunkStockCodes = nextChunkStockCodes;
      currentChunkFetchFuture = nextChunkFetchFuture;
    }

    onProgress?.call(totalProgress, totalProgress);

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

    if (maxConcurrentPersistWrites != null) {
      // Reserved for parity with other indicator services.
    }
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
    var completed = 0;
    final progressTotal = total * 2;

    for (final entry in entries) {
      await getOrComputeFromBars(
        stockCode: entry.key,
        dataType: dataType,
        bars: entry.value,
        forceRecompute: forceRecompute,
      );
      completed += 2;
      onProgress?.call(completed.clamp(0, progressTotal), progressTotal);
    }

    if (maxConcurrentTasks != null ||
        maxConcurrentPersistWrites != null ||
        persistBatchSize != null) {
      // Reserved for API parity with other indicator services.
    }
  }

  List<PowerSystemPoint> _computePowerSystemSeries({
    required List<KLine> bars,
    required List<EmaPoint> emaPoints,
    required List<MacdPoint> macdPoints,
  }) {
    final emaValueByDate = <String, double>{};
    for (final point in emaPoints) {
      final key = _dateKey(point.datetime);
      emaValueByDate[key] = point.emaShort;
    }

    final macdHistByDate = <String, double>{};
    for (final point in macdPoints) {
      final key = _dateKey(point.datetime);
      macdHistByDate[key] = point.hist;
    }

    final points = <PowerSystemPoint>[];
    for (var i = 1; i < bars.length; i++) {
      final prevDateKey = _dateKey(bars[i - 1].datetime);
      final currentDateKey = _dateKey(bars[i].datetime);
      final prevEma = emaValueByDate[prevDateKey];
      final currentEma = emaValueByDate[currentDateKey];
      final prevMacd = macdHistByDate[prevDateKey];
      final currentMacd = macdHistByDate[currentDateKey];

      if (prevEma == null ||
          currentEma == null ||
          prevMacd == null ||
          currentMacd == null) {
        continue;
      }

      final emaSlopeUp = currentEma > prevEma;
      final emaSlopeDown = currentEma < prevEma;
      final macdSlopeUp = currentMacd > prevMacd;
      final macdSlopeDown = currentMacd < prevMacd;

      int state;
      if (emaSlopeUp && macdSlopeUp) {
        state = 1;
      } else if (emaSlopeDown && macdSlopeDown) {
        state = -1;
      } else {
        state = 0;
      }

      points.add(PowerSystemPoint(datetime: bars[i].datetime, state: state));
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

  String _buildSourceSignature(List<KLine> bars, KLineDataType dataType) {
    var rolling = 19;
    for (final bar in bars) {
      final ts = bar.datetime.millisecondsSinceEpoch;
      final closeScaled = (bar.close * 10000).round();
      rolling = _mixInt(rolling, ts);
      rolling = _mixInt(rolling, closeScaled);
    }

    final emaConfig = _emaService.configFor(dataType);
    final macdConfig = _macdService.configFor(dataType);
    return '${dataType.name}|${bars.length}|${bars.first.datetime.millisecondsSinceEpoch}|'
        '${bars.last.datetime.millisecondsSinceEpoch}|${emaConfig.shortPeriod}|'
        '${emaConfig.longPeriod}|${macdConfig.fastPeriod}|${macdConfig.slowPeriod}|'
        '${macdConfig.signalPeriod}|${macdConfig.windowMonths}|$rolling';
  }

  String _buildConfigSignature(KLineDataType dataType) {
    final ema = _emaService.configFor(dataType);
    final macd = _macdService.configFor(dataType);
    return '${ema.shortPeriod}|${ema.longPeriod}|${macd.fastPeriod}|'
        '${macd.slowPeriod}|${macd.signalPeriod}|${macd.windowMonths}';
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

  String _prewarmSnapshotStorageKeyFor(KLineDataType dataType) {
    return dataType == KLineDataType.weekly
        ? weeklyPrewarmSnapshotStorageKey
        : dailyPrewarmSnapshotStorageKey;
  }

  int _mixInt(int seed, int value) {
    return ((seed * 1315423911) ^ value) & 0x7fffffff;
  }

  String _seriesKey(String stockCode, KLineDataType dataType) {
    return '${stockCode}_${dataType.name}';
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }
}
