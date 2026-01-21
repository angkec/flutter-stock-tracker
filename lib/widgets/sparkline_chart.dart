import 'package:flutter/material.dart';

/// 默认颜色常量
const Color _kUpColor = Color(0xFFFF4444); // 涨 - 红
const Color _kDownColor = Color(0xFF00AA00); // 跌 - 绿
const Color _kFlatColor = Colors.grey;

/// 迷你折线图组件，用于显示趋势
///
/// 根据首尾值的关系自动选择线条颜色：
/// - 最后值 > 第一个值：红色（上涨趋势）
/// - 最后值 < 第一个值：绿色（下跌趋势）
/// - 相等：灰色
class SparklineChart extends StatelessWidget {
  /// 要绘制的数据点列表
  final List<double> data;

  /// 图表宽度，默认为 60
  final double? width;

  /// 图表高度，默认为 20
  final double? height;

  /// 上涨趋势颜色
  final Color? upColor;

  /// 下跌趋势颜色
  final Color? downColor;

  /// 持平趋势颜色
  final Color? flatColor;

  /// 线条宽度
  final double strokeWidth;

  /// 参考线值（如 50 表示 50%），null 表示不显示
  final double? referenceValue;

  /// 参考线颜色
  final Color? referenceLineColor;

  const SparklineChart({
    super.key,
    required this.data,
    this.width,
    this.height,
    this.upColor,
    this.downColor,
    this.flatColor,
    this.strokeWidth = 1.5,
    this.referenceValue,
    this.referenceLineColor,
  });

  @override
  Widget build(BuildContext context) {
    final chartWidth = width ?? 60.0;
    final chartHeight = height ?? 20.0;

    if (data.isEmpty) {
      return SizedBox(width: chartWidth, height: chartHeight);
    }

    // 确定趋势颜色
    final Color lineColor;
    if (data.length < 2) {
      lineColor = flatColor ?? _kFlatColor;
    } else {
      final first = data.first;
      final last = data.last;
      if (last > first) {
        lineColor = upColor ?? _kUpColor;
      } else if (last < first) {
        lineColor = downColor ?? _kDownColor;
      } else {
        lineColor = flatColor ?? _kFlatColor;
      }
    }

    return SizedBox(
      width: chartWidth,
      height: chartHeight,
      child: CustomPaint(
        size: Size(chartWidth, chartHeight),
        painter: _SparklinePainter(
          data: data,
          lineColor: lineColor,
          strokeWidth: strokeWidth,
          referenceValue: referenceValue,
          referenceLineColor: referenceLineColor ?? Colors.grey.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final double strokeWidth;
  final double? referenceValue;
  final Color referenceLineColor;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    required this.strokeWidth,
    this.referenceValue,
    required this.referenceLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // 如果只有一个数据点，画一个点
    if (data.length == 1) {
      final paint = Paint()
        ..color = lineColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        strokeWidth,
        paint,
      );
      return;
    }

    // 添加少量边距以避免线条贴边
    const padding = 2.0;
    final effectiveWidth = size.width - padding * 2;
    final effectiveHeight = size.height - padding * 2;

    // 计算数据范围
    // 如果有参考值，使用 0-100 作为固定范围
    double minValue;
    double maxValue;
    if (referenceValue != null) {
      minValue = 0;
      maxValue = 100;
    } else {
      minValue = data.first;
      maxValue = data.first;
      for (final value in data) {
        if (value < minValue) minValue = value;
        if (value > maxValue) maxValue = value;
      }
    }

    // 处理所有值相同的情况
    double valueRange = maxValue - minValue;
    if (valueRange == 0) {
      valueRange = 1.0;
    }

    // 计算点之间的水平间距
    final xStep = effectiveWidth / (data.length - 1);

    // 将数据值转换为 Y 坐标
    double valueToY(double value) {
      return padding + (1 - (value - minValue) / valueRange) * effectiveHeight;
    }

    // 绘制参考线（如果有）
    if (referenceValue != null) {
      final refY = valueToY(referenceValue!);
      final refPaint = Paint()
        ..color = referenceLineColor
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(padding, refY),
        Offset(size.width - padding, refY),
        refPaint,
      );
    }

    // 创建数据线画笔
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 创建路径
    final path = Path();
    path.moveTo(padding, valueToY(data.first));

    for (var i = 1; i < data.length; i++) {
      final x = padding + i * xStep;
      final y = valueToY(data[i]);
      path.lineTo(x, y);
    }

    // 绘制数据线
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.referenceValue != referenceValue ||
        oldDelegate.referenceLineColor != referenceLineColor;
  }
}
