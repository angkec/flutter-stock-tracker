import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_coordinator.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  test('coordinator maps weekly touch to daily last-trading-day index', () {
    final coordinator = LinkedCrosshairCoordinator(
      weeklyBars: buildWeeklyBars(),
      dailyBars: buildDailyBarsForTwoWeeks(),
    );

    coordinator.handleTouch(
      LinkedTouchEvent(
        pane: LinkedPane.weekly,
        phase: LinkedTouchPhase.update,
        date: DateTime(2026, 2, 6),
        price: 12.5,
        barIndex: 0,
      ),
    );

    expect(coordinator.value?.sourcePane, LinkedPane.weekly);
    expect(coordinator.mappedDailyIndex, 4);
    expect(coordinator.mappedWeeklyIndex, 0);
  });
}
