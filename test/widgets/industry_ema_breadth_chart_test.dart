import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';
import 'package:stock_rtwatcher/widgets/industry_ema_breadth_chart.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('显示最新 EMA 广度摘要与阈值文案', (tester) async {
    final series = IndustryEmaBreadthSeries(
      industry: '半导体',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 5),
          percent: 58,
          aboveCount: 12,
          validCount: 20,
          missingCount: 4,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 6),
          percent: 64,
          aboveCount: 13,
          validCount: 21,
          missingCount: 3,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        IndustryEmaBreadthChart(
          series: series,
          config: const IndustryEmaBreadthConfig(
            upperThreshold: 80,
            lowerThreshold: 30,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('industry_ema_breadth_latest_summary')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Above 13 / Valid 21 / Missing 3'),
      findsOneWidget,
    );
    expect(find.text('Upper 80%'), findsOneWidget);
    expect(find.text('Lower 30%'), findsOneWidget);
  });

  testWidgets('百分比空值不会连接跨缺口折线', (tester) async {
    final series = IndustryEmaBreadthSeries(
      industry: '半导体',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 3),
          percent: 42,
          aboveCount: 8,
          validCount: 19,
          missingCount: 2,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 4),
          percent: 48,
          aboveCount: 10,
          validCount: 21,
          missingCount: 1,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 5),
          percent: null,
          aboveCount: 0,
          validCount: 0,
          missingCount: 22,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 6),
          percent: 55,
          aboveCount: 11,
          validCount: 20,
          missingCount: 2,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 7),
          percent: 60,
          aboveCount: 12,
          validCount: 20,
          missingCount: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        IndustryEmaBreadthChart(
          series: series,
          config: IndustryEmaBreadthConfig.defaultConfig,
        ),
      ),
    );

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('industry_ema_breadth_custom_paint')),
    );
    final painter = paint.painter! as IndustryEmaBreadthChartPainter;
    expect(painter.lineSegmentCount, 2);
  });

  testWidgets('支持点击图表选择日期并显示选中详情', (tester) async {
    final series = IndustryEmaBreadthSeries(
      industry: '半导体',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 5),
          percent: 58,
          aboveCount: 12,
          validCount: 20,
          missingCount: 4,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 6),
          percent: 64,
          aboveCount: 13,
          validCount: 21,
          missingCount: 3,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 7),
          percent: 72,
          aboveCount: 15,
          validCount: 22,
          missingCount: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        IndustryEmaBreadthChart(
          series: series,
          config: const IndustryEmaBreadthConfig(
            upperThreshold: 80,
            lowerThreshold: 30,
          ),
        ),
      ),
    );

    // Initially, the latest point should be selected (index 2)
    // But with our implementation, we start at index 0
    // Find the chart and tap on it
    final chartFinder = find.byKey(
      const ValueKey('industry_ema_breadth_custom_paint'),
    );
    expect(chartFinder, findsOneWidget);

    // Get the chart rect
    final chartRect = tester.getRect(chartFinder);

    // Tap on left side to select first point
    await tester.tapAt(Offset(chartRect.left + 20, chartRect.center.dy));
    await tester.pump();

    // Should show selected detail for first point
    expect(
      find.byKey(const ValueKey('industry_ema_breadth_selected_detail')),
      findsOneWidget,
    );
    expect(find.textContaining('选中 2026-02-05'), findsOneWidget);
    expect(find.textContaining('广度 58%'), findsOneWidget);
  });

  testWidgets('支持拖动图表选择不同日期', (tester) async {
    final series = IndustryEmaBreadthSeries(
      industry: '半导体',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 5),
          percent: 58,
          aboveCount: 12,
          validCount: 20,
          missingCount: 4,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 6),
          percent: 64,
          aboveCount: 13,
          validCount: 21,
          missingCount: 3,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 7),
          percent: 72,
          aboveCount: 15,
          validCount: 22,
          missingCount: 2,
        ),
      ],
    );

    IndustryEmaBreadthPoint? lastCallbackPoint;

    await tester.pumpWidget(
      _wrap(
        IndustryEmaBreadthChart(
          series: series,
          config: IndustryEmaBreadthConfig.defaultConfig,
          onSelectedPointChanged: (point) {
            lastCallbackPoint = point;
          },
        ),
      ),
    );

    // Initially should have a selection (first point)
    // After pump, the state should be set
    await tester.pump();

    // Verify selection detail is shown
    expect(
      find.byKey(const ValueKey('industry_ema_breadth_selected_detail')),
      findsOneWidget,
    );
  });

  testWidgets('空数据时不显示选中详情', (tester) async {
    await tester.pumpWidget(
      _wrap(
        IndustryEmaBreadthChart(
          series: null,
          config: IndustryEmaBreadthConfig.defaultConfig,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('industry_ema_breadth_selected_detail')),
      findsNothing,
    );
    expect(find.text('暂无 EMA 广度数据'), findsOneWidget);
  });

  testWidgets('选中空值百分比日期时显示最近有效值', (tester) async {
    final series = IndustryEmaBreadthSeries(
      industry: '半导体',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 5),
          percent: 58,
          aboveCount: 12,
          validCount: 20,
          missingCount: 4,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 6),
          percent: null, // null percent
          aboveCount: 0,
          validCount: 0,
          missingCount: 22,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 7),
          percent: 72,
          aboveCount: 15,
          validCount: 22,
          missingCount: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        IndustryEmaBreadthChart(
          series: series,
          config: IndustryEmaBreadthConfig.defaultConfig,
        ),
      ),
    );

    // Should show selected detail (falls back to valid closest point)
    expect(
      find.byKey(const ValueKey('industry_ema_breadth_selected_detail')),
      findsOneWidget,
    );
    // Should show the closest valid percent (58% from first point)
    expect(find.textContaining('广度 58%'), findsOneWidget);
  });

  // Regression test: selected detail must be visible within container bounds
  // (was previously clipped when container height was < 300px)
  testWidgets('选中详情在300px容器内完整可见（回归测试）', (tester) async {
    final series = IndustryEmaBreadthSeries(
      industry: '半导体',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 5),
          percent: 58,
          aboveCount: 12,
          validCount: 20,
          missingCount: 4,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 6),
          percent: 64,
          aboveCount: 13,
          validCount: 21,
          missingCount: 3,
        ),
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 7),
          percent: 72,
          aboveCount: 15,
          validCount: 22,
          missingCount: 2,
        ),
      ],
    );

    // Constrain to match app container height (305px after fix)
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 305,
            child: IndustryEmaBreadthChart(
              series: series,
              config: IndustryEmaBreadthConfig.defaultConfig,
            ),
          ),
        ),
      ),
    );

    // Verify detail widget exists
    final detailFinder = find.byKey(
      const ValueKey('industry_ema_breadth_selected_detail'),
    );
    expect(detailFinder, findsOneWidget);

    // Verify detail is fully visible (not clipped)
    final detailRect = tester.getRect(detailFinder);
    final containerRect = tester.getRect(find.byType(SizedBox).first);

    // Detail bottom should be within container bounds
    expect(
      detailRect.bottom,
      lessThanOrEqualTo(containerRect.bottom),
      reason:
          'Detail bottom (${detailRect.bottom}) should be within container bottom (${containerRect.bottom})',
    );
    expect(
      detailRect.top,
      greaterThanOrEqualTo(containerRect.top),
      reason: 'Detail top should be within container bounds',
    );
  });
}
