import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/adaptive_weekly_config.dart';
import 'package:stock_rtwatcher/services/adaptive_topk_calibrator.dart';

void main() {
  group('adaptive top-k calibrator', () {
    test('fBreadth clamps gate between minGate and maxGate', () {
      expect(fBreadth(0.0), 0.5);
      expect(fBreadth(0.25), 0.5);
      expect(fBreadth(0.375), 0.5);
      expect(fBreadth(0.50), 1.0);
      expect(fBreadth(0.80), 1.0);
    });

    test('computeScore multiplies z * q * gated breadth', () {
      final score = computeScore(1.5, 0.6, 0.2);
      expect(score, closeTo(0.45, 1e-9));
    });

    test('selectTopK filters invalid rows and sorts by score desc', () {
      final records = <AdaptiveIndustryDayRecord>[
        AdaptiveIndustryDayRecord(
          industry: 'A',
          day: DateTime(2026, 2, 6),
          z: 1.5,
          q: 0.6,
          breadth: 0.4,
        ),
        AdaptiveIndustryDayRecord(
          industry: 'B',
          day: DateTime(2026, 2, 6),
          z: 1.8,
          q: 0.7,
          breadth: 0.3,
        ),
        AdaptiveIndustryDayRecord(
          industry: 'C',
          day: DateTime(2026, 2, 6),
          z: 2.0,
          q: null,
          breadth: 0.4,
        ),
        AdaptiveIndustryDayRecord(
          industry: 'D',
          day: DateTime(2026, 2, 6),
          z: double.nan,
          q: 0.9,
          breadth: 0.5,
        ),
      ];

      final top = selectTopK(records, 2);
      expect(top.length, 2);
      expect(top[0].industry, 'B');
      expect(top[1].industry, 'A');
      expect(top[0].score, greaterThan(top[1].score));
    });

    test('percentile uses sorted linear interpolation', () {
      expect(percentile([1, 2, 3, 4], 0.0), 1.0);
      expect(percentile([1, 2, 3, 4], 1.0), 4.0);
      expect(percentile([1, 2, 3, 4], 0.95), closeTo(3.85, 1e-9));
    });

    test('deriveThresholdsFromCandidates applies buffers and floors', () {
      final candidates = <AdaptiveCandidate>[
        AdaptiveCandidate(
          industry: 'XXX',
          day: DateTime(2026, 2, 6),
          z: 1.62,
          q: 0.71,
          breadth: 0.41,
          score: 1.06,
        ),
        AdaptiveCandidate(
          industry: 'YYY',
          day: DateTime(2026, 2, 6),
          z: 1.44,
          q: 0.64,
          breadth: 0.33,
          score: 0.89,
        ),
      ];

      final thresholds = deriveThresholdsFromCandidates(
        candidates,
        const AdaptiveFloors(z: 0.8, q: 0.5, breadth: 0.2),
        const AdaptiveBuffers(z: 0.05, q: 0.02, breadth: 0.02),
      );

      expect(thresholds.z, closeTo(1.39, 1e-9));
      expect(thresholds.q, closeTo(0.62, 1e-9));
      expect(thresholds.breadth, closeTo(0.31, 1e-9));
    });

    test(
      'buildWeeklyConfig returns strong for clear winner in strong week',
      () {
        final config = buildWeeklyConfig([
          _row('半导体', DateTime(2026, 2, 2), 1.80, 0.80, 0.45),
          _row('军工', DateTime(2026, 2, 3), 1.20, 0.70, 0.40),
          _row('算力', DateTime(2026, 2, 4), 1.10, 0.60, 0.35),
          _row('银行', DateTime(2026, 2, 5), 1.05, 0.58, 0.34),
          _row('煤炭', DateTime(2026, 2, 6), 1.00, 0.56, 0.30),
        ]);

        expect(config.week, '2026-W06');
        expect(config.mode, 'adaptive_topk');
        expect(config.status, AdaptiveWeeklyStatus.strong);
        expect(config.candidates.length, 3);
        expect(config.candidates.first.industry, '半导体');
        expect(config.thresholds.z, greaterThanOrEqualTo(config.floors.z));
        expect(config.thresholds.q, greaterThanOrEqualTo(config.floors.q));
        expect(
          config.thresholds.breadth,
          greaterThanOrEqualTo(config.floors.breadth),
        );
      },
    );

    test(
      'buildWeeklyConfig returns weak when winner margin is insufficient',
      () {
        const params = AdaptiveTopKParams(k: 2, minRecords: 2);
        final config = buildWeeklyConfig([
          _row('A', DateTime(2026, 2, 6), 1.60, 0.70, 0.50),
          _row('B', DateTime(2026, 2, 6), 1.55, 0.69, 0.50),
          _row('C', DateTime(2026, 2, 6), 1.20, 0.60, 0.40),
        ], params: params);

        expect(config.status, AdaptiveWeeklyStatus.weak);
        expect(config.candidates.length, 2);
      },
    );

    test('buildWeeklyConfig returns none when z p95 is too low', () {
      final config = buildWeeklyConfig([
        _row('A', DateTime(2026, 2, 6), 0.9, 0.9, 0.5),
        _row('B', DateTime(2026, 2, 6), 0.8, 0.8, 0.4),
        _row('C', DateTime(2026, 2, 6), 0.7, 0.7, 0.3),
      ]);

      expect(config.status, AdaptiveWeeklyStatus.none);
    });

    test(
      'buildWeeklyConfig returns none when valid records are insufficient',
      () {
        final config = buildWeeklyConfig([
          _row('A', DateTime(2026, 2, 6), 1.3, 0.8, 0.4),
          _row('B', DateTime(2026, 2, 6), double.nan, 0.8, 0.4),
          _row('C', DateTime(2026, 2, 6), 1.1, null, 0.4),
        ]);

        expect(config.status, AdaptiveWeeklyStatus.none);
        expect(config.candidates.length, 1);
      },
    );

    test(
      'buildWeeklyConfig only uses latest ISO week from multi-week input',
      () {
        final config = buildWeeklyConfig([
          _row('上周高分', DateTime(2026, 1, 30), 3.0, 1.0, 0.6),
          _row('本周A', DateTime(2026, 2, 3), 1.5, 0.7, 0.4),
          _row('本周B', DateTime(2026, 2, 4), 1.4, 0.7, 0.4),
          _row('本周C', DateTime(2026, 2, 5), 1.3, 0.7, 0.4),
        ]);

        expect(config.week, '2026-W06');
        expect(
          config.candidates.map((e) => e.industry),
          isNot(contains('上周高分')),
        );
      },
    );
  });
}

AdaptiveIndustryDayRecord _row(
  String industry,
  DateTime day,
  double? z,
  double? q,
  double? breadth,
) {
  return AdaptiveIndustryDayRecord(
    industry: industry,
    day: day,
    z: z,
    q: q,
    breadth: breadth,
  );
}
