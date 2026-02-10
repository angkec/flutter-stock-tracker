import 'dart:math';

import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/services/industry_buildup/industry_buildup_pipeline_models.dart';
import 'package:stock_rtwatcher/services/industry_score_engine.dart';

abstract class IndustryBuildUpComputer {
  IndustryBuildUpComputeResult compute({
    required IndustryBuildUpLoadResult loadResult,
    required IndustryScoreConfig scoreConfig,
    required DateTime now,
    required void Function(int current, int total) onAggregationProgress,
    required void Function(int current, int total) onScoringProgress,
  });
}

class DefaultIndustryBuildUpComputer implements IndustryBuildUpComputer {
  static const int _zWindow = 20;
  static const double _weightCap = 0.08;
  static const double _breadthLow = 0.30;
  static const double _breadthHigh = 0.55;
  static const int _minPassedMembers = 8;
  static const double _hhi0 = 0.06;
  static const double _concLambda = 12.0;
  static const int _persistLookback = 5;
  static const double _persistZ = 1.0;
  static const int _persistNeed = 3;
  static const double _eps = 1e-9;

  @override
  IndustryBuildUpComputeResult compute({
    required IndustryBuildUpLoadResult loadResult,
    required IndustryScoreConfig scoreConfig,
    required DateTime now,
    required void Function(int current, int total) onAggregationProgress,
    required void Function(int current, int total) onScoringProgress,
  }) {
    final intermediatesByIndustry =
        <String, List<IndustryBuildUpIndustryDayIntermediate>>{};
    final aggregationTotal =
        loadResult.sortedTradingDates.length * loadResult.industryStocks.length;
    var aggregationCurrent = 0;
    onAggregationProgress(0, max(1, aggregationTotal));

    for (final date in loadResult.sortedTradingDates) {
      final dateKey = industryBuildUpDateKey(date);

      final marketFeatures = <IndustryBuildUpStockDayFeature>[];
      for (final code in loadResult.stockCodes) {
        final feature = loadResult.stockFeatures[code]?[dateKey];
        if (feature != null && feature.passed) {
          marketFeatures.add(feature);
        }
      }
      if (marketFeatures.isEmpty &&
          dateKey == loadResult.latestTradingDateKey) {
        for (final code in loadResult.stockCodes) {
          final feature = loadResult.stockFeatures[code]?[dateKey];
          if (feature != null && feature.minuteCount > 0) {
            marketFeatures.add(feature);
          }
        }
      }
      final xM = marketFeatures.isEmpty
          ? 0.0
          : marketFeatures.map((f) => f.xHat).reduce((a, b) => a + b) /
                marketFeatures.length;

      for (final entry in loadResult.industryStocks.entries) {
        aggregationCurrent++;
        final industry = entry.key;
        final memberCodes = entry.value;
        final memberCount = memberCodes.length;

        final features = <IndustryBuildUpStockDayFeature>[];
        for (final code in memberCodes) {
          final feature = loadResult.stockFeatures[code]?[dateKey];
          if (feature != null && feature.passed) {
            features.add(feature);
          }
        }
        if (features.isEmpty && dateKey == loadResult.latestTradingDateKey) {
          for (final code in memberCodes) {
            final feature = loadResult.stockFeatures[code]?[dateKey];
            if (feature != null && feature.minuteCount > 0) {
              features.add(feature);
            }
          }
        }

        final passedCount = features.length;
        if (passedCount == 0 || memberCount == 0) {
          onAggregationProgress(aggregationCurrent, max(1, aggregationTotal));
          continue;
        }

        final weights = _buildWeights(features);
        var xI = 0.0;
        var hhi = 0.0;
        var positiveCount = 0;
        for (var i = 0; i < features.length; i++) {
          final weight = weights[i];
          xI += weight * features[i].xHat;
          hhi += weight * weight;
          if (features[i].xHat > 0) {
            positiveCount++;
          }
        }
        final breadth = positiveCount / passedCount;

        intermediatesByIndustry.putIfAbsent(industry, () => []);
        intermediatesByIndustry[industry]!.add(
          IndustryBuildUpIndustryDayIntermediate(
            date: date,
            xI: xI,
            xM: xM,
            xRel: xI - xM,
            breadth: breadth,
            passedCount: passedCount,
            memberCount: memberCount,
            hhi: hhi,
          ),
        );
        onAggregationProgress(aggregationCurrent, max(1, aggregationTotal));
      }
    }

    final recordsByDate = <int, List<IndustryBuildupDailyRecord>>{};
    onScoringProgress(0, max(1, intermediatesByIndustry.length));
    var scoringCurrent = 0;
    for (final entry in intermediatesByIndustry.entries) {
      final industry = entry.key;
      final series = entry.value..sort((a, b) => a.date.compareTo(b.date));
      final zSeries = <double>[];

      for (var i = 0; i < series.length; i++) {
        final windowStart = max(0, i - _zWindow + 1);
        final window = series.sublist(windowStart, i + 1);
        final xRelValues = window.map((d) => d.xRel).toList();
        final mu = xRelValues.reduce((a, b) => a + b) / xRelValues.length;
        var sigmaSquare = 0.0;
        for (final value in xRelValues) {
          final diff = value - mu;
          sigmaSquare += diff * diff;
        }
        final sigma = sqrt(sigmaSquare / xRelValues.length);
        final zRel = (series[i].xRel - mu) / (sigma + _eps);
        zSeries.add(zRel);

        final qCoverage = min(1.0, series[i].passedCount / _minPassedMembers);
        final qBreadth = _clip01(
          (series[i].breadth - _breadthLow) / (_breadthHigh - _breadthLow),
        );
        final qConc = exp(-_concLambda * max(0.0, series[i].hhi - _hhi0));

        final persistStart = max(0, zSeries.length - _persistLookback);
        final persistCount = zSeries
            .sublist(persistStart)
            .where((z) => z > _persistZ)
            .length;
        final qPersist = persistCount >= _persistNeed ? 1.0 : 0.6;
        final q = _clip01(qCoverage * qBreadth * qConc * qPersist);

        final record = IndustryBuildupDailyRecord(
          date: series[i].date,
          industry: industry,
          zRel: zRel,
          breadth: series[i].breadth,
          q: q,
          xI: series[i].xI,
          xM: series[i].xM,
          passedCount: series[i].passedCount,
          memberCount: series[i].memberCount,
          rank: 0,
          updatedAt: now,
        );

        recordsByDate.putIfAbsent(
          industryBuildUpDateKey(series[i].date),
          () => [],
        );
        recordsByDate[industryBuildUpDateKey(series[i].date)]!.add(record);
      }

      scoringCurrent++;
      onScoringProgress(scoringCurrent, max(1, intermediatesByIndustry.length));
    }

    final baseRecords = recordsByDate.values
        .expand((dayRecords) => dayRecords)
        .toList(growable: false);
    final finalRecords = IndustryScoreEngine.enrichAndRank(
      baseRecords,
      config: scoreConfig,
    );

    final hasLatestTradingDayResult = finalRecords.any(
      (record) =>
          industryBuildUpDateKey(record.date) ==
          loadResult.latestTradingDateKey,
    );

    return IndustryBuildUpComputeResult(
      finalRecords: finalRecords,
      hasLatestTradingDayResult: hasLatestTradingDayResult,
    );
  }

  List<double> _buildWeights(List<IndustryBuildUpStockDayFeature> features) {
    if (features.isEmpty) return const [];
    final sumAmount = features.fold<double>(0, (sum, item) => sum + item.aSum);
    final raw = <double>[];
    if (sumAmount <= 0) {
      final equal = 1.0 / features.length;
      for (var i = 0; i < features.length; i++) {
        raw.add(equal);
      }
    } else {
      for (final feature in features) {
        raw.add(feature.aSum / sumAmount);
      }
    }

    final capped = raw.map((w) => min(w, _weightCap)).toList();
    final cappedSum = capped.fold<double>(0, (sum, item) => sum + item);
    if (cappedSum <= 0) {
      final equal = 1.0 / features.length;
      return List<double>.filled(features.length, equal);
    }
    return capped.map((w) => w / cappedSum).toList();
  }

  double _clip01(double value) {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}
