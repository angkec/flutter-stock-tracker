import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_coordinator.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';

class LinkedDualKlineView extends StatefulWidget {
  const LinkedDualKlineView({
    super.key,
    required this.weeklyBars,
    required this.dailyBars,
    required this.ratios,
  });

  final List<KLine> weeklyBars;
  final List<KLine> dailyBars;
  final List<DailyRatio> ratios;

  @override
  State<LinkedDualKlineView> createState() => _LinkedDualKlineViewState();
}

class _LinkedDualKlineViewState extends State<LinkedDualKlineView> {
  static const double _chartInfoHeight = 24;

  late LinkedCrosshairCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    _coordinator = LinkedCrosshairCoordinator(
      weeklyBars: widget.weeklyBars,
      dailyBars: widget.dailyBars,
    );
  }

  @override
  void didUpdateWidget(covariant LinkedDualKlineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weeklyBars != widget.weeklyBars ||
        oldWidget.dailyBars != widget.dailyBars) {
      _coordinator.dispose();
      _coordinator = LinkedCrosshairCoordinator(
        weeklyBars: widget.weeklyBars,
        dailyBars: widget.dailyBars,
      );
    }
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LinkedCrosshairState?>(
      valueListenable: _coordinator,
      builder: (context, state, _) {
        return Column(
          key: const ValueKey('linked_dual_kline_view'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 26,
              child: state == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '联动中',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '价格 ${state.anchorPrice.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
            ),
            Expanded(
              flex: 42,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return KLineChart(
                    key: const ValueKey('linked_weekly_chart'),
                    bars: widget.weeklyBars,
                    height: (constraints.maxHeight - _chartInfoHeight).clamp(
                      120.0,
                      double.infinity,
                    ),
                    linkedPane: LinkedPane.weekly,
                    onLinkedTouchEvent: _coordinator.handleTouch,
                    externalLinkedState: _coordinator.stateForPane(
                      LinkedPane.weekly,
                    ),
                    externalLinkedBarIndex: _coordinator.mappedWeeklyIndex,
                    showWeeklySeparators: false,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 58,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return KLineChart(
                    key: const ValueKey('linked_daily_chart'),
                    bars: widget.dailyBars,
                    ratios: widget.ratios,
                    height: (constraints.maxHeight - _chartInfoHeight).clamp(
                      120.0,
                      double.infinity,
                    ),
                    linkedPane: LinkedPane.daily,
                    onLinkedTouchEvent: _coordinator.handleTouch,
                    externalLinkedState: _coordinator.stateForPane(
                      LinkedPane.daily,
                    ),
                    externalLinkedBarIndex: _coordinator.mappedDailyIndex,
                    showWeeklySeparators: true,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
