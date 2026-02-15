import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/kline_viewport.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  testWidgets('emits initial viewport and updates after horizontal scroll', (
    tester,
  ) async {
    final events = <KLineViewport>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChart(
              key: const ValueKey('chart_viewport'),
              bars: buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1)),
              onViewportChanged: events.add,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(events, isNotEmpty);
    final initial = events.last;

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();

    expect(events.length, greaterThan(1));
    final updated = events.last;
    expect(updated.startIndex, lessThan(initial.startIndex));
    expect(updated.visibleCount, equals(initial.visibleCount));
  });
}
