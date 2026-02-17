import 'dart:math' as math;

import 'package:stock_rtwatcher/models/linked_layout_config.dart';
import 'package:stock_rtwatcher/models/linked_layout_result.dart';

class LinkedLayoutSolver {
  static LinkedLayoutResult resolve({
    required double availableHeight,
    required int topSubchartCount,
    required int bottomSubchartCount,
    required LinkedLayoutConfig config,
  }) {
    final normalized = config.normalize();
    final totalWeight = normalized.topPaneWeight + normalized.bottomPaneWeight;

    double requiredPaneMinHeight(int subchartCount) {
      final safeCount = math.max(0, subchartCount);
      return normalized.mainMinHeight +
          safeCount * normalized.subMinHeight +
          safeCount * normalized.subchartSpacing;
    }

    final topBaseline = requiredPaneMinHeight(topSubchartCount);
    final bottomBaseline = requiredPaneMinHeight(bottomSubchartCount);

    final requiredPaneBudget = math.max(
      topBaseline * totalWeight / normalized.topPaneWeight,
      bottomBaseline * totalWeight / normalized.bottomPaneWeight,
    );

    final requiredContainer =
        normalized.infoBarHeight + normalized.paneGap + requiredPaneBudget;

    final clampedByConfig = availableHeight.clamp(
      normalized.containerMinHeight,
      normalized.containerMaxHeight,
    );
    final container = math.max(clampedByConfig, requiredContainer).toDouble();

    final panesAvailable = math.max(
      0.0,
      container - normalized.infoBarHeight - normalized.paneGap,
    );

    final topPaneHeight =
        panesAvailable * normalized.topPaneWeight / totalWeight;
    final bottomPaneHeight =
        panesAvailable * normalized.bottomPaneWeight / totalWeight;

    LinkedPaneLayoutResult buildPane({
      required double paneHeight,
      required int subchartCount,
    }) {
      final safeCount = math.max(0, subchartCount);
      final spacingTotal = safeCount * normalized.subchartSpacing;
      final minimumRequired =
          normalized.mainMinHeight +
          safeCount * normalized.subMinHeight +
          spacingTotal;

      final availableExtra = math.max(0.0, paneHeight - minimumRequired);
      final mainGrowTarget = math.max(
        0.0,
        normalized.mainIdealHeight - normalized.mainMinHeight,
      );
      final mainExtra = math.min(availableExtra, mainGrowTarget);
      final mainHeight = normalized.mainMinHeight + mainExtra;

      final subExtraTotal = math.max(0.0, availableExtra - mainExtra);
      final perSubExtra = safeCount == 0 ? 0.0 : subExtraTotal / safeCount;

      final subHeights = List<double>.generate(
        safeCount,
        (_) => math.min(
          normalized.subIdealHeight,
          normalized.subMinHeight + perSubExtra,
        ),
        growable: false,
      );

      return LinkedPaneLayoutResult(
        mainChartHeight: mainHeight,
        subchartHeights: subHeights,
      );
    }

    return LinkedLayoutResult(
      containerHeight: container,
      top: buildPane(
        paneHeight: topPaneHeight,
        subchartCount: topSubchartCount,
      ),
      bottom: buildPane(
        paneHeight: bottomPaneHeight,
        subchartCount: bottomSubchartCount,
      ),
    );
  }
}
