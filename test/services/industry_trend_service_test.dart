import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';

List<DateTime> _weekdaysInRecentCalendarDays(int calendarDays) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dates = <DateTime>[];

  for (var i = 1; i <= calendarDays; i++) {
    final date = today.subtract(Duration(days: i));
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      continue;
    }
    dates.add(date);
  }

  return dates;
}

Map<String, dynamic> _buildTrendCache(List<DateTime> dates) {
  final points = dates
      .map(
        (date) => DailyRatioPoint(
          date: date,
          ratioAbovePercent: 50,
          totalStocks: 10,
          ratioAboveCount: 5,
        ).toJson(),
      )
      .toList();

  return {
    'version': 1,
    'calculatedFromVersion': 1,
    'data': {
      '测试行业': {'industry': '测试行业', 'points': points},
    },
    'timestamp': DateTime.now().toIso8601String(),
  };
}

void main() {
  group('IndustryTrendService.checkMissingDays', () {
    test(
      'returns 0 when cache covers recent 30 calendar days weekdays',
      () async {
        final dates = _weekdaysInRecentCalendarDays(30);
        final cache = _buildTrendCache(dates);

        SharedPreferences.setMockInitialValues({
          'industry_trend_cache': jsonEncode(cache),
        });

        final service = IndustryTrendService();
        await service.load();

        final missingDays = service.checkMissingDays();

        expect(missingDays, 0);
      },
    );
  });
}
