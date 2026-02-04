import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';

void main() {
  group('DayDataStatus', () {
    test('should have all expected values', () {
      expect(DayDataStatus.values, contains(DayDataStatus.complete));
      expect(DayDataStatus.values, contains(DayDataStatus.incomplete));
      expect(DayDataStatus.values, contains(DayDataStatus.missing));
      expect(DayDataStatus.values, contains(DayDataStatus.inProgress));
    });
  });

  group('MissingDatesResult', () {
    test('isComplete returns true when no missing or incomplete dates', () {
      final result = MissingDatesResult(
        missingDates: [],
        incompleteDates: [],
        completeDates: [DateTime(2026, 1, 15)],
      );

      expect(result.isComplete, isTrue);
    });

    test('isComplete returns false when has missing dates', () {
      final result = MissingDatesResult(
        missingDates: [DateTime(2026, 1, 16)],
        incompleteDates: [],
        completeDates: [DateTime(2026, 1, 15)],
      );

      expect(result.isComplete, isFalse);
    });

    test('isComplete returns false when has incomplete dates', () {
      final result = MissingDatesResult(
        missingDates: [],
        incompleteDates: [DateTime(2026, 1, 16)],
        completeDates: [DateTime(2026, 1, 15)],
      );

      expect(result.isComplete, isFalse);
    });

    test('datesToFetch combines missing and incomplete dates sorted', () {
      final jan15 = DateTime(2026, 1, 15);
      final jan16 = DateTime(2026, 1, 16);
      final jan17 = DateTime(2026, 1, 17);

      final result = MissingDatesResult(
        missingDates: [jan17],
        incompleteDates: [jan15],
        completeDates: [jan16],
      );

      expect(result.datesToFetch, equals([jan15, jan17]));
    });

    test('fetchCount returns sum of missing and incomplete', () {
      final result = MissingDatesResult(
        missingDates: [DateTime(2026, 1, 15), DateTime(2026, 1, 16)],
        incompleteDates: [DateTime(2026, 1, 17)],
        completeDates: [],
      );

      expect(result.fetchCount, equals(3));
    });
  });
}
