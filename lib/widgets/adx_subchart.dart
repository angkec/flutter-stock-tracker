import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/theme/theme.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/kline_viewport.dart';

class AdxSubChart extends KLineSubChart {
  static final AdxCacheStore _sharedDefaultStore = AdxCacheStore();

  const AdxSubChart({
    this.key,
    required this.dataType,
    this.cacheStore,
    this.height = 110,
    this.chartKey,
    this.selectionLineColor,
    this.selectionLineWidth,
    this.selectionDashLength,
    this.selectionGapLength,
  });

  final Key? key;
  final KLineDataType dataType;
  final AdxCacheStore? cacheStore;
  final double height;
  final Key? chartKey;
  final Color? selectionLineColor;
  final double? selectionLineWidth;
  final double? selectionDashLength;
  final double? selectionGapLength;

  @override
  Widget buildSubChart(
    BuildContext context, {
    required String stockCode,
    required List<KLine> bars,
    required KLineViewport viewport,
    required int? selectedIndex,
    required bool isSelecting,
  }) {
    return _AdxSubChartBody(
      key: key,
      stockCode: stockCode,
      bars: bars,
      viewport: viewport,
      selectedIndex: selectedIndex,
      isSelecting: isSelecting,
      dataType: dataType,
      cacheStore: cacheStore ?? _sharedDefaultStore,
      height: height,
      chartKey: chartKey,
      selectionLineColor: selectionLineColor,
      selectionLineWidth: selectionLineWidth,
      selectionDashLength: selectionDashLength,
      selectionGapLength: selectionGapLength,
    );
  }
}

class _AdxSubChartBody extends StatefulWidget {
  const _AdxSubChartBody({
    super.key,
    required this.stockCode,
    required this.bars,
    required this.viewport,
    required this.selectedIndex,
    required this.isSelecting,
    required this.dataType,
    required this.cacheStore,
    required this.height,
    this.chartKey,
    this.selectionLineColor,
    this.selectionLineWidth,
    this.selectionDashLength,
    this.selectionGapLength,
  });

  final String stockCode;
  final List<KLine> bars;
  final KLineViewport viewport;
  final int? selectedIndex;
  final bool isSelecting;
  final KLineDataType dataType;
  final AdxCacheStore cacheStore;
  final double height;
  final Key? chartKey;
  final Color? selectionLineColor;
  final double? selectionLineWidth;
  final double? selectionDashLength;
  final double? selectionGapLength;

  @override
  State<_AdxSubChartBody> createState() => _AdxSubChartBodyState();
}

