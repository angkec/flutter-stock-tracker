import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// K 线图颜色
const Color kUpColor = Color(0xFFFF4444);   // 涨 - 红
const Color kDownColor = Color(0xFF00AA00); // 跌 - 绿

/// K 线图组件（含成交量）
class KLineChart extends StatelessWidget {
  final List<KLine> bars;
  final double height;

  const KLineChart({
    super.key,
    required this.bars,
    this.height = 280, // 增加高度以容纳量柱
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('暂无数据')),
      );
    }

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _KLinePainter(bars: bars),
          );
        },
      ),
    );
  }
}

class _KLinePainter extends CustomPainter {
  final List<KLine> bars;

  _KLinePainter({required this.bars});

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

    // Paint objects
    final upPaint = Paint()
      ..color = kUpColor
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;
    final downPaint = Paint()
      ..color = kDownColor
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    // 绘制每根 K 线和量柱
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final x = sidePadding + i * barSpacing + barSpacing / 2;
      final paint = bar.close >= bar.open ? upPaint : downPaint;

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

      canvas.drawRect(
        Rect.fromLTWH(x - barWidth / 2, bodyTop, barWidth, bodyHeight),
        paint,
      );

      // === 量柱 ===
      final volHeight = volumeToHeight(bar.volume.toDouble());
      canvas.drawRect(
        Rect.fromLTWH(
          x - barWidth / 2,
          volumeBottom - volHeight,
          barWidth,
          volHeight.clamp(1.0, double.infinity),
        ),
        paint,
      );
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
    return oldDelegate.bars != bars;
  }
}
