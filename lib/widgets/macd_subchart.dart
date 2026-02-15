import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';
import 'package:stock_rtwatcher/theme/theme.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/kline_viewport.dart';

class MacdSubChart extends KLineSubChart {
  static final MacdCacheStore _sharedDefaultStore = MacdCacheStore();

  const MacdSubChart({
    this.key,
    required this.dataType,
    this.cacheStore,
    this.height = 120,
    this.chartKey,
    this.selectionLineColor,
    this.selectionLineWidth,
    this.selectionDashLength,
    this.selectionGapLength,
  });

  final Key? key;
  final KLineDataType dataType;
  final MacdCacheStore? cacheStore;
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
    return _MacdSubChartBody(
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

class _MacdSubChartBody extends StatefulWidget {
  const _MacdSubChartBody({
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
  final MacdCacheStore cacheStore;
  final double height;
  final Key? chartKey;
  final Color? selectionLineColor;
  final double? selectionLineWidth;
  final double? selectionDashLength;
  final double? selectionGapLength;

  @override
  State<_MacdSubChartBody> createState() => _MacdSubChartBodyState();
}

class _MacdSubChartBodyState extends State<_MacdSubChartBody> {
  MacdCacheSeries? _series;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSeries();
  }

  @override
  void didUpdateWidget(covariant _MacdSubChartBody oldWidget) {
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
    final title = widget.dataType == KLineDataType.daily
        ? 'MACD(日)'
        : 'MACD(周)';
    final points = _resolveViewportPoints();
    final selectedVisibleIndex = _resolveSelectedVisibleIndex();
    final activePoint = _resolveActivePoint(
      points: points,
      selectedVisibleIndex: selectedVisibleIndex,
    );
    final activeDate = _resolveActiveDate(
      points: points,
      selectedVisibleIndex: selectedVisibleIndex,
    );
    final overlayTheme = theme.extension<ChartOverlayTheme>();
    final isDark = theme.brightness == Brightness.dark;
    final selectionLineColor =
        widget.selectionLineColor ??
        overlayTheme?.macdSelectionLineColor ??
        ((isDark ? Colors.white : Colors.black).withValues(alpha: 0.7));
    final selectionLineWidth =
        widget.selectionLineWidth ??
        overlayTheme?.macdSelectionLineWidth ??
        1.0;
    final selectionDashLength =
        widget.selectionDashLength ??
        overlayTheme?.macdSelectionDashLength ??
        4.0;
    final selectionGapLength =
        widget.selectionGapLength ??
        overlayTheme?.macdSelectionGapLength ??
        3.0;

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
                              '暂无MACD缓存，请先在数据管理同步',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: CustomPaint(
                              key: widget.chartKey,
                              painter: MacdSubChartPainter(
                                points: points,
                                selectedVisibleIndex: selectedVisibleIndex,
                                selectionLineColor: selectionLineColor,
                                selectionLineWidth: selectionLineWidth,
                                selectionDashLength: selectionDashLength,
                                selectionGapLength: selectionGapLength,
                                gridColor: Colors.grey.withValues(alpha: 0.1),
                                zeroLineColor: colorScheme.outline.withValues(
                                  alpha: 0.3,
                                ),
                                difLineColor: Colors.orange,
                                deaLineColor: Colors.lightBlue,
                              ),
                              size: Size.infinite,
                            ),
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
    required MacdPoint? activePoint,
    required DateTime? activeDate,
  }) {
    final baseStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: Colors.grey,
    );
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
                    'DIF ${activePoint.dif.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DEA ${activePoint.dea.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.lightBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MACD ${activePoint.hist.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: activePoint.hist >= 0
                          ? AppColors.stockUp
                          : AppColors.stockDown,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  MacdPoint? _resolveActivePoint({
    required List<MacdPoint>? points,
    required int? selectedVisibleIndex,
  }) {
    if (points == null || points.isEmpty) {
      return null;
    }
    if (selectedVisibleIndex != null &&
        selectedVisibleIndex >= 0 &&
        selectedVisibleIndex < points.length) {
      return points[selectedVisibleIndex];
    }
    return points.last;
  }

  DateTime? _resolveActiveDate({
    required List<MacdPoint>? points,
    required int? selectedVisibleIndex,
  }) {
    if (points == null || points.isEmpty || widget.bars.isEmpty) {
      return null;
    }

    final start = widget.viewport.startIndex;
    final pointIndex = selectedVisibleIndex == null
        ? points.length - 1
        : selectedVisibleIndex.clamp(0, points.length - 1);
    final globalIndex = start + pointIndex;
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

  List<MacdPoint>? _resolveViewportPoints() {
    final series = _series;
    if (series == null || series.points.isEmpty || widget.bars.isEmpty) {
      return null;
    }

    final dateToPoint = <int, MacdPoint>{
      for (final point in series.points) _dateKey(point.datetime): point,
    };

    final total = widget.bars.length;
    final safeVisibleCount = widget.viewport.visibleCount.clamp(0, total);
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
    final visiblePoints = <MacdPoint>[];
    for (final bar in visibleBars) {
      final point = dateToPoint[_dateKey(bar.datetime)];
      if (point == null) {
        return null;
      }
      visiblePoints.add(point);
    }

    return visiblePoints;
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

class MacdSubChartPainter extends CustomPainter {
  const MacdSubChartPainter({
    required this.points,
    this.selectedVisibleIndex,
    this.selectionLineColor = const Color(0xB3000000),
    this.selectionLineWidth = 1.0,
    this.selectionDashLength = 4.0,
    this.selectionGapLength = 3.0,
    this.gridColor = const Color(0x1A9E9E9E),
    this.zeroLineColor = const Color(0x4D9E9E9E),
    this.difLineColor = Colors.orange,
    this.deaLineColor = Colors.lightBlue,
    this.sidePadding = 5,
    this.topPadding = 6,
    this.bottomPadding = 6,
  });

  final List<MacdPoint> points;
  final int? selectedVisibleIndex;
  final Color selectionLineColor;
  final double selectionLineWidth;
  final double selectionDashLength;
  final double selectionGapLength;
  final Color gridColor;
  final Color zeroLineColor;
  final Color difLineColor;
  final Color deaLineColor;
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
        math.min(point.hist, math.min(point.dif, point.dea)),
      );
      maxValue = math.max(
        maxValue,
        math.max(point.hist, math.max(point.dif, point.dea)),
      );
    }

    minValue = math.min(minValue, 0);
    maxValue = math.max(maxValue, 0);
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

    final zeroY = toY(0);
    final zeroLine = Paint()
      ..color = zeroLineColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(sidePadding, zeroY),
      Offset(size.width - sidePadding, zeroY),
      zeroLine,
    );

    final spacing = drawWidth / points.length;
    final barWidth = math.max(1.0, spacing * 0.56);

    final upPaint = Paint()..color = AppColors.stockUp.withValues(alpha: 0.88);
    final downPaint = Paint()
      ..color = AppColors.stockDown.withValues(alpha: 0.88);

    final difPath = Path();
    final deaPath = Path();

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final centerX = sidePadding + spacing * (i + 0.5);

      final histY = toY(point.hist);
      final rectTop = math.min(zeroY, histY);
      final rectBottom = math.max(zeroY, histY);
      final rect = Rect.fromLTRB(
        centerX - barWidth / 2,
        rectTop,
        centerX + barWidth / 2,
        rectBottom,
      );
      canvas.drawRect(rect, point.hist >= 0 ? upPaint : downPaint);

      final difY = toY(point.dif);
      final deaY = toY(point.dea);
      if (i == 0) {
        difPath.moveTo(centerX, difY);
        deaPath.moveTo(centerX, deaY);
      } else {
        difPath.lineTo(centerX, difY);
        deaPath.lineTo(centerX, deaY);
      }
    }

    final difPaint = Paint()
      ..color = difLineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final deaPaint = Paint()
      ..color = deaLineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(difPath, difPaint);
    canvas.drawPath(deaPath, deaPaint);

    if (selectedVisibleIndex != null &&
        selectedVisibleIndex! >= 0 &&
        selectedVisibleIndex! < points.length) {
      final selectedX = sidePadding + spacing * (selectedVisibleIndex! + 0.5);
      final dashPaint = Paint()
        ..color = selectionLineColor
        ..strokeWidth = selectionLineWidth;
      var y = topPadding;
      final bottom = size.height - bottomPadding;
      while (y < bottom) {
        final endY = (y + selectionDashLength).clamp(
          topPadding,
          bottom,
        );
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
  bool shouldRepaint(covariant MacdSubChartPainter oldDelegate) {
    return !listEquals(oldDelegate.points, points) ||
        oldDelegate.selectedVisibleIndex != selectedVisibleIndex ||
        oldDelegate.selectionLineColor != selectionLineColor ||
        oldDelegate.selectionLineWidth != selectionLineWidth ||
        oldDelegate.selectionDashLength != selectionDashLength ||
        oldDelegate.selectionGapLength != selectionGapLength ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.zeroLineColor != zeroLineColor ||
        oldDelegate.difLineColor != difLineColor ||
        oldDelegate.deaLineColor != deaLineColor ||
        oldDelegate.sidePadding != sidePadding ||
        oldDelegate.topPadding != topPadding ||
        oldDelegate.bottomPadding != bottomPadding;
  }
}
