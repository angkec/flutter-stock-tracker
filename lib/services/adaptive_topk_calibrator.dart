import 'dart:math';

import 'package:stock_rtwatcher/models/adaptive_weekly_config.dart';

double fBreadth(
  double b, {
  double b0 = 0.25,
  double b1 = 0.50,
  double minGate = 0.5,
  double maxGate = 1.0,
}) {
  if (!b.isFinite) return minGate;
  if (b1 <= b0) return b >= b1 ? maxGate : minGate;
  final scaled = (b - b0) / (b1 - b0);
  return _clip(scaled, minGate, maxGate);
}

double computeScore(
  double z,
  double q,
  double breadth, {
  double b0 = 0.25,
  double b1 = 0.50,
  double minGate = 0.5,
  double maxGate = 1.0,
}) {
  return z *
      q *
      fBreadth(breadth, b0: b0, b1: b1, minGate: minGate, maxGate: maxGate);
}

List<AdaptiveCandidate> selectTopK(
  List<AdaptiveIndustryDayRecord> records,
  int k, {
  double b0 = 0.25,
  double b1 = 0.50,
  double minGate = 0.5,
  double maxGate = 1.0,
}) {
  if (k <= 0) return const [];

  final candidates = <AdaptiveCandidate>[];
  for (final record in records) {
    if (!_isValidRecord(record)) continue;
    final score = computeScore(
      record.z!,
      record.q!,
      record.breadth!,
      b0: b0,
      b1: b1,
      minGate: minGate,
      maxGate: maxGate,
    );
    if (!score.isFinite) continue;

    candidates.add(
      AdaptiveCandidate(
        industry: record.industry,
        day: _dateOnly(record.day),
        z: record.z!,
        q: record.q!,
        breadth: record.breadth!,
        score: score,
      ),
    );
  }

  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final byZ = b.z.compareTo(a.z);
    if (byZ != 0) return byZ;
    return a.industry.compareTo(b.industry);
  });

  return candidates.take(k).toList(growable: false);
}

AdaptiveThresholds deriveThresholdsFromCandidates(
  List<AdaptiveCandidate> candidates,
  AdaptiveFloors floors,
  AdaptiveBuffers buffers,
) {
  if (candidates.isEmpty) {
    return floors.asThresholds();
  }

  var zMin = candidates.first.z;
  var qMin = candidates.first.q;
  var breadthMin = candidates.first.breadth;

  for (final item in candidates.skip(1)) {
    if (item.z < zMin) zMin = item.z;
    if (item.q < qMin) qMin = item.q;
    if (item.breadth < breadthMin) breadthMin = item.breadth;
  }

  return AdaptiveThresholds(
    z: max(zMin - buffers.z, floors.z),
    q: max(qMin - buffers.q, floors.q),
    breadth: max(breadthMin - buffers.breadth, floors.breadth),
  );
}

double percentile(List<double> xs, double p) {
  final values = xs.where((value) => value.isFinite).toList()..sort();
  if (values.isEmpty) return double.nan;
  if (values.length == 1) return values.first;

  final normalizedP = _clip(p, 0.0, 1.0);
  final pos = (values.length - 1) * normalizedP;
  final lower = pos.floor();
  final upper = pos.ceil();
  if (lower == upper) return values[lower];

  final w = pos - lower;
  return values[lower] * (1 - w) + values[upper] * w;
}

AdaptiveWeeklyConfig buildWeeklyConfig(
  List<AdaptiveIndustryDayRecord> weekRecords, {
  AdaptiveTopKParams params = const AdaptiveTopKParams(),
  DateTime? referenceDay,
}) {
  final normalizedReferenceDay = referenceDay != null
      ? _dateOnly(referenceDay)
      : null;
  final validRecords = weekRecords.where(_isValidRecord).toList();
  final latestDay =
      normalizedReferenceDay ??
      _inferLatestDay(validRecords) ??
      _inferLatestDay(weekRecords) ??
      _dateOnly(DateTime.now());
  final weekKey = isoWeekKey(latestDay);

  final weekScoped = validRecords
      .where((record) => isoWeekKey(record.day) == weekKey)
      .toList();
  final candidates = selectTopK(
    weekScoped,
    params.k,
    b0: params.b0,
    b1: params.b1,
    minGate: params.minGate,
    maxGate: params.maxGate,
  );
  final thresholds = deriveThresholdsFromCandidates(
    candidates,
    params.floors,
    params.buffers,
  );

  AdaptiveWeeklyStatus status = AdaptiveWeeklyStatus.none;
  final enoughRecords = weekScoped.length >= max(1, params.minRecords);
  final zP95 = percentile(
    weekScoped.map((record) => record.z!).toList(growable: false),
    0.95,
  );

  if (enoughRecords && candidates.isNotEmpty && zP95 >= params.zP95Threshold) {
    if (candidates.length < 2) {
      status = AdaptiveWeeklyStatus.strong;
    } else {
      final s1 = candidates[0].score;
      final s2 = candidates[1].score;
      final ratioPass = s2 == 0 ? s1 > 0 : (s1 / s2) > params.winnerRatio;
      final diffPass = (s1 - s2) > params.winnerDiff;
      status = ratioPass || diffPass
          ? AdaptiveWeeklyStatus.strong
          : AdaptiveWeeklyStatus.weak;
    }
  }

  return AdaptiveWeeklyConfig(
    week: weekKey,
    k: params.k,
    floors: params.floors,
    thresholds: thresholds,
    candidates: candidates,
    status: status,
  );
}

String isoWeekKey(DateTime date) {
  final day = _dateOnly(date);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final isoYear = thursday.year;
  final jan4 = DateTime(isoYear, 1, 4);
  final firstThursday = jan4.add(
    Duration(days: DateTime.thursday - jan4.weekday),
  );
  final week = 1 + (thursday.difference(firstThursday).inDays ~/ 7);
  return '$isoYear-W${week.toString().padLeft(2, '0')}';
}

bool _isValidRecord(AdaptiveIndustryDayRecord record) {
  if (record.industry.trim().isEmpty) return false;
  return _isFinite(record.z) &&
      _isFinite(record.q) &&
      _isFinite(record.breadth);
}

bool _isFinite(double? value) => value != null && value.isFinite;

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime? _inferLatestDay(List<AdaptiveIndustryDayRecord> records) {
  if (records.isEmpty) return null;
  return records
      .map((record) => _dateOnly(record.day))
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

double _clip(double value, double lower, double upper) {
  if (value < lower) return lower;
  if (value > upper) return upper;
  return value;
}
