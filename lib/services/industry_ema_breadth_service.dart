import 'dart:math';

import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_cache_store.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

class IndustryEmaBreadthService {
  IndustryEmaBreadthService({
    required IndustryService industryService,
    required DailyKlineCacheStore dailyCacheStore,
    required EmaCacheStore emaCacheStore,
    IndustryEmaBreadthCacheStore? cacheStore,
  }) : _industryService = industryService,
       _dailyCacheStore = dailyCacheStore,
       _emaCacheStore = emaCacheStore,
       _cacheStore = cacheStore ?? IndustryEmaBreadthCacheStore();

  final IndustryService _industryService;
  final DailyKlineCacheStore _dailyCacheStore;
  final EmaCacheStore _emaCacheStore;
  final IndustryEmaBreadthCacheStore _cacheStore;
  static const int _maxConcurrentWeeklyEmaLoads = 8;

  Future<IndustryEmaBreadthSeries?> getCachedSeries(String industry) {
    return _cacheStore.loadSeries(industry);
  }

  Future<Map<String, IndustryEmaBreadthSeries>> recomputeAllIndustries({
    required DateTime startDate,
    required DateTime endDate,
    void Function(int current, int total, String stage)? onProgress,
  }) async {
    final normalizedStart = _normalizeDate(startDate);
    final normalizedEnd = _normalizeDate(endDate);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError('endDate must be on/after startDate');
    }

    final industries = _industryService.allIndustries.toList(growable: false)
      ..sort();
    final stocksByIndustry = <String, List<String>>{};
    final allStocks = <String>{};
    for (final industry in industries) {
      final stockCodes = _industryService.getStocksByIndustry(industry)..sort();
      stocksByIndustry[industry] = stockCodes;
      allStocks.addAll(stockCodes);
    }

    final daySpan = normalizedEnd.difference(normalizedStart).inDays + 1;
    final targetBars = max(1, daySpan + 10);
    final lookbackMonths = _lookbackMonths(normalizedStart, normalizedEnd);
    final dailyByStock = await _dailyCacheStore.loadForStocksWithStatus(
      allStocks.toList(growable: false),
      anchorDate: normalizedEnd,
      targetBars: targetBars,
      lookbackMonths: lookbackMonths,
    );

    final dailyCloseByStock = <String, Map<DateTime, double>>{};
    final tradingDays = <DateTime>{};
    for (final entry in dailyByStock.entries) {
      if (entry.value.status != DailyKlineCacheLoadStatus.ok) {
        continue;
      }
      final map = _dailyCloseByDate(
        entry.value.bars,
        startDate: normalizedStart,
        endDate: normalizedEnd,
      );
      if (map.isNotEmpty) {
        dailyCloseByStock[entry.key] = map;
        tradingDays.addAll(map.keys);
      }
    }
    final axisDates = tradingDays.toList(growable: false)
      ..sort((a, b) => a.compareTo(b));

    final weeklySeriesByStock = await _emaCacheStore.loadAllSeries(
      allStocks,
      dataType: KLineDataType.weekly,
      maxConcurrentLoads: _maxConcurrentWeeklyEmaLoads,
    );

    final emaByStock = <String, List<EmaPoint>>{};
    for (final stockCode in allStocks) {
      final weeklySeries = weeklySeriesByStock[stockCode];
      if (weeklySeries == null || weeklySeries.points.isEmpty) {
        continue;
      }
      final points = List<EmaPoint>.from(weeklySeries.points)
        ..sort((a, b) => a.datetime.compareTo(b.datetime));
      emaByStock[stockCode] = points;
    }

    final emaByStockByDate = <String, Map<DateTime, double?>>{};
    for (final stockCode in allStocks) {
      final points = emaByStock[stockCode];
      if (points == null || points.isEmpty) {
        continue;
      }

      var cursor = 0;
      double? current;
      final byDate = <DateTime, double?>{};
      for (final date in axisDates) {
        while (cursor < points.length) {
          final pointDate = _normalizeDate(points[cursor].datetime);
          if (pointDate.isAfter(date)) {
            break;
          }
          current = points[cursor].emaShort;
          cursor++;
        }
        byDate[date] = current;
      }
      emaByStockByDate[stockCode] = byDate;
    }

    final seriesByIndustry = <String, IndustryEmaBreadthSeries>{};
    final totalUnits = max(1, industries.length * axisDates.length);
    onProgress?.call(0, totalUnits, '准备重算行业EMA广度...');
    var completedUnits = 0;
    for (final industry in industries) {
      final stockCodes = stocksByIndustry[industry] ?? const <String>[];
      final points = <IndustryEmaBreadthPoint>[];

      for (final date in axisDates) {
        var aboveCount = 0;
        var validCount = 0;
        var missingCount = 0;

        for (final stockCode in stockCodes) {
          final close = dailyCloseByStock[stockCode]?[date];
          final ema = emaByStockByDate[stockCode]?[date];
          if (close == null || ema == null) {
            missingCount++;
            continue;
          }

          validCount++;
          if (close > ema) {
            aboveCount++;
          }
        }

        points.add(
          IndustryEmaBreadthPoint(
            date: date,
            percent: validCount > 0 ? (aboveCount / validCount) * 100 : null,
            aboveCount: aboveCount,
            validCount: validCount,
            missingCount: missingCount,
          ),
        );

        completedUnits++;
        onProgress?.call(
          completedUnits,
          totalUnits,
          '计算中 ${industry} ${_dateLabel(date)}',
        );
        if (completedUnits % 64 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      seriesByIndustry[industry] = IndustryEmaBreadthSeries(
        industry: industry,
        points: points,
      );
    }

    await _cacheStore.saveAll(seriesByIndustry.values.toList(growable: false));
    onProgress?.call(totalUnits, totalUnits, '重算完成');
    return seriesByIndustry;
  }

  Map<DateTime, double> _dailyCloseByDate(
    List<KLine> bars, {
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final result = <DateTime, double>{};
    for (final bar in bars) {
      final date = _normalizeDate(bar.datetime);
      if (date.isBefore(startDate) || date.isAfter(endDate)) {
        continue;
      }
      result[date] = bar.close;
    }
    return result;
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dateLabel(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  int _lookbackMonths(DateTime startDate, DateTime endDate) {
    final monthDiff =
        (endDate.year - startDate.year) * 12 + endDate.month - startDate.month;
    return max(1, monthDiff + 1);
  }
}
