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
  static const int _defaultMaxConcurrentPrewarm = 6;
  static const int _defaultPersistBatchSize = 120;

  final DataRepository _repository;
  final MacdCacheStore _cacheStore;
  final Map<String, _MacdMemoryEntry> _memoryCache =
      <String, _MacdMemoryEntry>{};

  MacdConfig _config = MacdConfig.defaults;

  MacdIndicatorService({
    required DataRepository repository,
    MacdCacheStore? cacheStore,
  }) : _repository = repository,
       _cacheStore = cacheStore ?? MacdCacheStore();

  MacdConfig get config => _config;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(configStorageKey);
      if (raw == null || raw.isEmpty) {
        _config = MacdConfig.defaults;
        return;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _config = MacdConfig.fromJson(json);
    } catch (_) {
      _config = MacdConfig.defaults;
    }
  }

  Future<void> updateConfig(MacdConfig newConfig) async {
    if (!newConfig.isValid) {
      throw ArgumentError('Invalid MACD config');
    }
    _config = newConfig;
    _memoryCache.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(configStorageKey, jsonEncode(_config.toJson()));
    notifyListeners();
  }

  Future<void> resetConfig() async {
    await updateConfig(MacdConfig.defaults);
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
    bool persistToDisk = true,
    void Function(MacdCacheSeries series)? onSeriesComputed,
  }) async {
    if (bars.isEmpty) {
      return const <MacdPoint>[];
    }

    final sortedBars = _normalizeBarsOrder(bars);
    final signature = _buildSourceSignature(sortedBars);
    final cacheKey = _seriesKey(stockCode, dataType);

    final memory = _memoryCache[cacheKey];
    if (memory != null &&
        memory.sourceSignature == signature &&
        memory.config == _config) {
      return memory.points;
    }

    final disk = await _cacheStore.loadSeries(
      stockCode: stockCode,
      dataType: dataType,
    );

    if (disk != null &&
        disk.sourceSignature == signature &&
        disk.config == _config) {
      _memoryCache[cacheKey] = _MacdMemoryEntry(
        config: disk.config,
        sourceSignature: disk.sourceSignature,
        points: disk.points,
      );
      return disk.points;
    }

    final computed = _computeMacdSeries(sortedBars, _config);
    final computedSeries = MacdCacheSeries(
      stockCode: stockCode,
      dataType: dataType,
      config: _config,
      sourceSignature: signature,
      points: computed,
    );

    if (persistToDisk) {
      await _cacheStore.saveSeries(
        stockCode: stockCode,
        dataType: dataType,
        config: _config,
        sourceSignature: signature,
        points: computed,
      );
    } else {
      onSeriesComputed?.call(computedSeries);
    }

    _memoryCache[cacheKey] = _MacdMemoryEntry(
      config: _config,
      sourceSignature: signature,
      points: computed,
    );
    return computed;
  }

  Future<void> prewarmFromBars({
    required KLineDataType dataType,
    required Map<String, List<KLine>> barsByStockCode,
    int? maxConcurrentTasks,
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

      await _cacheStore.saveAll(batch, maxConcurrentWrites: 1);
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
        await getOrComputeFromBars(
          stockCode: entry.key,
          dataType: dataType,
          bars: entry.value,
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
    void Function(int current, int total)? onProgress,
  }) async {
    if (stockCodes.isEmpty) {
      onProgress?.call(1, 1);
      return;
    }

    final barsByStock = await _repository.getKlines(
      stockCodes: stockCodes,
      dateRange: dateRange,
      dataType: dataType,
    );

    await prewarmFromBars(
      dataType: dataType,
      barsByStockCode: barsByStock,
      onProgress: onProgress,
    );
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

  String _buildSourceSignature(List<KLine> bars) {
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
    return '${_config.fastPeriod}|${_config.slowPeriod}|'
        '${_config.signalPeriod}|${_config.windowMonths}|'
        '$length|$firstTs|$lastTs|$rolling';
  }

  int _mixInt(int seed, int value) {
    return ((seed * 1315423911) ^ value) & 0x7fffffff;
  }

  String _seriesKey(String stockCode, KLineDataType dataType) {
    return '${stockCode}_${dataType.name}';
  }
}