class _AdxSubChartBodyState extends State<_AdxSubChartBody> {
  AdxCacheSeries? _series;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void didUpdateWidget(covariant _AdxSubChartBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stockCode != widget.stockCode ||
        oldWidget.dataType != widget.dataType ||
        oldWidget.cacheStore != widget.cacheStore ||
        oldWidget.bars != widget.bars) {
      _loadSeries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = widget.dataType == KLineDataType.daily ? 'ADX(日)' : 'ADX(周)';
    final resolved = _resolveViewportSeries();
    final points = resolved?.points;
    final selectedVisibleIndex = _resolveSelectedVisibleIndex();
    final activePoint = _resolveActivePoint(
      resolved: resolved,
      selectedVisibleIndex: selectedVisibleIndex,
    );
    final activeDate = _resolveActiveDate(
      resolved: resolved,
      selectedVisibleIndex: selectedVisibleIndex,
    );
    final threshold = (_series?.config.threshold ?? 25).toDouble();
    final isDark = theme.brightness == Brightness.dark;
    final selectionLineColor =
        widget.selectionLineColor ??
        ((isDark ? Colors.white : Colors.black).withValues(alpha: 0.7));
    final selectionLineWidth = widget.selectionLineWidth ?? 1.0;
    final selectionDashLength = widget.selectionDashLength ?? 4.0;
    final selectionGapLength = widget.selectionGapLength ?? 3.0;

    return SizedBox(
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.18),
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
                child: _buildInfoRow(
                  context: context,
                  title: title,
                  activePoint: activePoint,
                  activeDate: activeDate,
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (points == null
                        ? Center(
                            child: Text(
                              '暂无ADX缓存，请先在数据管理同步',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Builder(
                            builder: (context) {
                              final resolvedSeries = resolved!;
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: CustomPaint(
                                  key: widget.chartKey,
                                  painter: AdxSubChartPainter(
                                    points: points,
                                    threshold: threshold,
                                    totalSlotCount:
                                        resolvedSeries.totalSlotCount,
                                    firstSlotIndex:
                                        resolvedSeries.firstSlotIndex,
                                    selectedVisibleIndex: selectedVisibleIndex,
                                    selectionLineColor: selectionLineColor,
                                    selectionLineWidth: selectionLineWidth,
                                    selectionDashLength: selectionDashLength,
                                    selectionGapLength: selectionGapLength,
                                    gridColor: Colors.grey.withValues(
                                      alpha: 0.1,
                                    ),
                                    thresholdLineColor: colorScheme.tertiary
                                        .withValues(alpha: 0.85),
                                    adxLineColor: Colors.orange,
                                    plusDiLineColor: AppColors.stockUp,
                                    minusDiLineColor: AppColors.stockDown,
                                  ),
                                  size: Size.infinite,
                                ),
                              );
                            },
                          )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required BuildContext context,
    required String title,
    required AdxPoint? activePoint,
    required DateTime? activeDate,
  }) {
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: 12, color: Colors.grey);
    final dateText = activeDate == null
        ? '--/--/--'
        : '${activeDate.year}/${activeDate.month}/${activeDate.day}';

    return Row(
      children: [
        Text(title, style: baseStyle?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(dateText, style: baseStyle),
        if (activePoint != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'ADX ${activePoint.adx.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+DI ${activePoint.plusDi.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: AppColors.stockUp),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-DI ${activePoint.minusDi.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: AppColors.stockDown),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  AdxPoint? _resolveActivePoint({
    required _ResolvedViewportAdx? resolved,
    required int? selectedVisibleIndex,
  }) {
    final points = resolved?.points;
    if (points == null || points.isEmpty) {
      return null;
    }
    if (selectedVisibleIndex != null &&
        resolved != null &&
        selectedVisibleIndex >= resolved.firstSlotIndex &&
        selectedVisibleIndex <
            resolved.firstSlotIndex + resolved.points.length) {
      final pointIndex = selectedVisibleIndex - resolved.firstSlotIndex;
      return points[pointIndex];
    }
    if (selectedVisibleIndex != null) {
      return null;
    }
    return points.last;
  }

  DateTime? _resolveActiveDate({
    required _ResolvedViewportAdx? resolved,
    required int? selectedVisibleIndex,
  }) {
    final points = resolved?.points;
    if (points == null || points.isEmpty || widget.bars.isEmpty) {
      return null;
    }

    final start = widget.viewport.startIndex;
    final visibleIndex = selectedVisibleIndex == null
        ? resolved!.firstSlotIndex + points.length - 1
        : selectedVisibleIndex;
    if (selectedVisibleIndex != null &&
        resolved != null &&
        (selectedVisibleIndex < resolved.firstSlotIndex ||
            selectedVisibleIndex >=
                resolved.firstSlotIndex + resolved.points.length)) {
      return null;
    }
    final globalIndex = start + visibleIndex;
    if (globalIndex < 0 || globalIndex >= widget.bars.length) {
      return null;
    }
    return widget.bars[globalIndex].datetime;
  }

  Future<void> _loadSeries() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final loaded = await widget.cacheStore.loadSeries(
        stockCode: widget.stockCode,
        dataType: widget.dataType,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _series = loaded;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _series = null;
        _isLoading = false;
      });
    }
  }

  _ResolvedViewportAdx? _resolveViewportSeries() {
    final series = _series;
    if (series == null || series.points.isEmpty || widget.bars.isEmpty) {
      return null;
    }

    final dateToPoint = <int, AdxPoint>{
      for (final point in series.points) _dateKey(point.datetime): point,
    };

    final total = widget.bars.length;
    final safeVisibleCount =
        widget.viewport.visibleCount.clamp(0, total) as int;
    final safeStart =
        widget.viewport.startIndex.clamp(
              0,
              math.max(0, total - safeVisibleCount),
            )
            as int;
    final safeEnd = (safeStart + safeVisibleCount).clamp(0, total);

    if (safeEnd <= safeStart) {
      return null;
    }

    final visibleBars = widget.bars.sublist(safeStart, safeEnd);
    final visiblePoints = <AdxPoint>[];
    var firstSlotIndex = -1;
    for (var slot = 0; slot < visibleBars.length; slot++) {
      final bar = visibleBars[slot];
      final point = dateToPoint[_dateKey(bar.datetime)];
      if (point == null) {
        if (firstSlotIndex >= 0) {
          return null;
        }
        continue;
      }
      if (firstSlotIndex < 0) {
        firstSlotIndex = slot;
      }
      visiblePoints.add(point);
    }
    if (visiblePoints.isEmpty || firstSlotIndex < 0) {
      return null;
    }

    return _ResolvedViewportAdx(
      points: visiblePoints,
      totalSlotCount: visibleBars.length,
      firstSlotIndex: firstSlotIndex,
    );
  }

  int _dateKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  int? _resolveSelectedVisibleIndex() {
    if (!widget.isSelecting || widget.selectedIndex == null) {
      return null;
    }

    final selectedIndex = widget.selectedIndex!;
    final start = widget.viewport.startIndex;
    final endExclusive = widget.viewport.endIndex;

    if (selectedIndex < start || selectedIndex >= endExclusive) {
      return null;
    }
    return selectedIndex - start;
  }
}

class _ResolvedViewportAdx {
  const _ResolvedViewportAdx({
    required this.points,
    required this.totalSlotCount,
    required this.firstSlotIndex,
  });

