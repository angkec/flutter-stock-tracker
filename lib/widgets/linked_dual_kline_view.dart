import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_coordinator.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/adx_subchart.dart';
import 'package:stock_rtwatcher/widgets/macd_subchart.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';

class LinkedDualKlineView extends StatefulWidget {
  const LinkedDualKlineView({
    super.key,
    required this.stockCode,
    required this.weeklyBars,
    required this.dailyBars,
    required this.ratios,
    this.macdCacheStoreForTest,
    this.adxCacheStoreForTest,
  });

  final String stockCode;
  final List<KLine> weeklyBars;
  final List<KLine> dailyBars;
  final List<DailyRatio> ratios;
  final MacdCacheStore? macdCacheStoreForTest;
  final AdxCacheStore? adxCacheStoreForTest;

  @override
  State<LinkedDualKlineView> createState() => _LinkedDualKlineViewState();
}

class _LinkedDualKlineViewState extends State<LinkedDualKlineView> {
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
                  const infoHeight = 24.0;
                  const subChartSpacing = 10.0;
                  const macdSubChartHeight = 78.0;
                  const adxSubChartHeight = 78.0;
                  final chartHeight =
                      constraints.maxHeight -
                      infoHeight -
                      subChartSpacing -
                      subChartSpacing -
                      macdSubChartHeight -
                      adxSubChartHeight;

                  return KLineChartWithSubCharts(
                    key: const ValueKey('linked_weekly_chart'),
                    stockCode: widget.stockCode,
                    bars: widget.weeklyBars,
                    chartHeight: chartHeight.clamp(10.0, double.infinity),
                    linkedPane: LinkedPane.weekly,
                    onLinkedTouchEvent: _coordinator.handleTouch,
                    externalLinkedState: _coordinator.stateForPane(
                      LinkedPane.weekly,
                    ),
                    externalLinkedBarIndex: _coordinator.mappedWeeklyIndex,
                    showWeeklySeparators: false,
                    subChartSpacing: subChartSpacing,
                    subCharts: [
                      MacdSubChart(
                        key: const ValueKey('linked_weekly_macd_subchart'),
                        dataType: KLineDataType.weekly,
                        cacheStore: widget.macdCacheStoreForTest,
                        height: macdSubChartHeight,
                        chartKey: const ValueKey('linked_weekly_macd_paint'),
                      ),
                      AdxSubChart(
                        key: const ValueKey('linked_weekly_adx_subchart'),
                        dataType: KLineDataType.weekly,
                        cacheStore: widget.adxCacheStoreForTest,
                        height: adxSubChartHeight,
                        chartKey: const ValueKey('linked_weekly_adx_paint'),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 58,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const infoHeight = 24.0;
                  const subChartSpacing = 10.0;
                  const macdSubChartHeight = 84.0;
                  const adxSubChartHeight = 84.0;
                  final chartHeight =
                      constraints.maxHeight -
                      infoHeight -
                      subChartSpacing -
                      subChartSpacing -
                      macdSubChartHeight -
                      adxSubChartHeight;

                  return KLineChartWithSubCharts(
                    key: const ValueKey('linked_daily_chart'),
                    stockCode: widget.stockCode,
                    bars: widget.dailyBars,
                    ratios: widget.ratios,
                    chartHeight: chartHeight.clamp(50.0, double.infinity),
                    linkedPane: LinkedPane.daily,
                    onLinkedTouchEvent: _coordinator.handleTouch,
                    externalLinkedState: _coordinator.stateForPane(
                      LinkedPane.daily,
                    ),
                    externalLinkedBarIndex: _coordinator.mappedDailyIndex,
                    showWeeklySeparators: true,
                    subChartSpacing: subChartSpacing,
                    subCharts: [
                      MacdSubChart(
                        key: const ValueKey('linked_daily_macd_subchart'),
                        dataType: KLineDataType.daily,
                        cacheStore: widget.macdCacheStoreForTest,
                        height: macdSubChartHeight,
                        chartKey: const ValueKey('linked_daily_macd_paint'),
                      ),
                      AdxSubChart(
                        key: const ValueKey('linked_daily_adx_subchart'),
                        dataType: KLineDataType.daily,
                        cacheStore: widget.adxCacheStoreForTest,
                        height: adxSubChartHeight,
                        chartKey: const ValueKey('linked_daily_adx_paint'),
                      ),
                    ],
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
