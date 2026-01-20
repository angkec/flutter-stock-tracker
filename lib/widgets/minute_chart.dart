import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// 分时图颜色
const Color _priceLineColor = Colors.white;
const Color _avgLineColor = Color(0xFFFFD700); // 黄色均价线
const Color _upColor = Color(0xFFFF4444);   // 涨 - 红
const Color _downColor = Color(0xFF00AA00); // 跌 - 绿

/// 分时图组件
class MinuteChart extends StatelessWidget {
  final List<KLine> bars;
  final double preClose; // 昨收价
  final double height;

  const MinuteChart({
    super.key,
    required this.bars,
    required this.preClose,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('暂无分时数据')),
      );
    }

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _MinuteChartPainter(
              bars: bars,
              preClose: preClose,
            ),
          );
        },
      ),
    );
  }
}

class _MinuteChartPainter extends CustomPainter {
  final List<KLine> bars;
  final double preClose;

  _MinuteChartPainter({
    required this.bars,
    required this.preClose,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    const double topPadding = 10;
    const double bottomPadding = 20;
    const double sidePadding = 5;
    const double volumeRatio = 0.25;
    const double gapHeight = 8;

    final totalHeight = size.height - topPadding - bottomPadding;
    final priceHeight = totalHeight * (1 - volumeRatio) - gapHeight;
    final volumeHeight = totalHeight * volumeRatio;
    final chartWidth = size.width - sidePadding * 2;

    // 价格区域
    const priceTop = topPadding;
    final priceBottom = priceTop + priceHeight;

    // 量柱区域
    final volumeTop = priceBottom + gapHeight;
    final volumeBottom = volumeTop + volumeHeight;

    // 计算价格范围（基于昨收价对称）
    double minPrice = preClose;
    double maxPrice = preClose;
    double maxVolume = 0;

    for (final bar in bars) {
      if (bar.close < minPrice) minPrice = bar.close;
      if (bar.close > maxPrice) maxPrice = bar.close;
      if (bar.high < minPrice) minPrice = bar.high;
      if (bar.high > maxPrice) maxPrice = bar.high;
      if (bar.low < minPrice) minPrice = bar.low;
      if (bar.low > maxPrice) maxPrice = bar.low;
      if (bar.volume > maxVolume) maxVolume = bar.volume;
    }

    // 以昨收价为中心对称显示
    final maxDiff = [
      (maxPrice - preClose).abs(),
      (minPrice - preClose).abs(),
      preClose * 0.02, // 最小 2% 范围
    ].reduce((a, b) => a > b ? a : b);

    minPrice = preClose - maxDiff * 1.1;
    maxPrice = preClose + maxDiff * 1.1;
    final priceRange = maxPrice - minPrice;

    if (maxVolume == 0) maxVolume = 1;

    // 每根柱子宽度
    final barWidth = chartWidth / 240; // 240 分钟

    // 价格转 Y 坐标
    double priceToY(double price) {
      return priceTop + (1 - (price - minPrice) / priceRange) * priceHeight;
    }

    // 成交量转高度
    double volumeToHeight(double volume) {
      return (volume / maxVolume) * volumeHeight;
    }

    // 绘制昨收价虚线
    final preCloseY = priceToY(preClose);
    final dashPaint = Paint()
      ..color = Colors.grey
      ..strokeWidth = 1;

    const dashWidth = 5.0;
    const dashSpace = 3.0;
    var startX = sidePadding;
    while (startX < size.width - sidePadding) {
      canvas.drawLine(
        Offset(startX, preCloseY),
        Offset(startX + dashWidth, preCloseY),
        dashPaint,
      );
      startX += dashWidth + dashSpace;
    }

    // 计算均价数据
    final avgPrices = <double>[];
    double cumAmount = 0;
    double cumVolume = 0;
    for (final bar in bars) {
      cumAmount += bar.amount;
      cumVolume += bar.volume;
      avgPrices.add(cumVolume > 0 ? cumAmount / cumVolume : bar.close);
    }

    // 绘制价格线
    final pricePath = Path();
    final avgPath = Path();

    for (var i = 0; i < bars.length; i++) {
      final x = sidePadding + (i + 0.5) * barWidth;
      final priceY = priceToY(bars[i].close);
      final avgY = priceToY(avgPrices[i]);

      if (i == 0) {
        pricePath.moveTo(x, priceY);
        avgPath.moveTo(x, avgY);
      } else {
        pricePath.lineTo(x, priceY);
        avgPath.lineTo(x, avgY);
      }
    }

    // 绘制均价线（黄色）
    final avgPaint = Paint()
      ..color = _avgLineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(avgPath, avgPaint);

    // 绘制价格线（白色）
    final pricePaint = Paint()
      ..color = _priceLineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(pricePath, pricePaint);

    // 绘制成交量柱
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final x = sidePadding + i * barWidth;
      final volHeight = volumeToHeight(bar.volume.toDouble());
      final isUp = bar.close >= preClose;

      final paint = Paint()
        ..color = isUp ? _upColor : _downColor
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(
          x,
          volumeBottom - volHeight,
          barWidth * 0.8,
          volHeight.clamp(0.5, double.infinity),
        ),
        paint,
      );
    }

    // 绘制时间标签
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final times = ['09:30', '10:30', '11:30', '14:00', '15:00'];
    final positions = [0.0, 60.0, 120.0, 180.0, 240.0]; // 分钟位置

    for (var i = 0; i < times.length; i++) {
      final x = sidePadding + positions[i] * barWidth;
      textPainter.text = TextSpan(
        text: times[i],
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      );
      textPainter.layout();

      var offsetX = x - textPainter.width / 2;
      if (i == 0) offsetX = sidePadding;
      if (i == times.length - 1) offsetX = size.width - sidePadding - textPainter.width;

      textPainter.paint(
        canvas,
        Offset(offsetX, size.height - bottomPadding + 3),
      );
    }

    // 绘制涨跌幅标签
    final upPercent = ((maxPrice - preClose) / preClose * 100).toStringAsFixed(2);
    final downPercent = ((minPrice - preClose) / preClose * 100).toStringAsFixed(2);

    textPainter.text = TextSpan(
      text: '+$upPercent%',
      style: const TextStyle(color: _upColor, fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - sidePadding - textPainter.width, priceTop));

    textPainter.text = TextSpan(
      text: '$downPercent%',
      style: const TextStyle(color: _downColor, fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - sidePadding - textPainter.width, priceBottom - 12));
  }

  @override
  bool shouldRepaint(covariant _MinuteChartPainter oldDelegate) {
    return oldDelegate.bars != bars || oldDelegate.preClose != preClose;
  }
}
