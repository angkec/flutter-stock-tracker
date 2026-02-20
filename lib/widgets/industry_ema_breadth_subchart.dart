import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/widgets/industry_ema_breadth_chart.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/kline_viewport.dart';

class IndustryEmaBreadthSubChart extends KLineSubChart {
  const IndustryEmaBreadthSubChart({
    this.key,
    required this.series,
    required this.config,
    this.height = 126,
    this.chartKey,
  });

  final Key? key;
  final IndustryEmaBreadthSeries? series;
  final IndustryEmaBreadthConfig config;
  final double height;
  final Key? chartKey;

  @override
  Widget buildSubChart(
    BuildContext context, {
    required String stockCode,
    required List<KLine> bars,
    required KLineViewport viewport,
    required int? selectedIndex,
    required bool isSelecting,
  }) {
    return _IndustryEmaBreadthSubChartBody(
      key: key,
      bars: bars,
      viewport: viewport,
      selectedIndex: selectedIndex,
      isSelecting: isSelecting,
      series: series,
      config: config,
      height: height,
      chartKey: chartKey,
    );
  }
}

class _IndustryEmaBreadthSubChartBody extends StatelessWidget {
  const _IndustryEmaBreadthSubChartBody({
    super.key,
    required this.bars,
    required this.viewport,
    required this.selectedIndex,
    required this.isSelecting,
    required this.series,
    required this.config,
    required this.height,
    this.chartKey,
  });

  final List<KLine> bars;
  final KLineViewport viewport;
  final int? selectedIndex;
  final bool isSelecting;
  final IndustryEmaBreadthSeries? series;
  final IndustryEmaBreadthConfig config;
  final double height;
  final Key? chartKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aligned = _resolveAlignedPoints();
    final selectedVisibleIndex = _resolveSelectedVisibleIndex();
    final active = _resolveActivePoint(aligned, selectedVisibleIndex);
    final activeDate = _resolveActiveDate(aligned, selectedVisibleIndex);

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildInfoRow(context, active, activeDate),
              ),
            ),
            Expanded(
              child: aligned == null
                  ? Center(
                      child: Text(
                        '暂无 EMA13 广度数据',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CustomPaint(
                        key: chartKey,
                        painter: IndustryEmaBreadthChartPainter(
                          points: aligned,
                          upperThreshold: config.upperThreshold,
                          lowerThreshold: config.lowerThreshold,
                          lineColor: theme.colorScheme.primary,
                          gridColor: theme.colorScheme.outlineVariant,
                          selectedIndex: selectedVisibleIndex ?? -1,
                        ),
                        size: Size.infinite,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IndustryEmaBreadthPoint? active,
    DateTime? activeDate,
  ) {
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey);
    final dateText = activeDate == null
        ? '--/--/--'
        : '${activeDate.year}/${activeDate.month}/${activeDate.day}';
    final breadthText = active?.percent == null
        ? '--'
        : '${active!.percent!.toStringAsFixed(0)}%';

    return Row(
      children: [
        Text(
          'EMA13广度',
          style: baseStyle?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Text(dateText, style: baseStyle),
        const SizedBox(width: 10),
        Text(
          '广度 $breadthText',
          style: const TextStyle(fontSize: 12, color: Colors.orange),
        ),
        if (active != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                'A ${active.aboveCount} / V ${active.validCount} / M ${active.missingCount}',
                style: const TextStyle(fontSize: 12, color: Colors.lightBlue),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<IndustryEmaBreadthPoint>? _resolveAlignedPoints() {
    final allPoints = series?.points;
    if (allPoints == null || allPoints.isEmpty || bars.isEmpty) {
      return null;
    }

    final total = bars.length;
    final safeVisibleCount = viewport.visibleCount.clamp(0, total).toInt();
    final safeStart = viewport.startIndex
        .clamp(0, math.max(0, total - safeVisibleCount))
        .toInt();
    final safeEnd = (safeStart + safeVisibleCount).clamp(0, total).toInt();
    if (safeEnd <= safeStart) {
      return null;
    }

    final pointByDate = <int, IndustryEmaBreadthPoint>{
      for (final point in allPoints) _dateKey(point.date): point,
    };

    final visibleBars = bars.sublist(safeStart, safeEnd);
    final aligned = <IndustryEmaBreadthPoint>[];
    for (final bar in visibleBars) {
      final point = pointByDate[_dateKey(bar.datetime)];
      if (point != null) {
        aligned.add(point);
      } else {
        aligned.add(
          IndustryEmaBreadthPoint(
            date: bar.datetime,
            percent: null,
            aboveCount: 0,
            validCount: 0,
            missingCount: 0,
          ),
        );
      }
    }
    return aligned;
  }

  int? _resolveSelectedVisibleIndex() {
    if (!isSelecting || selectedIndex == null) {
      return null;
    }
    final global = selectedIndex!;
    final start = viewport.startIndex;
    final end = viewport.endIndex;
    if (global < start || global >= end) {
      return null;
    }
    return global - start;
  }

  IndustryEmaBreadthPoint? _resolveActivePoint(
    List<IndustryEmaBreadthPoint>? aligned,
    int? selectedVisibleIndex,
  ) {
    if (aligned == null || aligned.isEmpty) {
      return null;
    }
    if (selectedVisibleIndex != null &&
        selectedVisibleIndex >= 0 &&
        selectedVisibleIndex < aligned.length) {
      final selected = aligned[selectedVisibleIndex];
      if (selected.percent != null) {
        return selected;
      }
      return null;
    }
    for (var i = aligned.length - 1; i >= 0; i--) {
      if (aligned[i].percent != null) {
        return aligned[i];
      }
    }
    return null;
  }

  DateTime? _resolveActiveDate(
    List<IndustryEmaBreadthPoint>? aligned,
    int? selectedVisibleIndex,
  ) {
    if (aligned == null || aligned.isEmpty) {
      return null;
    }
    if (selectedVisibleIndex != null &&
        selectedVisibleIndex >= 0 &&
        selectedVisibleIndex < aligned.length) {
      return aligned[selectedVisibleIndex].date;
    }
    final active = _resolveActivePoint(aligned, null);
    return active?.date;
  }

  int _dateKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;
}
