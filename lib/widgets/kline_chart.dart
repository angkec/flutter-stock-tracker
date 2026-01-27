import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/theme/theme.dart';

/// K 线图颜色 - use theme colors
const Color kUpColor = AppColors.stockUp;   // 涨 - 红
const Color kDownColor = AppColors.stockDown; // 跌 - 绿

/// K 线图组件（含成交量，支持触摸选择）
class KLineChart extends StatefulWidget {
  final List<KLine> bars;
  final List<DailyRatio>? ratios; // 量比数据，用于显示选中日期的量比
  final double height;
  final Set<int>? markedIndices; // 需要标记的K线索引（如突破日）
  final Map<int, int>? nearMissIndices; // 近似命中的K线索引及失败条件数
  final BreakoutDetectionResult? Function(int index)? getDetectionResult; // 获取检测结果的回调
  final ValueChanged<bool>? onScaling; // 缩放状态变化回调（true=开始缩放，false=结束缩放）

  const KLineChart({
    super.key,
    required this.bars,
    this.ratios,
    this.height = 280,
    this.markedIndices,
    this.nearMissIndices,
    this.getDetectionResult,
    this.onScaling,
  });

  @override
  State<KLineChart> createState() => _KLineChartState();
}


class _KLineChartState extends State<KLineChart> {
  int? _selectedIndex;

  // 缩放相关状态
  late int _visibleCount; // 可见K线数量
  late int _startIndex;   // 起始索引

  // 双指缩放追踪
  final Map<int, Offset> _pointers = {};
  double? _initialPinchDistance;
  int _initialVisibleCount = 30;

  // 缩放范围
  static const int _minVisibleCount = 10;
  static const int _maxVisibleCount = 120;

  @override
  void initState() {
    super.initState();
    _resetZoom();
  }

