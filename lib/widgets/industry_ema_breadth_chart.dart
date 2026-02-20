import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';

class IndustryEmaBreadthChart extends StatefulWidget {
  const IndustryEmaBreadthChart({
    super.key,
    required this.series,
    required this.config,
    this.height = 164,
    this.lineColor,
    this.gridColor,
    this.onSelectedPointChanged,
  });

  final IndustryEmaBreadthSeries? series;
  final IndustryEmaBreadthConfig config;
  final double height;
  final Color? lineColor;
  final Color? gridColor;
  final ValueChanged<IndustryEmaBreadthPoint?>? onSelectedPointChanged;

  @override
  State<IndustryEmaBreadthChart> createState() =>
      _IndustryEmaBreadthChartState();
}

class _IndustryEmaBreadthChartState extends State<IndustryEmaBreadthChart> {
  int _selectedIndex = 0;

  static const double _horizontalPadding = 16.0;
  static const double _topPadding = 12.0;
  static const double _bottomPadding = 24.0;

  IndustryEmaBreadthPoint? get _selectedPoint {
    final points = widget.series?.points ?? const [];
    if (points.isEmpty) return null;
    // Find the index of a valid (non-null percent) point closest to _selectedIndex
    final validIndices = <int>[];
    for (var i = 0; i < points.length; i++) {
      if (points[i].percent != null) {
        validIndices.add(i);
      }
    }
    if (validIndices.isEmpty) return null;
    final clampedIndex = _selectedIndex.clamp(0, points.length - 1);
    // Find the closest valid point to the selected index
    int closestIndex = validIndices.first;
    for (final idx in validIndices) {
      if ((idx - clampedIndex).abs() < (closestIndex - clampedIndex).abs()) {
        closestIndex = idx;
      }
    }
    return points[closestIndex];
  }

  int _resolveIndex(double dx, double width) {
    final points = widget.series?.points ?? const [];
    if (points.length <= 1) return 0;
    final usableWidth = (width - _horizontalPadding * 2).clamp(1.0, width);
    final localX = (dx - _horizontalPadding).clamp(0.0, usableWidth);
    final step = usableWidth / (points.length - 1);
    return (localX / step).round().clamp(0, points.length - 1);
  }

  void _updateSelection(int index) {
    final points = widget.series?.points ?? const [];
    if (points.isEmpty) return;
    final clampedIndex = index.clamp(0, points.length - 1);
    if (_selectedIndex != clampedIndex) {
      setState(() {
        _selectedIndex = clampedIndex;
      });
      widget.onSelectedPointChanged?.call(_selectedPoint);
    }
  }