  final List<AdxPoint> points;
  final int totalSlotCount;
  final int firstSlotIndex;
}

class AdxSubChartPainter extends CustomPainter {
  const AdxSubChartPainter({
    required this.points,
    required this.threshold,
    this.totalSlotCount,
    this.firstSlotIndex = 0,
    this.selectedVisibleIndex,
    this.selectionLineColor = const Color(0xB3000000),
    this.selectionLineWidth = 1.0,
    this.selectionDashLength = 4.0,
    this.selectionGapLength = 3.0,
    this.gridColor = const Color(0x1A9E9E9E),
    this.thresholdLineColor = const Color(0xFF009688),
    this.adxLineColor = Colors.orange,
    this.plusDiLineColor = AppColors.stockUp,
    this.minusDiLineColor = AppColors.stockDown,
    this.sidePadding = 5,
    this.topPadding = 6,
    this.bottomPadding = 6,
  });

  final List<AdxPoint> points;
  final double threshold;
  final int? totalSlotCount;
  final int firstSlotIndex;
  final int? selectedVisibleIndex;
  final Color selectionLineColor;
  final double selectionLineWidth;
  final double selectionDashLength;
  final double selectionGapLength;
  final Color gridColor;
  final Color thresholdLineColor;
  final Color adxLineColor;
  final Color plusDiLineColor;
  final Color minusDiLineColor;
  final double sidePadding;
  final double topPadding;
  final double bottomPadding;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    final drawWidth = math.max(1.0, size.width - sidePadding * 2);
    final drawableHeight = math.max(
      1.0,
      size.height - topPadding - bottomPadding,
    );

