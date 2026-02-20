import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';

List<KLine> _bars() {
  final base = DateTime(2026, 1, 1);
  return List<KLine>.generate(20, (i) {
    final open = 10 + i * 0.1;
    return KLine(
      datetime: base.add(Duration(days: i)),
      open: open,
      close: open + 0.05,
      high: open + 0.2,
      low: open - 0.2,
      volume: 1000,
      amount: 10000,
    );
  });
}

void main() {
  testWidgets('uses resolver color when provided', (tester) async {
    var calledCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KLineChart(
            bars: _bars(),
            candleColorResolver: (bar, globalIndex) {
              calledCount++;
              return Colors.blue;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(calledCount, greaterThan(0));
  });

  testWidgets('keeps original up/down colors when resolver returns null', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KLineChart(
            bars: _bars(),
            candleColorResolver: (bar, globalIndex) => null,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
  });
}
