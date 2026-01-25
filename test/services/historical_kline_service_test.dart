import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';

// Helper function to generate test KLine bars
List<KLine> _generateBars(DateTime date, int upCount, int downCount, {double upVol = 100, double downVol = 100}) {
  final bars = <KLine>[];
  for (var i = 0; i < upCount; i++) {
    bars.add(KLine(
      datetime: date.add(Duration(minutes: i)),
      open: 10, close: 11, high: 11, low: 10,
      volume: upVol, amount: 0,
    ));
  }
  for (var i = 0; i < downCount; i++) {
    bars.add(KLine(
      datetime: date.add(Duration(minutes: upCount + i)),
      open: 11, close: 10, high: 11, low: 10,
      volume: downVol, amount: 0,
    ));
  }
  return bars;
}

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

    group('getDailyVolumes', () {
      late HistoricalKlineService service;

      setUp(() {
        service = HistoricalKlineService();
      });

      test('returns empty map for unknown stock', () {
        final volumes = service.getDailyVolumes('999999');
        expect(volumes, isEmpty);
      });

      test('calculates daily up/down volumes correctly', () {
        final date1 = DateTime(2025, 1, 24, 9, 30);
        final date2 = DateTime(2025, 1, 25, 9, 30);

        final bars = [
          ..._generateBars(date1, 5, 3, upVol: 100, downVol: 50),
          ..._generateBars(date2, 4, 6, upVol: 200, downVol: 100),
        ];

        service.setStockBars('000001', bars);

        final volumes = service.getDailyVolumes('000001');

        expect(volumes.length, 2);
        expect(volumes['2025-01-24']?.up, 500); // 5 * 100
        expect(volumes['2025-01-24']?.down, 150); // 3 * 50
        expect(volumes['2025-01-25']?.up, 800); // 4 * 200
        expect(volumes['2025-01-25']?.down, 600); // 6 * 100
      });
    });

    group('getMissingDays', () {
      late HistoricalKlineService service;

      setUp(() {
        service = HistoricalKlineService();
      });

      test('returns expected trading days when no data', () {
        // With no complete dates, all estimated trading days are missing
        final missing = service.getMissingDays();
        expect(missing, greaterThan(0));
      });

      test('returns 0 when all recent dates are complete', () {
        // Simulate having all recent trading days
        // Need to go back ~45 calendar days to cover 30 trading days (weekends excluded)
        final today = DateTime.now();
        for (var i = 1; i <= 45; i++) {
          final date = today.subtract(Duration(days: i));
          if (date.weekday != DateTime.saturday && date.weekday != DateTime.sunday) {
            service.addCompleteDate(HistoricalKlineService.formatDate(date));
          }
        }
        final missing = service.getMissingDays();
        expect(missing, 0);
      });
    });

    group('persistence', () {
      test('serializes and deserializes correctly', () {
        final service = HistoricalKlineService();
        // Use a recent date to avoid cleanup removing it
        final now = DateTime.now();
        final recentDate = DateTime(now.year, now.month, now.day, 9, 30).subtract(const Duration(days: 1));
        final dateKey = HistoricalKlineService.formatDate(recentDate);
        final bars = _generateBars(recentDate, 5, 3);

        service.setStockBars('000001', bars);
        service.addCompleteDate(dateKey);

        final json = service.serializeCache();

        expect(json['version'], 1);
        expect(json['completeDates'], contains(dateKey));
        expect(json['stocks']['000001'], isNotEmpty);

        // Create new service and deserialize
        final service2 = HistoricalKlineService();
        service2.deserializeCache(json);

        expect(service2.completeDates, contains(dateKey));
        expect(service2.getDailyVolumes('000001'), isNotEmpty);
      });
    });
  });
}