    var minValue = double.infinity;
    var maxValue = double.negativeInfinity;
    for (final point in points) {
      minValue = math.min(
        minValue,
        math.min(point.adx, math.min(point.plusDi, point.minusDi)),
      );
      maxValue = math.max(
        maxValue,
        math.max(point.adx, math.max(point.plusDi, point.minusDi)),
      );
    }
    minValue = math.min(minValue, threshold);
    maxValue = math.max(maxValue, threshold);
    if ((maxValue - minValue).abs() < 1e-6) {
      maxValue = minValue + 1;
    }

    double toY(double value) {
      final t = (value - minValue) / (maxValue - minValue);
      return topPadding + (1 - t) * drawableHeight;
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    const gridLines = 4;
    for (var i = 1; i < gridLines; i++) {
      final y = topPadding + drawableHeight * i / gridLines;
      canvas.drawLine(
        Offset(sidePadding, y),
        Offset(size.width - sidePadding, y),
        gridPaint,
      );
    }

    final thresholdPaint = Paint()
      ..color = thresholdLineColor
      ..strokeWidth = 1.0;
    final thresholdY = toY(threshold);
    canvas.drawLine(
      Offset(sidePadding, thresholdY),
      Offset(size.width - sidePadding, thresholdY),
      thresholdPaint,
    );

    final slotCount = math.max(
      totalSlotCount ?? points.length,
      firstSlotIndex + points.length,
    );
    final spacing = drawWidth / slotCount;

    final adxPath = Path();
    final plusPath = Path();
    final minusPath = Path();

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final x = sidePadding + spacing * (firstSlotIndex + i + 0.5);
      final adxY = toY(point.adx);
      final plusY = toY(point.plusDi);
      final minusY = toY(point.minusDi);
      if (i == 0) {
        adxPath.moveTo(x, adxY);
        plusPath.moveTo(x, plusY);
        minusPath.moveTo(x, minusY);
      } else {
        adxPath.lineTo(x, adxY);
        plusPath.lineTo(x, plusY);
        minusPath.lineTo(x, minusY);
      }
    }

    canvas.drawPath(
      adxPath,
      Paint()
        ..color = adxLineColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      plusPath,
      Paint()
        ..color = plusDiLineColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      minusPath,
      Paint()
        ..color = minusDiLineColor
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    if (selectedVisibleIndex != null &&
        selectedVisibleIndex! >= firstSlotIndex &&
        selectedVisibleIndex! < firstSlotIndex + points.length) {
      final selectedX = sidePadding + spacing * (selectedVisibleIndex! + 0.5);
      final dashPaint = Paint()
        ..color = selectionLineColor
        ..strokeWidth = selectionLineWidth;
      var y = topPadding;
      final bottom = size.height - bottomPadding;
      while (y < bottom) {
        final endY = (y + selectionDashLength).clamp(topPadding, bottom);
        canvas.drawLine(
          Offset(selectedX, y),
          Offset(selectedX, endY),
          dashPaint,
        );
        y += selectionDashLength + selectionGapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant AdxSubChartPainter oldDelegate) {
    return !listEquals(oldDelegate.points, points) ||
        oldDelegate.threshold != threshold ||
        oldDelegate.totalSlotCount != totalSlotCount ||
        oldDelegate.firstSlotIndex != firstSlotIndex ||
        oldDelegate.selectedVisibleIndex != selectedVisibleIndex ||
        oldDelegate.selectionLineColor != selectionLineColor ||
        oldDelegate.selectionLineWidth != selectionLineWidth ||
        oldDelegate.selectionDashLength != selectionDashLength ||
        oldDelegate.selectionGapLength != selectionGapLength ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.thresholdLineColor != thresholdLineColor ||
        oldDelegate.adxLineColor != adxLineColor ||
        oldDelegate.plusDiLineColor != plusDiLineColor ||
        oldDelegate.minusDiLineColor != minusDiLineColor ||
        oldDelegate.sidePadding != sidePadding ||
        oldDelegate.topPadding != topPadding ||
        oldDelegate.bottomPadding != bottomPadding;
  }
}
