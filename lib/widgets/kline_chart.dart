import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
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

  const KLineChart({
    super.key,
    required this.bars,
    this.ratios,
    this.height = 280,
    this.markedIndices,
  });

  @override
  State<KLineChart> createState() => _KLineChartState();
}

class _KLineChartState extends State<KLineChart> {
  int? _selectedIndex;

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
        // K线图
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onHorizontalDragStart: (details) => _handleTouch(details.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (details) => _handleTouch(details.localPosition, constraints.maxWidth),
                onHorizontalDragEnd: (_) => _clearSelection(),
                onTapDown: (details) => _handleTouch(details.localPosition, constraints.maxWidth),
                onTapUp: (_) => _clearSelection(),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.height),
                  painter: _KLinePainter(
                    bars: widget.bars,
                    selectedIndex: _selectedIndex,
                    markedIndices: widget.markedIndices,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleTouch(Offset position, double chartWidth) {
    const sidePadding = 5.0;
    final effectiveWidth = chartWidth - sidePadding * 2;
    final barSpacing = effectiveWidth / widget.bars.length;

    // 计算触摸位置对应的K线索引
    final x = position.dx - sidePadding;
    var index = (x / barSpacing).floor();
    index = index.clamp(0, widget.bars.length - 1);

    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
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
}

class _KLinePainter extends CustomPainter {
  final List<KLine> bars;
  final int? selectedIndex;
  final Set<int>? markedIndices;

  _KLinePainter({required this.bars, this.selectedIndex, this.markedIndices});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    const double topPadding = 10;
    const double bottomPadding = 20; // 日期标签
    const double sidePadding = 5;
    const double volumeRatio = 0.25; // 量柱占总高度的比例
    const double gapHeight = 8; // K线和量柱之间的间隔

    final totalHeight = size.height - topPadding - bottomPadding;
    final klineHeight = totalHeight * (1 - volumeRatio) - gapHeight;
    final volumeHeight = totalHeight * volumeRatio;
    final chartWidth = size.width - sidePadding * 2;

    // K线区域
    const klineTop = topPadding;
    final klineBottom = klineTop + klineHeight;

    // 量柱区域
    final volumeTop = klineBottom + gapHeight;
    final volumeBottom = volumeTop + volumeHeight;

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

    // 绘制选中线（如果有）
    if (selectedIndex != null && selectedIndex! >= 0 && selectedIndex! < bars.length) {
      final x = sidePadding + selectedIndex! * barSpacing + barSpacing / 2;
      final crosshairPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(x, topPadding),
        Offset(x, size.height - bottomPadding),
        crosshairPaint,
      );
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
           oldDelegate.selectedIndex != selectedIndex ||
           oldDelegate.markedIndices != markedIndices;
  }
}
