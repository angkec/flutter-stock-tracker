import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/linked_layout_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_coordinator.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/adx_subchart.dart';
import 'package:stock_rtwatcher/widgets/macd_subchart.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/widgets/power_system_candle_color.dart';

class LinkedDualKlineView extends StatefulWidget {
  const LinkedDualKlineView({
    super.key,
    required this.stockCode,
    required this.weeklyBars,
    required this.dailyBars,
    required this.ratios,
    this.layout,
    this.macdCacheStoreForTest,
    this.adxCacheStoreForTest,
    this.emaCacheStoreForTest,
    this.powerSystemCacheStoreForTest,
  });

  final String stockCode;
  final List<KLine> weeklyBars;
  final List<KLine> dailyBars;
  final List<DailyRatio> ratios;
  final LinkedLayoutResult? layout;
  final MacdCacheStore? macdCacheStoreForTest;
  final AdxCacheStore? adxCacheStoreForTest;
  final EmaCacheStore? emaCacheStoreForTest;
  final PowerSystemCacheStore? powerSystemCacheStoreForTest;

  @override
  State<LinkedDualKlineView> createState() => _LinkedDualKlineViewState();
}

class _LinkedDualKlineViewState extends State<LinkedDualKlineView> {
  late LinkedCrosshairCoordinator _coordinator;

  List<double?>? _weeklyEmaShort;
  List<double?>? _weeklyEmaLong;
  List<double?>? _dailyEmaShort;
  List<double?>? _dailyEmaLong;
  CandleColorResolver? _weeklyPowerSystemColorResolver;
  CandleColorResolver? _dailyPowerSystemColorResolver;

  @override
  void initState() {
    super.initState();
    _coordinator = LinkedCrosshairCoordinator(
      weeklyBars: widget.weeklyBars,
      dailyBars: widget.dailyBars,
    );
    _loadEmaOverlays();
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
      _loadEmaOverlays();
    }
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  Future<void> _loadEmaOverlays() async {
    final store = widget.emaCacheStoreForTest ?? EmaCacheStore();
    final powerStore =
        widget.powerSystemCacheStoreForTest ?? PowerSystemCacheStore();
    final code = widget.stockCode;

    final emaResults = await Future.wait([
      store.loadSeries(stockCode: code, dataType: KLineDataType.weekly),
      store.loadSeries(stockCode: code, dataType: KLineDataType.daily),
    ]);

    if (!mounted) return;

    final weeklySeries = emaResults[0] as EmaCacheSeries?;
    final dailySeries = emaResults[1] as EmaCacheSeries?;

    setState(() {
      if (weeklySeries != null) {
        final aligned = _alignEmaToBars(widget.weeklyBars, weeklySeries);
        _weeklyEmaShort = aligned.$1;
        _weeklyEmaLong = aligned.$2;
      }
      if (dailySeries != null) {
        final aligned = _alignEmaToBars(widget.dailyBars, dailySeries);
        _dailyEmaShort = aligned.$1;
        _dailyEmaLong = aligned.$2;
      }
    });

    final powerResults = await Future.wait([
      powerStore.loadSeries(stockCode: code, dataType: KLineDataType.weekly),
      powerStore.loadSeries(stockCode: code, dataType: KLineDataType.daily),
    ]);
    if (!mounted) return;

    final weeklyPowerSeries = powerResults[0] as PowerSystemCacheSeries?;
    final dailyPowerSeries = powerResults[1] as PowerSystemCacheSeries?;
    setState(() {
      _weeklyPowerSystemColorResolver = weeklyPowerSeries == null
          ? null
          : PowerSystemCandleColor.fromSeries(weeklyPowerSeries);
      _dailyPowerSystemColorResolver = dailyPowerSeries == null
          ? null
          : PowerSystemCandleColor.fromSeries(dailyPowerSeries);
    });
  }

