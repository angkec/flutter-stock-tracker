import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/linked_layout_result.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/linked_dual_kline_view.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  testWidgets('renders weekly and daily charts in linked mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkedDualKlineView(
            stockCode: '600000',
            weeklyBars: buildWeeklyBars(),
            dailyBars: buildDailyBarsForTwoWeeks(),
            ratios: const [],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('linked_weekly_chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('linked_daily_chart')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('linked_weekly_macd_subchart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_daily_macd_subchart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_weekly_adx_subchart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_daily_adx_subchart')),
      findsOneWidget,
    );

    final weeklyChart = tester.widget<KLineChartWithSubCharts>(
      find.byKey(const ValueKey('linked_weekly_chart')),
    );
    final dailyChart = tester.widget<KLineChartWithSubCharts>(
      find.byKey(const ValueKey('linked_daily_chart')),
    );
    expect(weeklyChart.showWeeklySeparators, isFalse);
    expect(dailyChart.showWeeklySeparators, isTrue);
  });

  testWidgets(
    'uses injected resolved heights for weekly and daily main charts',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const layout = LinkedLayoutResult(
        containerHeight: 700,
        top: LinkedPaneLayoutResult(
          mainChartHeight: 96,
          subchartHeights: [60, 60],
        ),
        bottom: LinkedPaneLayoutResult(
          mainChartHeight: 130,
          subchartHeights: [62, 62],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: layout.containerHeight,
              child: LinkedDualKlineView(
                stockCode: '600000',
                weeklyBars: buildWeeklyBars(),
                dailyBars: buildDailyBarsForTwoWeeks(),
                ratios: const [],
                layout: layout,
              ),
            ),
          ),
        ),
      );

      final weeklyChart = tester.widget<KLineChartWithSubCharts>(
        find.byKey(const ValueKey('linked_weekly_chart')),
      );
      final dailyChart = tester.widget<KLineChartWithSubCharts>(
        find.byKey(const ValueKey('linked_daily_chart')),
      );

      expect(weeklyChart.chartHeight, 96);
      expect(dailyChart.chartHeight, 130);
    },
  );
}
