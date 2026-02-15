import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/kline_viewport.dart';

import '../support/kline_fixture_builder.dart';

class _CaptureSubChart extends KLineSubChart {
  _CaptureSubChart(this.onViewport, this.onSelection);

  final ValueChanged<KLineViewport> onViewport;
  final void Function(int? selectedIndex, bool isSelecting) onSelection;

  @override
  Widget buildSubChart(
    BuildContext context, {
    required String stockCode,
    required List<KLine> bars,
    required KLineViewport viewport,
    required int? selectedIndex,
    required bool isSelecting,
  }) {
    onViewport(viewport);
    onSelection(selectedIndex, isSelecting);
    return const SizedBox(key: ValueKey('capture_subchart'), height: 40);
  }
}

void main() {
  testWidgets('forwards viewport updates to subchart builders', (tester) async {
    KLineViewport? captured;
    int? capturedSelectedIndex;
    bool? capturedIsSelecting;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChartWithSubCharts(
              stockCode: '600000',
              bars: buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1)),
              subCharts: [
                _CaptureSubChart(
                  (viewport) => captured = viewport,
                  (selectedIndex, isSelecting) {
                    capturedSelectedIndex = selectedIndex;
                    capturedIsSelecting = isSelecting;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.byKey(const ValueKey('capture_subchart')), findsOneWidget);
    expect(captured, isNotNull);
    expect(captured!.visibleCount, greaterThan(0));
    expect(captured!.totalCount, 50);
    expect(capturedSelectedIndex, isNull);
    expect(capturedIsSelecting, isFalse);
  });
}
