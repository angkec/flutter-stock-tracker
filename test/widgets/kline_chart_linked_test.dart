import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  testWidgets('emits linked touch events during long press move', (
    tester,
  ) async {
    final events = <LinkedTouchEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChart(
              key: const ValueKey('chart'),
              bars: buildDailyBarsForTwoWeeks(),
              linkedPane: LinkedPane.daily,
              onLinkedTouchEvent: events.add,
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const ValueKey('chart')));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(30, -20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      events.where((event) => event.phase == LinkedTouchPhase.update),
      isNotEmpty,
    );
    expect(events.last.phase, LinkedTouchPhase.end);
  });

  testWidgets(
    'auto-scrolls to reveal external mapped day when selection comes from weekly',
    (tester) async {
      final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: KLineChart(
                key: const ValueKey('chart_auto_scroll'),
                bars: bars,
                linkedPane: LinkedPane.daily,
                externalLinkedState: LinkedCrosshairState(
                  sourcePane: LinkedPane.weekly,
                  anchorDate: DateTime(2026, 1, 1),
                  anchorPrice: 10.5,
                  isLinking: true,
                ),
                externalLinkedBarIndex: 0,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    },
  );
}
