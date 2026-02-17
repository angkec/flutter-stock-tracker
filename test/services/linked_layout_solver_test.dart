import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/linked_layout_config.dart';
import 'package:stock_rtwatcher/services/linked_layout_solver.dart';

void main() {
  test('keeps both pane main charts above minimum in balanced defaults', () {
    const config = LinkedLayoutConfig.balanced();
    final result = LinkedLayoutSolver.resolve(
      availableHeight: 560,
      topSubchartCount: 2,
      bottomSubchartCount: 2,
      config: config,
    );

    expect(
      result.top.mainChartHeight,
      greaterThanOrEqualTo(config.mainMinHeight),
    );
    expect(
      result.bottom.mainChartHeight,
      greaterThanOrEqualTo(config.mainMinHeight),
    );
  });

  test(
    'scales to 5 fixed subcharts and preserves minimum readable heights',
    () {
      const config = LinkedLayoutConfig.balanced();
      final result = LinkedLayoutSolver.resolve(
        availableHeight: 720,
        topSubchartCount: 5,
        bottomSubchartCount: 5,
        config: config,
      );

      expect(result.top.subchartHeights.length, 5);
      expect(result.bottom.subchartHeights.length, 5);
      expect(
        result.top.subchartHeights.every((h) => h >= config.subMinHeight),
        isTrue,
      );
      expect(
        result.bottom.subchartHeights.every((h) => h >= config.subMinHeight),
        isTrue,
      );
    },
  );

  test(
    'clamps container height to configured bounds under normal pressure',
    () {
      const config = LinkedLayoutConfig.balanced(
        containerMinHeight: 640,
        containerMaxHeight: 840,
      );

      final tiny = LinkedLayoutSolver.resolve(
        availableHeight: 300,
        topSubchartCount: 2,
        bottomSubchartCount: 2,
        config: config,
      );
      final huge = LinkedLayoutSolver.resolve(
        availableHeight: 2000,
        topSubchartCount: 2,
        bottomSubchartCount: 2,
        config: config,
      );

      expect(tiny.containerHeight, greaterThanOrEqualTo(640));
      expect(huge.containerHeight, lessThanOrEqualTo(840));
    },
  );

  test(
    'preserves readable minimums for 5 subcharts per pane under extreme pressure',
    () {
      const config = LinkedLayoutConfig.balanced(
        containerMinHeight: 640,
        containerMaxHeight: 840,
      );

      final result = LinkedLayoutSolver.resolve(
        availableHeight: 560,
        topSubchartCount: 5,
        bottomSubchartCount: 5,
        config: config,
      );

      expect(result.containerHeight, greaterThan(config.containerMaxHeight));
      expect(
        result.top.mainChartHeight,
        greaterThanOrEqualTo(config.mainMinHeight),
      );
      expect(
        result.bottom.mainChartHeight,
        greaterThanOrEqualTo(config.mainMinHeight),
      );
      expect(
        result.top.subchartHeights.every((height) => height >= config.subMinHeight),
        isTrue,
      );
      expect(
        result.bottom.subchartHeights.every((height) => height >= config.subMinHeight),
        isTrue,
      );
    },
  );
}