  @override
  void didUpdateWidget(KLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bars.length != widget.bars.length) {
      _resetZoom();
    }
  }

  void _resetZoom() {
    // 默认显示30根K线
    const defaultVisibleCount = 30;
    _visibleCount = defaultVisibleCount.clamp(_minVisibleCount, _maxVisibleCount);
    // 默认显示最新的K线（右对齐）
    _startIndex = (widget.bars.length - _visibleCount).clamp(0, widget.bars.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bars.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Text('暂无数据')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 选中信息显示
        _buildSelectedInfo(),
        // K线图（使用 Stack 叠加检测结果）
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final crosshairColor = isDark ? Colors.white : Colors.black;
              // 计算可见的K线数据
              final endIndex = (_startIndex + _visibleCount).clamp(0, widget.bars.length);
              final visibleBars = widget.bars.sublist(_startIndex, endIndex);

              // 调整 markedIndices 为可见范围内的索引
              Set<int>? visibleMarkedIndices;
              if (widget.markedIndices != null) {
                visibleMarkedIndices = widget.markedIndices!
                    .where((i) => i >= _startIndex && i < endIndex)
                    .map((i) => i - _startIndex)
                    .toSet();
              }

              // 调整 nearMissIndices 为可见范围内的索引
              Map<int, int>? visibleNearMissIndices;
              if (widget.nearMissIndices != null) {
                visibleNearMissIndices = {};
                for (final entry in widget.nearMissIndices!.entries) {
                  if (entry.key >= _startIndex && entry.key < endIndex) {
                    visibleNearMissIndices[entry.key - _startIndex] = entry.value;
                  }
                }
              }

              // 调整 selectedIndex 为可见范围内的索引
              int? visibleSelectedIndex;
              if (_selectedIndex != null &&
                  _selectedIndex! >= _startIndex &&
                  _selectedIndex! < endIndex) {
                visibleSelectedIndex = _selectedIndex! - _startIndex;
              }

              // 判断是否可以滚动
              final canScrollLeft = _startIndex > 0;
              final canScrollRight = _startIndex + _visibleCount < widget.bars.length;
              final isZoomed = _visibleCount < widget.bars.length;

              return Stack(
                children: [
                  Listener(
                    onPointerDown: (event) => _onPointerDown(event),
                    onPointerMove: (event) => _onPointerMove(event),
                    onPointerUp: (event) => _onPointerUp(event),
                    onPointerCancel: (event) => _onPointerUp(event),
                    child: GestureDetector(
                      // 使用长按手势来选择K线，避免与外层页面滑动冲突
                      onLongPressStart: (details) => _handleTouch(details.localPosition, constraints.maxWidth),
                      onLongPressMoveUpdate: (details) => _handleTouch(details.localPosition, constraints.maxWidth),
                      onLongPressEnd: (_) => _clearSelection(),
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, widget.height),
                        painter: _KLinePainter(
                          bars: visibleBars,
                          ratios: widget.ratios,
                          selectedIndex: visibleSelectedIndex,
                          markedIndices: visibleMarkedIndices,
                          nearMissIndices: visibleNearMissIndices,
                          crosshairColor: crosshairColor,
                          startIndex: _startIndex, // 传递起始索引用于日期匹配
                        ),
                      ),
                    ),
                  ),
                  // 检测结果浮层
                  _buildDetectionOverlay(),
                  // 左侧滚动按钮
                  if (isZoomed && canScrollLeft)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 20,
                      child: GestureDetector(
                        onTap: () => _scrollLeft(),
                        onLongPress: () => _scrollLeft(fast: true),
                        child: Container(
                          width: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.chevron_left,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 右侧滚动按钮
                  if (isZoomed && canScrollRight)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 20,
                      child: GestureDetector(
                        onTap: () => _scrollRight(),
                        onLongPress: () => _scrollRight(fast: true),
                        child: Container(
                          width: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.chevron_right,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleTouch(Offset position, double chartWidth) {
    const sidePadding = 5.0;
    const edgeThreshold = 40.0; // 边缘触发滚动的阈值
    final effectiveWidth = chartWidth - sidePadding * 2;
    final visibleCount = _visibleCount.clamp(1, widget.bars.length);
    final barSpacing = effectiveWidth / visibleCount;

    // 检测是否在边缘区域，如果是则滚动
    if (position.dx < edgeThreshold && _startIndex > 0) {
      // 在左边缘，向左滚动
      setState(() {
        _startIndex = (_startIndex - 1).clamp(0, widget.bars.length - _visibleCount);
        _selectedIndex = _startIndex;
      });
      return;
    } else if (position.dx > chartWidth - edgeThreshold &&
               _startIndex + _visibleCount < widget.bars.length) {
      // 在右边缘，向右滚动
      setState(() {
        _startIndex = (_startIndex + 1).clamp(0, widget.bars.length - _visibleCount);
        _selectedIndex = _startIndex + _visibleCount - 1;
      });
      return;
    }

    // 计算触摸位置对应的K线索引（相对于可见范围）
    final x = position.dx - sidePadding;
    var visibleIndex = (x / barSpacing).floor();
    visibleIndex = visibleIndex.clamp(0, visibleCount - 1);

    // 转换为实际索引
    final actualIndex = _startIndex + visibleIndex;
    if (actualIndex != _selectedIndex && actualIndex < widget.bars.length) {
      setState(() => _selectedIndex = actualIndex);
    }
  }

  // 双指缩放：追踪触点
  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      // 开始双指操作，记录初始距离
      final positions = _pointers.values.toList();
      _initialPinchDistance = (positions[0] - positions[1]).distance;
      _initialVisibleCount = _visibleCount;
      // 通知父组件开始缩放
      widget.onScaling?.call(true);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_pointers.length == 2 && _initialPinchDistance != null) {
      // 计算当前双指距离
      final positions = _pointers.values.toList();
      final currentDistance = (positions[0] - positions[1]).distance;

      // 计算缩放比例
      final scale = currentDistance / _initialPinchDistance!;

      // 计算新的可见数量（放大手势 = 减少可见数量）
      final newVisibleCount = (_initialVisibleCount / scale)
          .round()
          .clamp(_minVisibleCount, _maxVisibleCount);

      if (newVisibleCount != _visibleCount) {
        setState(() {
          // 保持缩放中心点
          final centerIndex = _startIndex + _visibleCount ~/ 2;
          _visibleCount = newVisibleCount;
          _startIndex = (centerIndex - _visibleCount ~/ 2)
              .clamp(0, widget.bars.length - _visibleCount);
        });
      }
    }
  }

  void _onPointerUp(PointerEvent event) {
    final wasScaling = _pointers.length >= 2;
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _initialPinchDistance = null;
      // 通知父组件结束缩放
      if (wasScaling) {
        widget.onScaling?.call(false);
      }
    }
  }

  // 向左滚动（查看更早的数据）
  void _scrollLeft({bool fast = false}) {
    final scrollAmount = fast ? _visibleCount ~/ 2 : _visibleCount ~/ 4;
    setState(() {
      _startIndex = (_startIndex - scrollAmount).clamp(0, widget.bars.length - _visibleCount);
    });
  }

  // 向右滚动（查看更新的数据）
  void _scrollRight({bool fast = false}) {
    final scrollAmount = fast ? _visibleCount ~/ 2 : _visibleCount ~/ 4;
    setState(() {
      _startIndex = (_startIndex + scrollAmount).clamp(0, widget.bars.length - _visibleCount);
    });
  }

  void _clearSelection() {
    if (_selectedIndex != null) {
      setState(() => _selectedIndex = null);
    }
  }

  Widget _buildSelectedInfo() {
    if (_selectedIndex == null || _selectedIndex! >= widget.bars.length) {
      return const SizedBox(height: 24);
    }

    final bar = widget.bars[_selectedIndex!];
    final dateStr = '${bar.datetime.year}/${bar.datetime.month}/${bar.datetime.day}';

    // 查找对应日期的量比
    double? ratio;
    if (widget.ratios != null) {
      for (final r in widget.ratios!) {
        if (r.date.year == bar.datetime.year &&
            r.date.month == bar.datetime.month &&
            r.date.day == bar.datetime.day) {
          ratio = r.ratio;
          break;
        }
      }
    }

    final changePercent = ((bar.close - bar.open) / bar.open * 100);
    final isUp = bar.close >= bar.open;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            dateStr,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Text(
            '收: ${bar.close.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12,
              color: isUp ? kUpColor : kDownColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isUp ? "+" : ""}${changePercent.toStringAsFixed(2)}%',
            style: TextStyle(
              fontSize: 12,
              color: isUp ? kUpColor : kDownColor,
            ),
          ),
          if (ratio != null) ...[
            const SizedBox(width: 12),
            Text(
              '量比: ${ratio.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: ratio >= 1.0 ? kUpColor : kDownColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建检测结果显示（显示在K线图左上角）
  Widget _buildDetectionOverlay() {
    if (_selectedIndex == null || widget.getDetectionResult == null) {
      return const SizedBox.shrink();
    }

    final result = widget.getDetectionResult!(_selectedIndex!);
    if (result == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 8,
      top: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 突破日条件标题
            Text(
              '突破日检测 ${result.breakoutPassed ? "✓" : "✗"}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: result.breakoutPassed ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 4),
            // 突破日各项检测
            ...result.allItems.map((item) => _buildDetectionItem(item)),
            // 回踩阶段检测
            if (result.pullbackResult != null) ...[
              const SizedBox(height: 6),
              Text(
                '回踩检测 (${result.pullbackResult!.pullbackDays}天) ${result.pullbackResult!.passed ? "✓" : "✗"}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: result.pullbackResult!.passed ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 4),
              ...result.pullbackResult!.allItems.map((item) => _buildDetectionItem(item)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionItem(DetectionItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.passed ? Icons.check_circle : Icons.cancel,
            size: 12,
            color: item.passed ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 4),
          Text(
            item.name,
            style: const TextStyle(fontSize: 10),
          ),
          if (item.detail != null) ...[
            const SizedBox(width: 4),
            Text(
              item.detail!,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KLinePainter extends CustomPainter {
  final List<KLine> bars;
  final List<DailyRatio>? ratios;
  final int? selectedIndex;
  final Set<int>? markedIndices;
  final Map<int, int>? nearMissIndices; // 近似命中的索引及失败条件数
  final Color crosshairColor;
  final int startIndex; // 可见范围的起始索引（用于日期匹配）

  _KLinePainter({
    required this.bars,
    this.ratios,
    this.selectedIndex,
    this.markedIndices,
    this.nearMissIndices,
    this.crosshairColor = Colors.white,
    this.startIndex = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    const double topPadding = 10;
    const double bottomPadding = 20; // 日期标签
    const double sidePadding = 5;
    const double volumeRatio = 0.20; // 量柱占总高度的比例
    const double ratioBarRatio = 0.10; // 量比柱占总高度的比例
    const double gapHeight = 6; // 各区域之间的间隔

    final totalHeight = size.height - topPadding - bottomPadding;
    final klineHeight = totalHeight * (1 - volumeRatio - ratioBarRatio) - gapHeight * 2;
    final volumeHeight = totalHeight * volumeRatio;
    final ratioBarHeight = totalHeight * ratioBarRatio;
    final chartWidth = size.width - sidePadding * 2;

    // K线区域
    const klineTop = topPadding;
    final klineBottom = klineTop + klineHeight;

    // 量柱区域
    final volumeTop = klineBottom + gapHeight;
    final volumeBottom = volumeTop + volumeHeight;

    // 量比柱区域
    final ratioTop = volumeBottom + gapHeight;
    final ratioBottom = ratioTop + ratioBarHeight;

    // 计算价格范围
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;
    double maxVolume = 0;

    for (final bar in bars) {
      if (bar.low < minPrice) minPrice = bar.low;
      if (bar.high > maxPrice) maxPrice = bar.high;
      if (bar.volume > maxVolume) maxVolume = bar.volume;
    }

    // 价格上下留 5% 边距
    final priceRange = maxPrice - minPrice;
    final priceMargin = priceRange * 0.05;
    minPrice -= priceMargin;
    maxPrice += priceMargin;
    var adjustedPriceRange = maxPrice - minPrice;
    if (adjustedPriceRange == 0) adjustedPriceRange = 1.0;

    // 成交量留 10% 顶部边距
    if (maxVolume == 0) maxVolume = 1;
    final volumeMargin = maxVolume * 0.1;
    maxVolume += volumeMargin;

    // 构建日期到量比的映射
    final ratioMap = <String, double>{};
    double maxRatio = 2.0; // 最小量比范围为 0-2
    if (ratios != null) {
      for (final r in ratios!) {
        if (r.ratio != null) {
          final key = '${r.date.year}-${r.date.month}-${r.date.day}';
          ratioMap[key] = r.ratio!;
          if (r.ratio! > maxRatio) maxRatio = r.ratio!;
        }
      }
    }
    // 量比上限留 10% 边距
    maxRatio *= 1.1;

    // K 线宽度
    final barWidth = chartWidth / bars.length * 0.8;
    final barSpacing = chartWidth / bars.length;

    // 价格转 Y 坐标
    double priceToY(double price) {
      return klineTop + (1 - (price - minPrice) / adjustedPriceRange) * klineHeight;
    }

    // 成交量转高度
    double volumeToHeight(double volume) {
      return (volume / maxVolume) * volumeHeight;
    }

    // Paint objects (wick strokeWidth: 0.8)
    final upPaint = Paint()
      ..color = kUpColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.fill;
    final downPaint = Paint()
      ..color = kDownColor
      ..strokeWidth = 0.8
      ..style = PaintingStyle.fill;

    // Paint objects for volume bars (80% opacity)
    final upVolumePaint = Paint()
      ..color = kUpColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    final downVolumePaint = Paint()
      ..color = kDownColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    // Draw horizontal grid lines (10% opacity)
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..strokeWidth = 0.5;

    const gridLines = 4;
    for (int i = 1; i < gridLines; i++) {
      final y = klineTop + klineHeight * i / gridLines;
      canvas.drawLine(Offset(sidePadding, y), Offset(size.width - sidePadding, y), gridPaint);
    }

    // 绘制量比区域的基准线 (ratio = 1.0)
    final ratioBaseY = ratioBottom - (1.0 / maxRatio) * ratioBarHeight;
    final ratioBasePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(sidePadding, ratioBaseY),
      Offset(size.width - sidePadding, ratioBaseY),
      ratioBasePaint,
    );

    // 绘制选中线（虚线）
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < bars.length) {
      final x = sidePadding + selectedIndex! * barSpacing + barSpacing / 2;
      final crosshairPaint = Paint()
        ..color = crosshairColor.withValues(alpha: 0.7)
        ..strokeWidth = 1;

      // 绘制虚线
      const dashHeight = 4.0;
      const dashGap = 3.0;
      var y = topPadding;
      while (y < size.height - bottomPadding) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, (y + dashHeight).clamp(0, size.height - bottomPadding)),
          crosshairPaint,
        );
        y += dashHeight + dashGap;
      }
    }

    // 绘制每根 K 线和量柱
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final x = sidePadding + i * barSpacing + barSpacing / 2;
      final isSelected = i == selectedIndex;

      // 选中的K线使用更亮的颜色
      Paint paint;
      if (isSelected) {
        paint = Paint()
          ..color = bar.close >= bar.open
              ? kUpColor.withValues(alpha: 1.0)
              : kDownColor.withValues(alpha: 1.0)
          ..strokeWidth = 2
          ..style = PaintingStyle.fill;
      } else {
        paint = bar.close >= bar.open ? upPaint : downPaint;
      }

      // === K线 ===
      final openY = priceToY(bar.open);
      final closeY = priceToY(bar.close);
      final highY = priceToY(bar.high);
      final lowY = priceToY(bar.low);

      // 绘制影线
      canvas.drawLine(Offset(x, highY), Offset(x, lowY), paint);

      // 绘制实体
      final bodyTop = openY < closeY ? openY : closeY;
      final bodyBottom = openY > closeY ? openY : closeY;
      final bodyHeight = (bodyBottom - bodyTop).clamp(1.0, double.infinity);

      final currentBarWidth = isSelected ? barWidth * 1.2 : barWidth;

      canvas.drawRect(
        Rect.fromLTWH(x - currentBarWidth / 2, bodyTop, currentBarWidth, bodyHeight),
        paint,
      );

      // === 量柱 (80% opacity) ===
      final volHeight = volumeToHeight(bar.volume.toDouble());
      final volumePaint = isSelected
          ? (bar.close >= bar.open ? upVolumePaint : downVolumePaint)
          : (bar.close >= bar.open ? upVolumePaint : downVolumePaint);
      canvas.drawRect(
        Rect.fromLTWH(
          x - currentBarWidth / 2,
          volumeBottom - volHeight,
          currentBarWidth,
          volHeight.clamp(1.0, double.infinity),
        ),
        volumePaint,
      );

      // === 突破日标记 ===
      if (markedIndices != null && markedIndices!.contains(i)) {
        final markerPaint = Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.fill;

        // 在K线上方画一个小三角形
        final markerY = highY - 6;
        final path = Path()
          ..moveTo(x, markerY)
          ..lineTo(x - 4, markerY - 6)
          ..lineTo(x + 4, markerY - 6)
          ..close();
        canvas.drawPath(path, markerPaint);
      }
      // === 近似命中标记 ===
      else if (nearMissIndices != null && nearMissIndices!.containsKey(i)) {
        final failedCount = nearMissIndices![i]!;
        final markerPaint = Paint()
          ..color = Colors.orange.withValues(alpha: 0.4) // 浅色
          ..style = PaintingStyle.fill;

        // 在K线上方画一个浅色小三角形
        final markerY = highY - 6;
        final path = Path()
          ..moveTo(x, markerY)
          ..lineTo(x - 4, markerY - 6)
          ..lineTo(x + 4, markerY - 6)
          ..close();
        canvas.drawPath(path, markerPaint);

        // 在三角形内显示差几条（失败条件数）
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$failedCount',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, markerY - 5 - textPainter.height / 2),
        );
      }

      // === 量比柱 ===
      final dateKey = '${bar.datetime.year}-${bar.datetime.month}-${bar.datetime.day}';
      final ratio = ratioMap[dateKey];
      if (ratio != null) {
        final ratioHeight = (ratio / maxRatio) * ratioBarHeight;
        final ratioPaint = Paint()
          ..color = ratio >= 1.0
              ? kUpColor.withValues(alpha: 0.7)
              : kDownColor.withValues(alpha: 0.7)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(
            x - currentBarWidth / 2,
            ratioBottom - ratioHeight,
            currentBarWidth,
            ratioHeight.clamp(1.0, double.infinity),
          ),
          ratioPaint,
        );
      }
    }

    // 绘制底部日期
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final interval = (bars.length / 5).ceil();

    for (var i = 0; i < bars.length; i += interval) {
      final bar = bars[i];
      final x = sidePadding + i * barSpacing + barSpacing / 2;
      final dateStr = '${bar.datetime.month}/${bar.datetime.day}';

      textPainter.text = TextSpan(
        text: dateStr,
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - bottomPadding + 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KLinePainter oldDelegate) {
    return oldDelegate.bars != bars ||
           oldDelegate.ratios != ratios ||
           oldDelegate.selectedIndex != selectedIndex ||
           oldDelegate.markedIndices != markedIndices ||
           oldDelegate.nearMissIndices != nearMissIndices ||
           oldDelegate.crosshairColor != crosshairColor ||
           oldDelegate.startIndex != startIndex;
  }
}
