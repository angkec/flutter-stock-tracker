import 'dart:math';

import 'package:stock_rtwatcher/models/industry_buildup.dart';

class IndustryScoreEngine {
  static double computeBreadthGate(
    double? breadth, {
    IndustryScoreConfig config = const IndustryScoreConfig(),
  }) {
    if (breadth == null || !breadth.isFinite) {
      return config.minGate;
    }
    final denominator = config.b1 - config.b0;
    if (denominator.abs() < 1e-12) {
      return config.maxGate;
    }

    final normalized = (breadth - config.b0) / denominator;
    if (normalized < config.minGate) return config.minGate;
    if (normalized > config.maxGate) return config.maxGate;
    return normalized;
  }

  static ({
    double zPos,
    double breadthGate,
    double rawScore,
    bool hasValidInput,
  })
  computeRawScoreComponents({
    required double? z,
    required double? q,
    required double? breadth,
    IndustryScoreConfig config = const IndustryScoreConfig(),
  }) {
    final gate = computeBreadthGate(breadth, config: config);
    if (!_isFiniteNumber(z) ||
        !_isFiniteNumber(q) ||
        !_isFiniteNumber(breadth)) {
      return (
        zPos: 0.0,
        breadthGate: gate,
        rawScore: 0.0,
        hasValidInput: false,
      );
    }

    final zPos = max(z!, 0.0);
    final qSafe = q!;
    final rawScore = log(1 + zPos) * qSafe * gate;
    if (!rawScore.isFinite || rawScore.isNaN) {
      return (
        zPos: zPos,
        breadthGate: gate,
        rawScore: 0.0,
        hasValidInput: false,
      );
    }

    return (
      zPos: zPos,
      breadthGate: gate,
      rawScore: rawScore,
      hasValidInput: true,
    );
  }

  static List<IndustryBuildupDailyRecord> enrichAndRank(
    List<IndustryBuildupDailyRecord> records, {
    IndustryScoreConfig config = const IndustryScoreConfig(),
  }) {
    if (records.isEmpty) return const <IndustryBuildupDailyRecord>[];

    final sortedRecords = List<IndustryBuildupDailyRecord>.from(records)
      ..sort((a, b) {
        final byDate = a.dateOnly.compareTo(b.dateOnly);
        if (byDate != 0) return byDate;
        return a.industry.compareTo(b.industry);
      });

    final byDay = <int, List<IndustryBuildupDailyRecord>>{};
    final emaByIndustry = <String, double>{};

    for (final record in sortedRecords) {
      final score = computeRawScoreComponents(
        z: record.zRel,
        q: record.q,
        breadth: record.breadth,
        config: config,
      );

      final previousEma = emaByIndustry[record.industry];
      final scoreEma = _computeEma(
        previousEma: previousEma,
        rawScore: score.rawScore,
        alpha: config.alpha,
        hasValidInput: score.hasValidInput,
      );
      emaByIndustry[record.industry] = scoreEma;

      final enriched = IndustryBuildupDailyRecord(
        date: record.date,
        industry: record.industry,
        zRel: record.zRel,
        zPos: score.zPos,
        breadth: record.breadth,
        breadthGate: score.breadthGate,
        q: record.q,
        rawScore: score.rawScore,
        scoreEma: scoreEma,
        xI: record.xI,
        xM: record.xM,
        passedCount: record.passedCount,
        memberCount: record.memberCount,
        rank: record.rank,
        rankChange: record.rankChange,
        rankArrow: record.rankArrow,
        updatedAt: record.updatedAt,
      );

      final dayKey = _dayKey(record.date);
      byDay
          .putIfAbsent(dayKey, () => <IndustryBuildupDailyRecord>[])
          .add(enriched);
    }

    final ranked = <IndustryBuildupDailyRecord>[];
    final previousRanks = <String, int>{};
    final dayKeys = byDay.keys.toList()..sort();

    for (final dayKey in dayKeys) {
      final dayRecords = byDay[dayKey]!
        ..sort((a, b) {
          final byScore = b.scoreEma.compareTo(a.scoreEma);
          if (byScore != 0) return byScore;
          return a.industry.compareTo(b.industry);
        });

      for (var i = 0; i < dayRecords.length; i++) {
        final base = dayRecords[i];
        final rank = i + 1;
        final previousRank = previousRanks[base.industry];
        final rankChange = previousRank == null ? 0 : previousRank - rank;
        final rankArrow = _rankArrow(rankChange);

        ranked.add(
          IndustryBuildupDailyRecord(
            date: base.date,
            industry: base.industry,
            zRel: base.zRel,
            zPos: base.zPos,
            breadth: base.breadth,
            breadthGate: base.breadthGate,
            q: base.q,
            rawScore: base.rawScore,
            scoreEma: base.scoreEma,
            xI: base.xI,
            xM: base.xM,
            passedCount: base.passedCount,
            memberCount: base.memberCount,
            rank: rank,
            rankChange: rankChange,
            rankArrow: rankArrow,
            updatedAt: base.updatedAt,
          ),
        );

        previousRanks[base.industry] = rank;
      }
    }

    ranked.sort((a, b) {
      final byDate = a.dateOnly.compareTo(b.dateOnly);
      if (byDate != 0) return byDate;
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      return a.industry.compareTo(b.industry);
    });

    return ranked;
  }

  static bool _isFiniteNumber(double? value) {
    return value != null && value.isFinite && !value.isNaN;
  }

  static int _dayKey(DateTime date) {
    return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
  }

  static double _computeEma({
    required double? previousEma,
    required double rawScore,
    required double alpha,
    required bool hasValidInput,
  }) {
    if (previousEma == null) {
      return rawScore;
    }
    if (!hasValidInput) {
      return previousEma;
    }
    return alpha * rawScore + (1 - alpha) * previousEma;
  }

  static String _rankArrow(int rankChange) {
    if (rankChange > 0) return '↑';
    if (rankChange < 0) return '↓';
    return '→';
  }
}
