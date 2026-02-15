import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';
import 'package:stock_rtwatcher/widgets/linked_kline_mapper.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  test('maps daily bar date to weekly bar index', () {
    final weeklyBars = buildWeeklyBars();
    final dailyBars = buildDailyBarsForTwoWeeks();

    final idx = LinkedKlineMapper.findWeeklyIndexForDailyDate(
      weeklyBars: weeklyBars,
      dailyDate: dailyBars.last.datetime,
    );

    expect(idx, 1);
  });

  test('maps weekly bar to last trading day index', () {
    final weeklyBars = buildWeeklyBars();
    final dailyBars = buildDailyBarsForTwoWeeks();

    final idx = LinkedKlineMapper.findDailyIndexForWeeklyDate(
      dailyBars: dailyBars,
      weeklyDate: weeklyBars.first.datetime,
    );

    expect(dailyBars[idx!].datetime.weekday, DateTime.friday);
    expect(dailyBars[idx].datetime, DateTime(2026, 2, 6));
  });

  test('linked state copyWith preserves untouched fields', () {
    final state = LinkedCrosshairState(
      sourcePane: LinkedPane.daily,
      anchorDate: DateTime(2026, 2, 13),
      anchorPrice: 12.34,
      isLinking: true,
    );

    final next = state.copyWith(anchorPrice: 12.88);
    expect(next.sourcePane, LinkedPane.daily);
    expect(next.anchorDate, DateTime(2026, 2, 13));
    expect(next.anchorPrice, 12.88);
    expect(next.isLinking, true);
  });

  test('ensureIndexVisible scrolls window when target is out of range', () {
    final nextStart = LinkedKlineMapper.ensureIndexVisible(
      startIndex: 20,
      visibleCount: 30,
      targetIndex: 5,
      totalCount: 50,
    );
    expect(nextStart, 5);

    final nextStartRight = LinkedKlineMapper.ensureIndexVisible(
      startIndex: 0,
      visibleCount: 30,
      targetIndex: 45,
      totalCount: 50,
    );
    expect(nextStartRight, 16);
  });

  test(
    'findWeeklyBoundaryIndices marks weekly transitions in visible window',
    () {
      final dailyBars = buildDailyBarsForTwoWeeks();
      final boundaries = LinkedKlineMapper.findWeeklyBoundaryIndices(
        bars: dailyBars,
        startIndex: 0,
        endIndex: dailyBars.length,
      );

      expect(boundaries.contains(0), isTrue);
      expect(boundaries.contains(5), isTrue);

      final subBoundaries = LinkedKlineMapper.findWeeklyBoundaryIndices(
        bars: dailyBars,
        startIndex: 2,
        endIndex: 9,
      );
      expect(subBoundaries.contains(3), isTrue);
    },
  );
}
