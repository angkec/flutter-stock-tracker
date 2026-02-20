import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/kline_viewport.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';

abstract class KLineSubChart {
  const KLineSubChart();

  Widget buildSubChart(
    BuildContext context, {
    required String stockCode,
    required List<KLine> bars,
    required KLineViewport viewport,
    required int? selectedIndex,
    required bool isSelecting,
  });
}

class KLineChartWithSubCharts extends StatefulWidget {
  const KLineChartWithSubCharts({
    super.key,
    required this.stockCode,
    required this.bars,
    this.ratios,
    this.chartHeight = 280,
    this.markedIndices,
    this.nearMissIndices,
    this.getDetectionResult,
    this.onScaling,
    this.linkedPane,
    this.onLinkedTouchEvent,
    this.externalLinkedState,
    this.externalLinkedBarIndex,
    this.showWeeklySeparators = false,
    this.subCharts = const <KLineSubChart>[],
    this.subChartSpacing = 10,
    this.emaShortSeries,
    this.emaLongSeries,
    this.candleColorResolver,
  });

  final String stockCode;
  final List<KLine> bars;
  final List<DailyRatio>? ratios;
  final double chartHeight;
  final Set<int>? markedIndices;
  final Map<int, int>? nearMissIndices;
  final BreakoutDetectionResult? Function(int index)? getDetectionResult;
  final ValueChanged<bool>? onScaling;
  final LinkedPane? linkedPane;
  final ValueChanged<LinkedTouchEvent>? onLinkedTouchEvent;
  final LinkedCrosshairState? externalLinkedState;
  final int? externalLinkedBarIndex;
  final bool showWeeklySeparators;
  final List<KLineSubChart> subCharts;
  final double subChartSpacing;
  final List<double?>? emaShortSeries;
  final List<double?>? emaLongSeries;
  final Color? Function(KLine bar, int globalIndex)? candleColorResolver;

  @override
  State<KLineChartWithSubCharts> createState() =>
      _KLineChartWithSubChartsState();
}

class _KLineChartWithSubChartsState extends State<KLineChartWithSubCharts> {
  late KLineViewport _viewport;
  int? _selectedIndex;
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _viewport = _buildFallbackViewport(widget.bars);
  }

  @override
  void didUpdateWidget(covariant KLineChartWithSubCharts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bars != widget.bars) {
      _viewport = _buildFallbackViewport(widget.bars);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KLineChart(
          bars: widget.bars,
          ratios: widget.ratios,
          height: widget.chartHeight,
          markedIndices: widget.markedIndices,
          nearMissIndices: widget.nearMissIndices,
          getDetectionResult: widget.getDetectionResult,
          onScaling: widget.onScaling,
          linkedPane: widget.linkedPane,
          onLinkedTouchEvent: widget.onLinkedTouchEvent,
          externalLinkedState: widget.externalLinkedState,
          externalLinkedBarIndex: widget.externalLinkedBarIndex,
          showWeeklySeparators: widget.showWeeklySeparators,
          onViewportChanged: _handleViewportChanged,
          onSelectionChanged: _handleSelectionChanged,
          emaShortSeries: widget.emaShortSeries,
          emaLongSeries: widget.emaLongSeries,
          candleColorResolver: widget.candleColorResolver,
        ),
        for (var index = 0; index < widget.subCharts.length; index++) ...[
          SizedBox(height: widget.subChartSpacing),
          widget.subCharts[index].buildSubChart(
            context,
            stockCode: widget.stockCode,
            bars: widget.bars,
            viewport: _viewport,
            selectedIndex: _selectedIndex,
            isSelecting: _isSelecting,
          ),
        ],
      ],
    );
  }

  void _handleViewportChanged(KLineViewport viewport) {
    if (_viewport == viewport) {
      return;
    }
    setState(() {
      _viewport = viewport;
    });
  }

  void _handleSelectionChanged(int? selectedIndex, bool isSelecting) {
    if (_selectedIndex == selectedIndex && _isSelecting == isSelecting) {
      return;
    }
    setState(() {
      _selectedIndex = selectedIndex;
      _isSelecting = isSelecting;
    });
  }

  KLineViewport _buildFallbackViewport(List<KLine> bars) {
    final totalCount = bars.length;
    if (totalCount <= 0) {
      return const KLineViewport(startIndex: 0, visibleCount: 0, totalCount: 0);
    }

    const defaultVisibleCount = 30;
    final visibleCount = defaultVisibleCount.clamp(1, totalCount);
    final startIndex = (totalCount - visibleCount).clamp(0, totalCount - 1);

    return KLineViewport(
      startIndex: startIndex,
      visibleCount: visibleCount,
      totalCount: totalCount,
    );
  }
}
