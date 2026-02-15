import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/linked_dual_kline_view.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  testWidgets('renders weekly and daily charts in linked mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkedDualKlineView(
            weeklyBars: buildWeeklyBars(),
            dailyBars: buildDailyBarsForTwoWeeks(),
            ratios: const [],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('linked_weekly_chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('linked_daily_chart')), findsOneWidget);

    final weeklyChart = tester.widget<KLineChart>(
      find.byKey(const ValueKey('linked_weekly_chart')),
    );
    final dailyChart = tester.widget<KLineChart>(
      find.byKey(const ValueKey('linked_daily_chart')),
    );
    expect(weeklyChart.showWeeklySeparators, isFalse);
    expect(dailyChart.showWeeklySeparators, isTrue);
  });
}
