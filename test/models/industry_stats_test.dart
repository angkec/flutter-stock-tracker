// test/models/industry_stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';

void main() {
  group('IndustrySortMode', () {
    test('enum has all required values', () {
      expect(IndustrySortMode.values.length, 3);
      expect(IndustrySortMode.values, contains(IndustrySortMode.ratioPercent));
      expect(IndustrySortMode.values, contains(IndustrySortMode.trendSlope));
      expect(IndustrySortMode.values, contains(IndustrySortMode.todayChange));
    });
  });

  group('IndustryStats', () {
    test('ratioSortValue calculates correctly', () {
      final stats = IndustryStats(
        name: 'Test',
        upCount: 5,
        downCount: 3,
        flatCount: 2,
        ratioAbove: 6,
        ratioBelow: 4,
      );

      expect(stats.ratioSortValue, 1.5); // 6/4 = 1.5
    });

    test('ratioSortValue returns infinity when ratioBelow is 0', () {
      final stats = IndustryStats(
        name: 'Test',
        upCount: 5,
        downCount: 3,
        flatCount: 2,
        ratioAbove: 6,
        ratioBelow: 0,
      );

      expect(stats.ratioSortValue, double.infinity);
    });

    test('ratioAbovePercent calculates correctly', () {
      final stats = IndustryStats(
        name: 'Test',
        upCount: 5,
        downCount: 3,
        flatCount: 2,
        ratioAbove: 6,
        ratioBelow: 4,
      );

      // ratioAbove / total * 100 = 6 / 10 * 100 = 60
      expect(stats.ratioAbovePercent, 60.0);
    });

    test('ratioAbovePercent returns 0 when total is 0', () {
      final stats = IndustryStats(
        name: 'Test',
        upCount: 0,
        downCount: 0,
        flatCount: 0,
        ratioAbove: 0,
        ratioBelow: 0,
      );

      expect(stats.ratioAbovePercent, 0.0);
    });
  });

  group('calculateTrendSlope', () {
    test('returns 0 for empty trend data', () {
      expect(calculateTrendSlope([]), 0.0);
    });

    test('returns 0 for single data point', () {
      expect(calculateTrendSlope([50.0]), 0.0);
    });

    test('calculates positive slope for upward trend', () {
      // Simple upward trend: 10, 20, 30
      final slope = calculateTrendSlope([10.0, 20.0, 30.0]);
      expect(slope, greaterThan(0));
      expect(slope, closeTo(10.0, 0.01)); // Should be 10 per step
    });

    test('calculates negative slope for downward trend', () {
      // Simple downward trend: 30, 20, 10
      final slope = calculateTrendSlope([30.0, 20.0, 10.0]);
      expect(slope, lessThan(0));
      expect(slope, closeTo(-10.0, 0.01));
    });

    test('uses only last 7 data points', () {
      // 10 points, but should only use last 7: [40,50,60,70,80,90,100]
      final data = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0];
      final slope = calculateTrendSlope(data);

      // Slope should be 10 (linear increase)
      expect(slope, closeTo(10.0, 0.01));
    });

    test('handles flat trend', () {
      final slope = calculateTrendSlope([50.0, 50.0, 50.0, 50.0]);
      expect(slope, closeTo(0.0, 0.01));
    });
  });

  group('calculateTodayChange', () {
    test('returns 0 for empty today trend', () {
      expect(calculateTodayChange(null, []), 0.0);
    });

    test('returns today value when no historical data', () {
      final today = DailyRatioPoint(
        date: DateTime.now(),
        ratioAbovePercent: 60.0,
        totalStocks: 10,
        ratioAboveCount: 6,
      );
      expect(calculateTodayChange(today, []), 60.0);
    });

    test('calculates positive change', () {
      final today = DailyRatioPoint(
        date: DateTime.now(),
        ratioAbovePercent: 70.0,
        totalStocks: 10,
        ratioAboveCount: 7,
      );
      final historical = [
        DailyRatioPoint(
          date: DateTime.now().subtract(const Duration(days: 1)),
          ratioAbovePercent: 50.0,
          totalStocks: 10,
          ratioAboveCount: 5,
        ),
      ];

      expect(calculateTodayChange(today, historical), 20.0); // 70 - 50
    });

    test('calculates negative change', () {
      final today = DailyRatioPoint(
        date: DateTime.now(),
        ratioAbovePercent: 40.0,
        totalStocks: 10,
        ratioAboveCount: 4,
      );
      final historical = [
        DailyRatioPoint(
          date: DateTime.now().subtract(const Duration(days: 2)),
          ratioAbovePercent: 30.0,
          totalStocks: 10,
          ratioAboveCount: 3,
        ),
        DailyRatioPoint(
          date: DateTime.now().subtract(const Duration(days: 1)),
          ratioAbovePercent: 60.0,
          totalStocks: 10,
          ratioAboveCount: 6,
        ),
      ];

      expect(calculateTodayChange(today, historical), -20.0); // 40 - 60
    });

    test('uses most recent historical point', () {
      final today = DailyRatioPoint(
        date: DateTime.now(),
        ratioAbovePercent: 80.0,
        totalStocks: 10,
        ratioAboveCount: 8,
      );
      // Historical points in arbitrary order
      final historical = [
        DailyRatioPoint(
          date: DateTime.now().subtract(const Duration(days: 3)),
          ratioAbovePercent: 40.0,
          totalStocks: 10,
          ratioAboveCount: 4,
        ),
        DailyRatioPoint(
          date: DateTime.now().subtract(const Duration(days: 1)),
          ratioAbovePercent: 70.0,
          totalStocks: 10,
          ratioAboveCount: 7,
        ),
        DailyRatioPoint(
          date: DateTime.now().subtract(const Duration(days: 2)),
          ratioAbovePercent: 50.0,
          totalStocks: 10,
          ratioAboveCount: 5,
        ),
      ];

      // Should use 70 (most recent) as yesterday's value
      expect(calculateTodayChange(today, historical), 10.0); // 80 - 70
    });
  });
}