  @override
  void didUpdateWidget(covariant IndustryEmaBreadthChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset selection when series changes
    if (oldWidget.series?.points.length != widget.series?.points.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveLineColor = widget.lineColor ?? theme.colorScheme.primary;
    final effectiveGridColor =
        widget.gridColor ?? theme.colorScheme.outlineVariant;
    final points = widget.series?.points ?? const <IndustryEmaBreadthPoint>[];
    final latest = points.isEmpty ? null : points.last;
    final selectedPoint = _selectedPoint;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EMA13 广度',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          if (latest != null)
            Text(
              'Above ${latest.aboveCount} / Valid ${latest.validCount} / Missing ${latest.missingCount}',
              key: const ValueKey('industry_ema_breadth_latest_summary'),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              'Above - / Valid - / Missing -',
              key: const ValueKey('industry_ema_breadth_latest_summary'),
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Upper ${widget.config.upperThreshold.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Lower ${widget.config.lowerThreshold.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (points.isEmpty)
            SizedBox(
              height: widget.height,
              width: double.infinity,
              child: Center(
                child: Text(
                  '暂无 EMA 广度数据',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            SizedBox(
              height: widget.height,
              width: double.infinity,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      _updateSelection(
                        _resolveIndex(
                          details.localPosition.dx,
                          constraints.maxWidth,
                        ),
                      );
                    },
                    onHorizontalDragUpdate: (details) {
                      _updateSelection(
                        _resolveIndex(
                          details.localPosition.dx,
                          constraints.maxWidth,
                        ),
                      );
                    },
                    child: CustomPaint(
                      key: const ValueKey('industry_ema_breadth_custom_paint'),
                      size: Size(constraints.maxWidth, widget.height),
                      painter: IndustryEmaBreadthChartPainter(
                        points: points,
                        upperThreshold: widget.config.upperThreshold,
                        lowerThreshold: widget.config.lowerThreshold,
                        lineColor: effectiveLineColor,
                        gridColor: effectiveGridColor,
                        selectedIndex: selectedPoint != null
                            ? points.indexOf(selectedPoint)
                            : -1,
                      ),
                    ),
                  );
                },
              ),
            ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '手指滑动或点击图表可选择日期',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (selectedPoint != null) ...[
            const SizedBox(height: 6),
            _buildSelectedDetail(context, selectedPoint, effectiveLineColor),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedDetail(
    BuildContext context,
    IndustryEmaBreadthPoint point,
    Color lineColor,
  ) {
    final theme = Theme.of(context);
    final dateStr =
        '${point.date.year}-'
        '${point.date.month.toString().padLeft(2, '0')}-'
        '${point.date.day.toString().padLeft(2, '0')}';
    final percentStr = point.percent != null
        ? '${point.percent!.toStringAsFixed(0)}%'
        : '-';

    return Container(
      key: const ValueKey('industry_ema_breadth_selected_detail'),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '选中 $dateStr  广度 $percentStr  '
        'Above ${point.aboveCount} / Valid ${point.validCount} / Missing ${point.missingCount}',
        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class IndustryEmaBreadthChartPainter extends CustomPainter {
  IndustryEmaBreadthChartPainter({
    required this.points,
    required this.upperThreshold,
    required this.lowerThreshold,
    required this.lineColor,
    required this.gridColor,
    this.selectedIndex = -1,
  }) : lineSegmentCount = _countLineSegments(points);

  final List<IndustryEmaBreadthPoint> points;
  final double upperThreshold;
  final double lowerThreshold;
  final Color lineColor;
  final Color gridColor;
  final int selectedIndex;
  final int lineSegmentCount;

  static int _countLineSegments(List<IndustryEmaBreadthPoint> points) {
    var segments = 0;
    IndustryEmaBreadthPoint? previous;
    for (final point in points) {
      if (point.percent == null) {
        previous = null;
        continue;
      }
      if (previous?.percent != null) {
        segments++;
      }
      previous = point;
    }
    return segments;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const padding = EdgeInsets.only(left: 16, top: 12, right: 16, bottom: 24);
    final chartArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );

    _drawThresholdLine(canvas, chartArea, upperThreshold, 'U');
    _drawThresholdLine(canvas, chartArea, lowerThreshold, 'L');

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final divisor = points.length > 1 ? points.length - 1 : 1;
    Offset? lastDrawn;
    Offset? latestDrawn;
    double? latestValue;

    for (var i = 0; i < points.length; i++) {
      final percent = points[i].percent;
      if (percent == null) {
        lastDrawn = null;
        continue;
      }

      final point = Offset(
        chartArea.left + (i / divisor) * chartArea.width,
        chartArea.bottom - (percent / 100.0) * chartArea.height,
      );

      if (lastDrawn != null) {
        canvas.drawLine(lastDrawn, point, linePaint);
      }
      lastDrawn = point;
      latestDrawn = point;
      latestValue = percent;

      canvas.drawCircle(point, 3.2, dotBorderPaint);
      canvas.drawCircle(point, 3.2, dotPaint);
    }

    if (latestDrawn != null && latestValue != null) {
      _drawLatestLabel(canvas, chartArea, latestDrawn, latestValue);
    }

    // Draw selected marker
    if (selectedIndex >= 0 && selectedIndex < points.length) {
      final selectedPointData = points[selectedIndex];
      if (selectedPointData.percent != null) {
        final selectedPoint = Offset(
          chartArea.left + (selectedIndex / divisor) * chartArea.width,
          chartArea.bottom -
              (selectedPointData.percent! / 100.0) * chartArea.height,
        );
        // Draw vertical line
        final markerPaint = Paint()
          ..color = lineColor.withValues(alpha: 0.35)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(selectedPoint.dx, chartArea.top),
          Offset(selectedPoint.dx, chartArea.bottom),
          markerPaint,
        );
        // Draw larger selected dot
        final selectedDotPaint = Paint()
          ..color = lineColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(selectedPoint, 5.0, selectedDotPaint);
        final selectedDotBorderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(selectedPoint, 5.0, selectedDotBorderPaint);
      }
    }

    _drawDateLabels(canvas, chartArea);
  }

  void _drawThresholdLine(
    Canvas canvas,
    Rect chartArea,
    double threshold,
    String label,
  ) {
    final y = chartArea.bottom - (threshold / 100.0) * chartArea.height;
    if (y < chartArea.top || y > chartArea.bottom) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    var startX = chartArea.left;
    while (startX < chartArea.right) {
      canvas.drawLine(
        Offset(startX, y),
        Offset((startX + dashWidth).clamp(chartArea.left, chartArea.right), y),
        gridPaint,
      );
      startX += dashWidth + dashSpace;
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$label ${threshold.toStringAsFixed(0)}%',
        style: TextStyle(color: gridColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(chartArea.left, y - textPainter.height - 2),
    );
  }

  void _drawLatestLabel(
    Canvas canvas,
    Rect chartArea,
    Offset point,
    double value,
  ) {
    final labelPainter = TextPainter(
      text: TextSpan(
        text: '${value.toStringAsFixed(0)}%',
        style: TextStyle(
          color: lineColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = (point.dx - labelPainter.width - 8).clamp(
      chartArea.left,
      chartArea.right - labelPainter.width,
    );
    final dy = (point.dy - labelPainter.height - 4).clamp(
      chartArea.top,
      chartArea.bottom - labelPainter.height,
    );
    labelPainter.paint(canvas, Offset(dx, dy));
  }

  void _drawDateLabels(Canvas canvas, Rect chartArea) {
    if (points.isEmpty) return;
    final first = _formatDate(points.first.date);
    final firstPainter = TextPainter(
      text: TextSpan(
        text: first,
        style: TextStyle(color: gridColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    firstPainter.paint(canvas, Offset(chartArea.left, chartArea.bottom + 4));

    if (points.length > 1) {
      final last = _formatDate(points.last.date);
      final lastPainter = TextPainter(
        text: TextSpan(
          text: last,
          style: TextStyle(color: gridColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lastPainter.paint(
        canvas,
        Offset(chartArea.right - lastPainter.width, chartArea.bottom + 4),
      );
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  @override
  bool shouldRepaint(covariant IndustryEmaBreadthChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.upperThreshold != upperThreshold ||
        oldDelegate.lowerThreshold != lowerThreshold ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
