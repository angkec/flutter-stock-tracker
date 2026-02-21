import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/services/china_trading_calendar_service.dart';

void main() {
  group('ChinaTradingCalendarService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    const service = ChinaTradingCalendarService();

    test('treats configured holiday weekday as non-trading day', () {
      final holiday = DateTime(2026, 10, 6); // National Day break
      expect(service.isTradingDay(holiday), isFalse);
    });

    test('resolves latest trading day before holiday weekday', () {
      final day = DateTime(2026, 10, 6);
      final latest = service.latestTradingDayOnOrBefore(day);

      expect(latest, isNotNull);
      expect(latest!.year, 2026);
      expect(latest.month, 9);
      expect(latest.day, 30);
    });

    test('prefers inferred trading dates when provided', () {
      final sunday = DateTime(2026, 10, 11);
      final inferred = [DateTime(2026, 10, 11)];

      expect(
        service.isTradingDay(sunday, inferredTradingDates: inferred),
        isTrue,
      );
    });

    test(
      'refreshRemoteCalendar applies remote holidays to trading checks',
      () async {
        final service = ChinaTradingCalendarService(
          remoteFetcher: () async {
            return {
              'closedDates': <String>['2026-09-29'],
            };
          },
          nowProvider: () => DateTime(2026, 9, 30, 12),
        );

        final refreshed = await service.refreshRemoteCalendar();

        expect(refreshed, isTrue);
        expect(service.isTradingDay(DateTime(2026, 9, 29)), isFalse);
      },
    );

    test(
      'loadCachedCalendar keeps cached dates when remote refresh fails',
      () async {
        final seedService = ChinaTradingCalendarService(
          remoteFetcher: () async {
            return {
              'closedDates': <String>['2026-09-28'],
            };
          },
          nowProvider: () => DateTime(2026, 9, 30, 12),
        );
        await seedService.refreshRemoteCalendar();

        final fallbackService = ChinaTradingCalendarService(
          remoteFetcher: () async {
            throw Exception('remote unavailable');
          },
        );

        final loaded = await fallbackService.loadCachedCalendar();
        final refreshed = await fallbackService.refreshRemoteCalendar();

        expect(loaded, isTrue);
        expect(refreshed, isFalse);
        expect(fallbackService.isTradingDay(DateTime(2026, 9, 28)), isFalse);
      },
    );
  });
}
