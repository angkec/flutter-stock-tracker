import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';

List<KLine> _makeBars(int count) {
  final base = DateTime(2024, 1, 2);
  return List.generate(count, (i) {
    final open = 10.0 + i * 0.1;
    return KLine(
      datetime: base.add(Duration(days: i)),
      open: open,
      close: open + 0.05,
      high: open + 0.2,
      low: open - 0.1,
      volume: 1000,
      amount: 10000,
    );
  });
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('KLineChart EMA overlay', () {
    testWidgets('shows EMA labels when no bar is selected (latest values)', (
      tester,
    ) async {
      final bars = _makeBars(30);
      // short series: last value = 11.5, long series: last value = 10.8
      final shortSeries = List<double?>.filled(30, null);
      final longSeries = List<double?>.filled(30, null);
      shortSeries[29] = 11.5;
      longSeries[29] = 10.8;

      await tester.pumpWidget(
        _wrap(
          KLineChart(
            bars: bars,
            emaShortSeries: shortSeries,
            emaLongSeries: longSeries,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('EMA短'), findsOneWidget);
      expect(find.textContaining('EMA长'), findsOneWidget);
    });

    testWidgets('shows EMA values for selected bar when series provided', (
      tester,
    ) async {
      final bars = _makeBars(30);
      final shortSeries = List<double?>.filled(30, null);
      final longSeries = List<double?>.filled(30, null);
      for (var i = 9; i < 30; i++) {
        shortSeries[i] = 10.0 + i * 0.05;
      }
      for (var i = 20; i < 30; i++) {
        longSeries[i] = 10.0 + i * 0.03;
      }

      await tester.pumpWidget(
        _wrap(
          KLineChart(
            bars: bars,
            emaShortSeries: shortSeries,
            emaLongSeries: longSeries,
          ),
        ),
      );
      await tester.pump();

      // Simulate long press to select a bar (bar at index 25 should have both values)
      await tester.longPressAt(tester.getCenter(find.byType(CustomPaint).first));
      await tester.pump();

      // After selection, EMA labels should still be visible
      expect(find.textContaining('EMA短'), findsOneWidget);
      expect(find.textContaining('EMA长'), findsOneWidget);
    });

    testWidgets('does not show EMA labels when no series provided', (
      tester,
    ) async {
      final bars = _makeBars(30);

      await tester.pumpWidget(_wrap(KLineChart(bars: bars)));
      await tester.pump();

      expect(find.textContaining('EMA短'), findsNothing);
      expect(find.textContaining('EMA长'), findsNothing);
    });
  });
}
