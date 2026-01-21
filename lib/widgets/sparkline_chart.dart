import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/theme/app_colors.dart';

/// 迷你折线图组件，用于显示趋势
///
/// 当设置了 referenceValue 时，折线会根据是否在参考值上下分段着色：
/// - 在参考值以上的部分：红色（upColor）
/// - 在参考值以下的部分：绿色（downColor）
///
/// 没有 referenceValue 时，根据首尾值的关系选择整条线的颜色。
class SparklineChart extends StatelessWidget {
  /// 要绘制的数据点列表
  final List<double> data;

  /// 图表宽度，默认为 60
  final double? width;

  /// 图表高度，默认为 20
  final double? height;

  /// 上涨/高于参考值颜色
  final Color? upColor;

  /// 下跌/低于参考值颜色
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

    // 确定线条颜色（用于无参考值时的整条线颜色）
    final Color lineColor;
    if (data.length < 2) {
      lineColor = flatColor ?? AppColors.stockFlat;
    } else {
      final first = data.first;
      final last = data.last;
      if (last > first) {
        lineColor = upColor ?? AppColors.stockUp;
      } else if (last < first) {
        lineColor = downColor ?? AppColors.stockDown;
      } else {
        lineColor = flatColor ?? AppColors.stockFlat;
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
          upColor: upColor ?? AppColors.stockUp,
          downColor: downColor ?? AppColors.stockDown,
          strokeWidth: strokeWidth,
          referenceValue: referenceValue,
          referenceLineColor: referenceLineColor ?? Colors.grey,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color upColor;
  final Color downColor;
  final double strokeWidth;
  final double? referenceValue;
  final Color referenceLineColor;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    required this.upColor,
    required this.downColor,
    required this.strokeWidth,
    this.referenceValue,
    required this.referenceLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // 添加少量边距以避免线条贴边
    const padding = 2.0;
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

    // 将数据值转换为 Y 坐标
    double valueToY(double value) {
      return padding + (1 - (value - minValue) / valueRange) * effectiveHeight;
    }

    // 绘制参考线（如果有）- 在绘制数据线之前绘制，这样数据线在参考线上方
    if (referenceValue != null) {
      final refY = valueToY(referenceValue!);
      final refPaint = Paint()
        ..color = referenceLineColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      // 使用虚线效果 - 稍长的dash更容易看到
      const dashWidth = 3.0;
      const dashSpace = 2.0;
      var x = padding;
      while (x < size.width - padding) {
        canvas.drawLine(
          Offset(x, refY),
          Offset((x + dashWidth).clamp(0, size.width - padding), refY),
          refPaint,
        );
        x += dashWidth + dashSpace;
      }
    }

    // 如果只有一个数据点，画一个点
    if (data.length == 1) {
      final pointColor = referenceValue != null
          ? (data.first > referenceValue! ? upColor : downColor)
          : lineColor;
      final paint = Paint()
        ..color = pointColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        strokeWidth,
        paint,
      );
      return;
    }

    final effectiveWidth = size.width - padding * 2;

    // 计算点之间的水平间距
    final xStep = effectiveWidth / (data.length - 1);

    // 如果没有参考值，使用单色绘制整条线
    if (referenceValue == null) {
      final paint = Paint()
        ..color = lineColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path();
      path.moveTo(padding, valueToY(data.first));

      for (var i = 1; i < data.length; i++) {
        final x = padding + i * xStep;
        final y = valueToY(data[i]);
        path.lineTo(x, y);
      }

      canvas.drawPath(path, paint);
      return;
    }

    // 有参考值时，分段绘制不同颜色
    final upPaint = Paint()
      ..color = upColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final downPaint = Paint()
      ..color = downColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ref = referenceValue!;

    // 逐段绘制，每段根据是在参考值上方还是下方决定颜色
    for (var i = 0; i < data.length - 1; i++) {
      final x1 = padding + i * xStep;
      final x2 = padding + (i + 1) * xStep;
      final v1 = data[i];
      final v2 = data[i + 1];
      final y1 = valueToY(v1);
      final y2 = valueToY(v2);

      // 判断这段线是否跨越参考值
      final above1 = v1 >= ref;
      final above2 = v2 >= ref;

      if (above1 == above2) {
        // 整段都在同一侧，使用对应颜色
        final paint = above1 ? upPaint : downPaint;
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      } else {
        // 跨越参考值，需要计算交点并分两段绘制
        // 线性插值找交点
        final t = (ref - v1) / (v2 - v1);
        final crossX = x1 + t * (x2 - x1);
        final crossY = valueToY(ref);

        // 绘制第一段（从起点到交点）
        final paint1 = above1 ? upPaint : downPaint;
        canvas.drawLine(Offset(x1, y1), Offset(crossX, crossY), paint1);

        // 绘制第二段（从交点到终点）
        final paint2 = above2 ? upPaint : downPaint;
        canvas.drawLine(Offset(crossX, crossY), Offset(x2, y2), paint2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.upColor != upColor ||
        oldDelegate.downColor != downColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.referenceValue != referenceValue ||
        oldDelegate.referenceLineColor != referenceLineColor;
  }
}