  (List<double?>, List<double?>) _alignEmaToBars(
    List<KLine> bars,
    EmaCacheSeries series,
  ) {
    final pointMap = <String, EmaPoint>{};
    for (final p in series.points) {
      final key = '${p.datetime.year}-${p.datetime.month}-${p.datetime.day}';
      pointMap[key] = p;
    }

    final shortList = List<double?>.filled(bars.length, null);
    final longList = List<double?>.filled(bars.length, null);

    for (var i = 0; i < bars.length; i++) {
      final d = bars[i].datetime;
      final key = '${d.year}-${d.month}-${d.day}';
      final point = pointMap[key];
      if (point != null) {
        shortList[i] = point.emaShort;
        longList[i] = point.emaLong;
      }
    }

    return (shortList, longList);
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
                  final heights = _resolveWeeklyHeights(constraints.maxHeight);

                  return KLineChartWithSubCharts(
                    key: const ValueKey('linked_weekly_chart'),
                    stockCode: widget.stockCode,
                    bars: widget.weeklyBars,
                    chartHeight: heights.mainChartHeight,
                    linkedPane: LinkedPane.weekly,
                    onLinkedTouchEvent: _coordinator.handleTouch,
                    externalLinkedState: _coordinator.stateForPane(
                      LinkedPane.weekly,
                    ),
                    externalLinkedBarIndex: _coordinator.mappedWeeklyIndex,
                    showWeeklySeparators: false,
                    subChartSpacing: heights.subChartSpacing,
                    emaShortSeries: _weeklyEmaShort,
                    emaLongSeries: _weeklyEmaLong,
                    candleColorResolver: _weeklyPowerSystemColorResolver,
                    subCharts: [
                      MacdSubChart(
                        key: const ValueKey('linked_weekly_macd_subchart'),
                        dataType: KLineDataType.weekly,
                        cacheStore: widget.macdCacheStoreForTest,
                        height: heights.macdSubChartHeight,
                        chartKey: const ValueKey('linked_weekly_macd_paint'),
                      ),
                      AdxSubChart(
                        key: const ValueKey('linked_weekly_adx_subchart'),
                        dataType: KLineDataType.weekly,
                        cacheStore: widget.adxCacheStoreForTest,
                        height: heights.adxSubChartHeight,
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
                  final heights = _resolveDailyHeights(constraints.maxHeight);

                  return KLineChartWithSubCharts(
                    key: const ValueKey('linked_daily_chart'),
                    stockCode: widget.stockCode,
                    bars: widget.dailyBars,
                    ratios: widget.ratios,
                    chartHeight: heights.mainChartHeight,
                    linkedPane: LinkedPane.daily,
                    onLinkedTouchEvent: _coordinator.handleTouch,
                    externalLinkedState: _coordinator.stateForPane(
                      LinkedPane.daily,
                    ),
                    externalLinkedBarIndex: _coordinator.mappedDailyIndex,
                    showWeeklySeparators: true,
                    subChartSpacing: heights.subChartSpacing,
                    emaShortSeries: _dailyEmaShort,
                    emaLongSeries: _dailyEmaLong,
                    candleColorResolver: _dailyPowerSystemColorResolver,
                    subCharts: [
                      MacdSubChart(
                        key: const ValueKey('linked_daily_macd_subchart'),
                        dataType: KLineDataType.daily,
                        cacheStore: widget.macdCacheStoreForTest,
                        height: heights.macdSubChartHeight,
                        chartKey: const ValueKey('linked_daily_macd_paint'),
                      ),
                      AdxSubChart(
                        key: const ValueKey('linked_daily_adx_subchart'),
                        dataType: KLineDataType.daily,
                        cacheStore: widget.adxCacheStoreForTest,
                        height: heights.adxSubChartHeight,
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

  _LinkedPaneHeights _resolveWeeklyHeights(double paneHeight) {
    const defaultInfoHeight = 24.0;
    const defaultSubChartSpacing = 10.0;
    const defaultMacdHeight = 78.0;
    const defaultAdxHeight = 78.0;

    final layout = widget.layout;
    if (layout == null) {
      final chartHeight =
          paneHeight -
          defaultInfoHeight -
          defaultSubChartSpacing -
          defaultSubChartSpacing -
          defaultMacdHeight -
          defaultAdxHeight;
      return _LinkedPaneHeights(
        mainChartHeight: chartHeight.clamp(10.0, double.infinity),
        macdSubChartHeight: defaultMacdHeight,
        adxSubChartHeight: defaultAdxHeight,
        subChartSpacing: defaultSubChartSpacing,
      );
    }

    final subHeights = layout.top.subchartHeights;
    return _LinkedPaneHeights(
      mainChartHeight: layout.top.mainChartHeight,
      macdSubChartHeight: subHeights.isNotEmpty
          ? subHeights.first
          : defaultMacdHeight,
      adxSubChartHeight: subHeights.length > 1
          ? subHeights[1]
          : defaultAdxHeight,
      subChartSpacing: defaultSubChartSpacing,
    );
  }

  _LinkedPaneHeights _resolveDailyHeights(double paneHeight) {
    const defaultInfoHeight = 24.0;
    const defaultSubChartSpacing = 10.0;
    const defaultMacdHeight = 84.0;
    const defaultAdxHeight = 84.0;

    final layout = widget.layout;
    if (layout == null) {
      final chartHeight =
          paneHeight -
          defaultInfoHeight -
          defaultSubChartSpacing -
          defaultSubChartSpacing -
          defaultMacdHeight -
          defaultAdxHeight;
      return _LinkedPaneHeights(
        mainChartHeight: chartHeight.clamp(50.0, double.infinity),
        macdSubChartHeight: defaultMacdHeight,
        adxSubChartHeight: defaultAdxHeight,
        subChartSpacing: defaultSubChartSpacing,
      );
    }

    final subHeights = layout.bottom.subchartHeights;
    return _LinkedPaneHeights(
      mainChartHeight: layout.bottom.mainChartHeight,
      macdSubChartHeight: subHeights.isNotEmpty
          ? subHeights.first
          : defaultMacdHeight,
      adxSubChartHeight: subHeights.length > 1
          ? subHeights[1]
          : defaultAdxHeight,
      subChartSpacing: defaultSubChartSpacing,
    );
  }
}

class _LinkedPaneHeights {
  const _LinkedPaneHeights({
    required this.mainChartHeight,
    required this.macdSubChartHeight,
    required this.adxSubChartHeight,
    required this.subChartSpacing,
  });

  final double mainChartHeight;
  final double macdSubChartHeight;
  final double adxSubChartHeight;
  final double subChartSpacing;
}
