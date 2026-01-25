import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';

void main() {
  group('HistoricalKlineService', () {
    group('date utilities', () {
      test('formatDate returns YYYY-MM-DD format', () {
        final date = DateTime(2025, 1, 25);
        expect(HistoricalKlineService.formatDate(date), '2025-01-25');
      });

      test('formatDate pads single digit month and day', () {
        final date = DateTime(2025, 3, 5);
        expect(HistoricalKlineService.formatDate(date), '2025-03-05');
      });

      test('parseDate parses YYYY-MM-DD format', () {
        final date = HistoricalKlineService.parseDate('2025-01-25');
        expect(date.year, 2025);
        expect(date.month, 1);
        expect(date.day, 25);
      });
    });
  });
}
