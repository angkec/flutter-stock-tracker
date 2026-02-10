import 'dart:math';

import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/industry_buildup/industry_buildup_pipeline_models.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

abstract class IndustryBuildUpLoader {
  Future<IndustryBuildUpLoadOutcome> load({
    required DataRepository repository,
    required IndustryService industryService,
    required void Function(int current, int total) onTradingDateScanProgress,
    required void Function(int current, int total) onPreprocessProgress,
  });
}

class DefaultIndustryBuildUpLoader implements IndustryBuildUpLoader {
  static const double _tau = 0.001;
  static const int _expectedMinutes = 240;
  static const double _minDailyAmount = 2e7;
  static const double _minMinuteCoverage = 0.9;
  static const double _maxMinuteVolShare = 0.12;
  static const double _eps = 1e-9;

  @override
  Future<IndustryBuildUpLoadOutcome> load({
    required DataRepository repository,
    required IndustryService industryService,
    required void Function(int current, int total) onTradingDateScanProgress,
    required void Function(int current, int total) onPreprocessProgress,
  }) async {
    final industryStocks = _buildIndustryStocks(industryService);
    final stockCodes = industryStocks.values.expand((e) => e).toSet().toList()
      ..sort();
    if (stockCodes.isEmpty) {
      return IndustryBuildUpLoadOutcome.failure('无行业股票映射');
    }

    final probeRange = DateRange(
      DateTime.now().subtract(const Duration(days: 60)),
      DateTime.now(),
    );
    var tradingDates = await repository.getTradingDates(probeRange);
    if (tradingDates.isEmpty) {
      tradingDates = await _deriveTradingDatesFromMinuteBars(
        repository: repository,
        stockCodes: stockCodes,
        dateRange: probeRange,
        onProgress: onTradingDateScanProgress,
      );
    }
    if (tradingDates.isEmpty) {
      return IndustryBuildUpLoadOutcome.failure('无交易日数据');
    }

    final sortedTradingDates =
        tradingDates.map(industryBuildUpDateOnly).toSet().toList()..sort();
    final latestTradingDate = sortedTradingDates.last;
    final latestTradingDateKey = industryBuildUpDateKey(latestTradingDate);
    final start = sortedTradingDates.first;
    final end = sortedTradingDates.last.add(const Duration(days: 1));
    final dateRange = DateRange(
      start,
      end.subtract(const Duration(milliseconds: 1)),
    );

    final stockFeatures = <String, Map<int, IndustryBuildUpStockDayFeature>>{};
    onPreprocessProgress(0, stockCodes.length);
    for (var i = 0; i < stockCodes.length; i++) {
      final code = stockCodes[i];
      final bars =
          (await repository.getKlines(
            stockCodes: [code],
            dateRange: dateRange,
            dataType: KLineDataType.oneMinute,
          ))[code] ??
          const <KLine>[];
      stockFeatures[code] = _computeStockDayFeatures(bars);
      onPreprocessProgress(i + 1, stockCodes.length);
    }

    return IndustryBuildUpLoadOutcome.success(
      IndustryBuildUpLoadResult(
        industryStocks: industryStocks,
        stockCodes: stockCodes,
        sortedTradingDates: sortedTradingDates,
        latestTradingDate: latestTradingDate,
        latestTradingDateKey: latestTradingDateKey,
        dateRange: dateRange,
        stockFeatures: stockFeatures,
      ),
    );
  }

  Map<String, List<String>> _buildIndustryStocks(
    IndustryService industryService,
  ) {
    final result = <String, List<String>>{};
    for (final industry in industryService.allIndustries) {
      final stocks = industryService.getStocksByIndustry(industry);
      if (stocks.isNotEmpty) {
        result[industry] = stocks;
      }
    }
    return result;
  }

  Map<int, IndustryBuildUpStockDayFeature> _computeStockDayFeatures(
    List<KLine> bars,
  ) {
    final byDate = <int, List<KLine>>{};
    for (final bar in bars) {
      byDate.putIfAbsent(industryBuildUpDateKey(bar.datetime), () => []);
      byDate[industryBuildUpDateKey(bar.datetime)]!.add(bar);
    }

    final result = <int, IndustryBuildUpStockDayFeature>{};
    for (final entry in byDate.entries) {
      final dayBars = entry.value
        ..sort((a, b) => a.datetime.compareTo(b.datetime));
      if (dayBars.isEmpty) continue;

      var pSum = 0.0;
      var vSum = 0.0;
      var aSum = 0.0;
      var maxV = 0.0;
      for (final bar in dayBars) {
        vSum += bar.volume;
        aSum += bar.amount;
        if (bar.volume > maxV) {
          maxV = bar.volume;
        }
      }

      for (var i = 1; i < dayBars.length; i++) {
        final prevClose = dayBars[i - 1].close;
        if (prevClose <= 0) continue;
        final r = log(dayBars[i].close / prevClose);
        final phi = _tanh(r / _tau);
        pSum += dayBars[i].volume * phi;
      }

      final xHat = pSum / (vSum + _eps);
      final coverage = dayBars.length / _expectedMinutes;
      final maxShare = maxV / (vSum + _eps);
      final passed =
          aSum >= _minDailyAmount &&
          coverage >= _minMinuteCoverage &&
          maxShare <= _maxMinuteVolShare;

      result[entry.key] = IndustryBuildUpStockDayFeature(
        xHat: xHat,
        vSum: vSum,
        aSum: aSum,
        maxShare: maxShare,
        minuteCount: dayBars.length,
        passed: passed,
      );
    }

    return result;
  }

  Future<List<DateTime>> _deriveTradingDatesFromMinuteBars({
    required DataRepository repository,
    required List<String> stockCodes,
    required DateRange dateRange,
    required void Function(int current, int total) onProgress,
  }) async {
    final dates = <DateTime>{};
    for (var i = 0; i < stockCodes.length; i++) {
      final code = stockCodes[i];
      final bars =
          (await repository.getKlines(
            stockCodes: [code],
            dateRange: dateRange,
            dataType: KLineDataType.oneMinute,
          ))[code] ??
          const <KLine>[];
      for (final bar in bars) {
        dates.add(industryBuildUpDateOnly(bar.datetime));
      }
      onProgress(i + 1, stockCodes.length);
    }
    final result = dates.toList()..sort();
    return result;
  }

  double _tanh(double x) {
    final e2x = exp(2 * x);
    return (e2x - 1) / (e2x + 1);
  }
}
