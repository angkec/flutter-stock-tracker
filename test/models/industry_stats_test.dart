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

  group('IndustryFilter', () {
    test('default filter has no constraints', () {
      const filter = IndustryFilter();
      expect(filter.consecutiveRisingDays, isNull);
      expect(filter.minRatioAbovePercent, isNull);
      expect(filter.hasActiveFilters, isFalse);
    });

    test('hasActiveFilters returns true when consecutiveRisingDays is set', () {
      const filter = IndustryFilter(consecutiveRisingDays: 3);
      expect(filter.hasActiveFilters, isTrue);
    });

    test('hasActiveFilters returns true when minRatioAbovePercent is set', () {
      const filter = IndustryFilter(minRatioAbovePercent: 50.0);
      expect(filter.hasActiveFilters, isTrue);
    });

    test('copyWith creates new filter with updated values', () {
      const filter = IndustryFilter();
      final updated = filter.copyWith(consecutiveRisingDays: 5);
      expect(updated.consecutiveRisingDays, 5);
      expect(updated.minRatioAbovePercent, isNull);
    });

    test('copyWith can clear values with explicit null', () {
      const filter = IndustryFilter(consecutiveRisingDays: 3, minRatioAbovePercent: 50.0);
      final updated = filter.copyWith(
        consecutiveRisingDays: null,
        clearConsecutiveRisingDays: true,
      );
      expect(updated.consecutiveRisingDays, isNull);
      expect(updated.minRatioAbovePercent, 50.0);
    });
  });

  group('countConsecutiveRisingDays', () {
    test('returns 0 for empty data', () {
      expect(countConsecutiveRisingDays([]), 0);
    });

    test('returns 0 for single data point', () {
      expect(countConsecutiveRisingDays([50.0]), 0);
    });

    test('returns 0 for decreasing trend at end', () {
      // Ends with a decrease: 50 -> 40
      expect(countConsecutiveRisingDays([30.0, 40.0, 50.0, 40.0]), 0);
    });

    test('returns 1 for single rise at end', () {
      // Pattern: 30 -> 40 -> 35 -> 50
      // Transitions from end: 35->50 (rise), 40->35 (drop - STOP)
      // So only 1 consecutive rise at end
      expect(countConsecutiveRisingDays([30.0, 40.0, 35.0, 50.0]), 1);
    });

    test('counts consecutive rising days correctly', () {
      // Consecutive rises: 30 -> 40 -> 50 -> 60 (3 consecutive rises)
      expect(countConsecutiveRisingDays([30.0, 40.0, 50.0, 60.0]), 3);
    });

    test('stops counting at first non-rise when going backwards', () {
      // Pattern: 10 -> 20 -> 15 -> 25 -> 35 -> 45
      // Transitions from end: 35->45 (rise), 25->35 (rise), 15->25 (rise), 20->15 (drop - STOP)
      // So consecutive rises = 3
      expect(countConsecutiveRisingDays([10.0, 20.0, 15.0, 25.0, 35.0, 45.0]), 3);
    });

    test('counts flat days as non-rising', () {
      // Pattern: 30 -> 40 -> 40 -> 50 (flat in middle breaks the streak)
      expect(countConsecutiveRisingDays([30.0, 40.0, 40.0, 50.0]), 1);
    });

    test('handles all equal values', () {
      expect(countConsecutiveRisingDays([50.0, 50.0, 50.0, 50.0]), 0);
    });
  });

  group('filterMatchesConsecutiveRising', () {
    test('returns true when no filter is set', () {
      expect(filterMatchesConsecutiveRising([30.0, 40.0, 50.0], null), isTrue);
    });

    test('returns true when consecutive days meet threshold', () {
      // 3 consecutive rises: 30->40->50->60
      expect(filterMatchesConsecutiveRising([30.0, 40.0, 50.0, 60.0], 3), isTrue);
    });

    test('returns false when consecutive days below threshold', () {
      // Pattern: 30 -> 40 -> 35 -> 50 -> 60
      // Only 2 consecutive rises at end: 35->50->60
      expect(filterMatchesConsecutiveRising([30.0, 40.0, 35.0, 50.0, 60.0], 3), isFalse);
    });

    test('returns true when consecutive days exceed threshold', () {
      // 5 consecutive rises
      expect(filterMatchesConsecutiveRising([10.0, 20.0, 30.0, 40.0, 50.0, 60.0], 3), isTrue);
    });
  });

  group('filterMatchesMinRatioPercent', () {
    test('returns true when no filter is set', () {
      expect(filterMatchesMinRatioPercent(30.0, null), isTrue);
    });

    test('returns true when ratio exceeds threshold', () {
      expect(filterMatchesMinRatioPercent(60.0, 50.0), isTrue);
    });

    test('returns true when ratio equals threshold', () {
      expect(filterMatchesMinRatioPercent(50.0, 50.0), isTrue);
    });

    test('returns false when ratio below threshold', () {
      expect(filterMatchesMinRatioPercent(40.0, 50.0), isFalse);
    });

    test('returns false when ratio is null and filter is set', () {
      expect(filterMatchesMinRatioPercent(null, 50.0), isFalse);
    });
  });
}
