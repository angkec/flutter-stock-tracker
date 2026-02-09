import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/services/industry_score_engine.dart';

IndustryBuildupDailyRecord _record({
  required DateTime day,
  required String industry,
  required double z,
  required double q,
  required double breadth,
}) {
  return IndustryBuildupDailyRecord(
    date: day,
    industry: industry,
    zRel: z,
    breadth: breadth,
    q: q,
    xI: 0.1,
    xM: 0.05,
    passedCount: 10,
    memberCount: 20,
    rank: 0,
    updatedAt: DateTime(2026, 2, 7, 12),
  );
}

void main() {
  group('IndustryScoreEngine', () {
    test('breadthGate clips to configured range', () {
      const config = IndustryScoreConfig();

      expect(
        IndustryScoreEngine.computeBreadthGate(0.10, config: config),
        closeTo(0.5, 1e-9),
      );
      expect(
        IndustryScoreEngine.computeBreadthGate(0.45, config: config),
        closeTo(0.8, 1e-9),
      );
      expect(
        IndustryScoreEngine.computeBreadthGate(0.90, config: config),
        closeTo(1.0, 1e-9),
      );
    });

    test('rawScore falls back to 0 when input has null or NaN', () {
      const config = IndustryScoreConfig();

      final withNull = IndustryScoreEngine.computeRawScoreComponents(
        z: null,
        q: 0.8,
        breadth: 0.5,
        config: config,
      );
      expect(withNull.rawScore, 0.0);

      final withNaN = IndustryScoreEngine.computeRawScoreComponents(
        z: 1.0,
        q: double.nan,
        breadth: 0.5,
        config: config,
      );
      expect(withNaN.rawScore, 0.0);
    });

    test('EMA keeps continuity when days are missing in the middle', () {
      final records = [
        _record(
          day: DateTime(2026, 2, 3),
          industry: 'A',
          z: 1.0,
          q: 1.0,
          breadth: 0.5,
        ),
        _record(
          day: DateTime(2026, 2, 5),
          industry: 'A',
          z: 3.0,
          q: 1.0,
          breadth: 0.5,
        ),
      ];

      final scored = IndustryScoreEngine.enrichAndRank(records);
      scored.sort((a, b) => a.date.compareTo(b.date));

      final first = scored[0];
      final third = scored[1];

      expect(first.rawScore, closeTo(0.6931471806, 1e-6));
      expect(first.scoreEma, closeTo(0.6931471806, 1e-6));
      expect(third.rawScore, closeTo(1.3862943611, 1e-6));
      expect(third.scoreEma, closeTo(0.9010913347, 1e-6));
    });

    test('rank/rankChange/rankArrow are correct with stable tie-break', () {
      final records = [
        _record(
          day: DateTime(2026, 2, 3),
          industry: 'A',
          z: 1.0,
          q: 1.0,
          breadth: 0.5,
        ),
        _record(
          day: DateTime(2026, 2, 3),
          industry: 'B',
          z: 1.0,
          q: 1.0,
          breadth: 0.5,
        ),
        _record(
          day: DateTime(2026, 2, 4),
          industry: 'A',
          z: 0.2,
          q: 1.0,
          breadth: 0.5,
        ),
        _record(
          day: DateTime(2026, 2, 4),
          industry: 'B',
          z: 2.0,
          q: 1.0,
          breadth: 0.5,
        ),
        _record(
          day: DateTime(2026, 2, 4),
          industry: 'C',
          z: 1.0,
          q: 1.0,
          breadth: 0.5,
        ),
      ];

      final scored = IndustryScoreEngine.enrichAndRank(records);

      final day1 =
          scored.where((r) => r.dateOnly == DateTime(2026, 2, 3)).toList()
            ..sort((a, b) => a.rank.compareTo(b.rank));
      expect(day1.map((r) => r.industry).toList(), ['A', 'B']);
      expect(day1.map((r) => r.rankChange).toList(), [0, 0]);
      expect(day1.map((r) => r.rankArrow).toList(), ['→', '→']);

      final day2 =
          scored.where((r) => r.dateOnly == DateTime(2026, 2, 4)).toList()
            ..sort((a, b) => a.rank.compareTo(b.rank));
      expect(day2.map((r) => r.industry).toList(), ['B', 'C', 'A']);

      final byIndustry = {for (final r in day2) r.industry: r};
      expect(byIndustry['B']!.rankChange, 1);
      expect(byIndustry['B']!.rankArrow, '↑');
      expect(byIndustry['A']!.rankChange, -2);
      expect(byIndustry['A']!.rankArrow, '↓');
      expect(byIndustry['C']!.rankChange, 0);
      expect(byIndustry['C']!.rankArrow, '→');
    });

    test(
      'mock data demo: 3 industries x 5 days produce sortable latest scores',
      () {
        final records = <IndustryBuildupDailyRecord>[];
        final days = [
          DateTime(2026, 2, 2),
          DateTime(2026, 2, 3),
          DateTime(2026, 2, 4),
          DateTime(2026, 2, 5),
          DateTime(2026, 2, 6),
        ];

        void addSeries(String industry, List<double> z) {
          for (var i = 0; i < days.length; i++) {
            records.add(
              _record(
                day: days[i],
                industry: industry,
                z: z[i],
                q: 0.8,
                breadth: 0.45,
              ),
            );
          }
        }

        addSeries('半导体', [0.8, 1.0, 1.2, 1.5, 1.7]);
        addSeries('军工', [0.6, 0.5, 0.7, 1.0, 0.9]);
        addSeries('医药', [1.4, 1.1, 0.8, 0.7, 0.6]);

        final scored = IndustryScoreEngine.enrichAndRank(records);
        final latest =
            scored.where((r) => r.dateOnly == DateTime(2026, 2, 6)).toList()
              ..sort((a, b) => a.rank.compareTo(b.rank));

        expect(latest.length, 3);
        expect(latest.first.industry, '半导体');
        expect(latest.first.scoreEma, greaterThan(latest[1].scoreEma));
        expect(latest[1].scoreEma, greaterThan(latest[2].scoreEma));
      },
    );
  });
}
