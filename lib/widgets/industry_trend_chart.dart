import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';

/// 行业趋势图组件
///
/// 显示行业量比占比的历史趋势，包括：
/// - 折线图展示 ratioAbovePercent 随时间的变化
/// - 50% 参考线
/// - 最后一个数据点高亮显示及数值标签
/// - X 轴显示首尾日期标签
class IndustryTrendChart extends StatelessWidget {
  /// 趋势数据点列表
  final List<DailyRatioPoint> data;

  /// 图表高度
  final double height;

  /// 主线条颜色（可选，默认使用主题色）
  final Color? lineColor;

  /// 网格线颜色（可选，默认使用主题色）
  final Color? gridColor;

  const IndustryTrendChart({
    super.key,
    required this.data,
    this.height = 150,
    this.lineColor,
    this.gridColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveLineColor = lineColor ?? theme.colorScheme.primary;
    final effectiveGridColor = gridColor ?? theme.colorScheme.outlineVariant;

    if (data.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '暂无趋势数据',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _IndustryTrendPainter(
          data: data,
          lineColor: effectiveLineColor,
          gridColor: effectiveGridColor,
        ),
      ),
    );
  }
}

/// 行业趋势图绘制器
class _IndustryTrendPainter extends CustomPainter {
  final List<DailyRatioPoint> data;
  final Color lineColor;
  final Color gridColor;

  _IndustryTrendPainter({
    required this.data,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // 定义绘图区域，为日期标签留出底部空间
    const padding = EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 28);
    final chartArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );

    // 提取 ratioAbovePercent 数值
    final values = data.map((p) => p.ratioAbovePercent).toList();

    // 计算数据范围
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;

    // 调整范围以提供更好的视觉效果
    final adjustedMin = range > 0 ? minValue - range * 0.1 : minValue - 5;
    final adjustedMax = range > 0 ? maxValue + range * 0.1 : maxValue + 5;
    final adjustedRange = adjustedMax - adjustedMin;

    // 绘制 50% 参考线
    _drawReferenceLine(canvas, chartArea, adjustedMin, adjustedRange);

    // 绘制趋势线
    _drawTrendLine(canvas, chartArea, values, adjustedMin, adjustedRange);

    // 绘制最后一个数据点和标签
    _drawLastPoint(canvas, chartArea, values, adjustedMin, adjustedRange);

    // 绘制日期标签
    _drawDateLabels(canvas, chartArea, size);
  }

  /// 绘制 50% 参考线
  void _drawReferenceLine(
    Canvas canvas,
    Rect chartArea,
    double adjustedMin,
    double adjustedRange,
  ) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final y50 = chartArea.bottom -
        ((50 - adjustedMin) / adjustedRange) * chartArea.height;

    if (y50 >= chartArea.top && y50 <= chartArea.bottom) {
      // 绘制虚线
      const dashWidth = 4.0;
      const dashSpace = 3.0;
      var startX = chartArea.left;
      while (startX < chartArea.right) {
        canvas.drawLine(
          Offset(startX, y50),
          Offset((startX + dashWidth).clamp(chartArea.left, chartArea.right), y50),
          gridPaint,
        );
        startX += dashWidth + dashSpace;
      }

      // 绘制 50% 标签
      final textPainter = TextPainter(
        text: TextSpan(
          text: '50%',
          style: TextStyle(color: gridColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(chartArea.left, y50 - textPainter.height - 2),
      );
    }
  }

  /// 绘制趋势折线
  void _drawTrendLine(
    Canvas canvas,
    Rect chartArea,
    List<double> values,
    double adjustedMin,
    double adjustedRange,
  ) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final divisor = values.length > 1 ? values.length - 1 : 1;

    for (var i = 0; i < values.length; i++) {
      final x = chartArea.left + (i / divisor) * chartArea.width;
      final y = chartArea.bottom -
          ((values[i] - adjustedMin) / adjustedRange) * chartArea.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);
  }

  /// 绘制最后一个数据点和数值标签
  void _drawLastPoint(
    Canvas canvas,
    Rect chartArea,
    List<double> values,
    double adjustedMin,
    double adjustedRange,
  ) {
    final lastX = chartArea.right;
    final lastY = chartArea.bottom -
        ((values.last - adjustedMin) / adjustedRange) * chartArea.height;

    // 绘制高亮圆点
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 4, dotPaint);

    // 绘制数值标签
    final valuePainter = TextPainter(
      text: TextSpan(
        text: '${values.last.toStringAsFixed(0)}%',
        style: TextStyle(
          color: lineColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    valuePainter.layout();
    valuePainter.paint(
      canvas,
      Offset(lastX - valuePainter.width - 8, lastY - valuePainter.height / 2),
    );
  }

  /// 格式化日期为 MM/dd 格式
  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  /// 绘制日期标签（首尾日期）
  void _drawDateLabels(Canvas canvas, Rect chartArea, Size size) {
    if (data.isEmpty) return;

    final textStyle = TextStyle(color: gridColor, fontSize: 10);

    // 绘制第一个日期
    final firstDatePainter = TextPainter(
      text: TextSpan(
        text: _formatDate(data.first.date),
        style: textStyle,
      ),
      textDirection: TextDirection.ltr,
    );
    firstDatePainter.layout();
    firstDatePainter.paint(
      canvas,
      Offset(chartArea.left, chartArea.bottom + 4),
    );

    // 绘制最后一个日期（如果数据点大于1）
    if (data.length > 1) {
      final lastDatePainter = TextPainter(
        text: TextSpan(
          text: _formatDate(data.last.date),
          style: textStyle,
        ),
        textDirection: TextDirection.ltr,
      );
      lastDatePainter.layout();
      lastDatePainter.paint(
        canvas,
        Offset(chartArea.right - lastDatePainter.width, chartArea.bottom + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IndustryTrendPainter oldDelegate) {
    return data != oldDelegate.data ||
        lineColor != oldDelegate.lineColor ||
        gridColor != oldDelegate.gridColor;
  }
}
