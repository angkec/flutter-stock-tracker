import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// K 线图颜色
const Color kUpColor = Color(0xFFFF4444);   // 涨 - 红
const Color kDownColor = Color(0xFF00AA00); // 跌 - 绿

/// K 线图组件
class KLineChart extends StatelessWidget {
  final List<KLine> bars;
  final double height;

  const KLineChart({
    super.key,
    required this.bars,
    this.height = 220,
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
    const double bottomPadding = 25; // 留空间给日期
    const double sidePadding = 5;

    final chartHeight = size.height - topPadding - bottomPadding;
    final chartWidth = size.width - sidePadding * 2;

    // 计算价格范围
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;
    for (final bar in bars) {
      if (bar.low < minPrice) minPrice = bar.low;
      if (bar.high > maxPrice) maxPrice = bar.high;
    }

    // 上下留 5% 边距
    final priceRange = maxPrice - minPrice;
    final margin = priceRange * 0.05;
    minPrice -= margin;
    maxPrice += margin;
    var adjustedRange = maxPrice - minPrice;
    if (adjustedRange == 0) adjustedRange = 1.0;

    // K 线宽度
    final barWidth = chartWidth / bars.length * 0.8;
    final barSpacing = chartWidth / bars.length;

    // 价格转 Y 坐标（Y 轴反转）
    double priceToY(double price) {
      return topPadding + (1 - (price - minPrice) / adjustedRange) * chartHeight;
    }

    // Create Paint objects once before the loop
    final upPaint = Paint()
      ..color = kUpColor
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;
    final downPaint = Paint()
      ..color = kDownColor
      ..strokeWidth = 1
      ..style = PaintingStyle.fill;

    // 绘制每根 K 线
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final x = sidePadding + i * barSpacing + barSpacing / 2;

      final openY = priceToY(bar.open);
      final closeY = priceToY(bar.close);
      final highY = priceToY(bar.high);
      final lowY = priceToY(bar.low);

      final paint = bar.close >= bar.open ? upPaint : downPaint;

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
    }

    // 绘制底部日期（每隔几根显示一个）
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final interval = (bars.length / 5).ceil(); // 大约显示 5 个日期

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
        Offset(x - textPainter.width / 2, size.height - bottomPadding + 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _KLinePainter oldDelegate) {
    return oldDelegate.bars != bars;
  }
}
