import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/backtest_config.dart';
import 'package:stock_rtwatcher/theme/theme.dart';

/// 回测图表组件
///
/// 提供两种图表视图，通过 Tab 切换：
/// 1. 成功率柱状图 - 展示各观察周期的成功率
/// 2. 收益分布直方图 - 展示涨幅分布区间
class BacktestChart extends StatefulWidget {
  /// 回测结果数据
  final BacktestResult result;

  /// 目标涨幅（用于在分布图上显示阈值线）
  final double targetGain;

  /// 图表高度
  final double height;

  const BacktestChart({
    super.key,
    required this.result,
    required this.targetGain,
    this.height = 200,
  });

  @override
  State<BacktestChart> createState() => _BacktestChartState();
}

class _BacktestChartState extends State<BacktestChart>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab 切换栏
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: '成功率', height: 36),
              Tab(text: '收益分布', height: 36),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 图表区域
        SizedBox(
          height: widget.height,
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // 成功率柱状图
              _SuccessRateChart(
                periodStats: widget.result.periodStats,
              ),
              // 收益分布直方图
              _ReturnDistributionChart(
                allMaxGains: widget.result.allMaxGains,
                targetGain: widget.targetGain,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 成功率柱状图
class _SuccessRateChart extends StatelessWidget {
  final List<PeriodStats> periodStats;

  const _SuccessRateChart({required this.periodStats});

  @override
  Widget build(BuildContext context) {
    if (periodStats.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return CustomPaint(
      size: Size.infinite,
      painter: _SuccessRatePainter(
        periodStats: periodStats,
        textColor: Theme.of(context).colorScheme.onSurface,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// 成功率柱状图绘制器
class _SuccessRatePainter extends CustomPainter {
  final List<PeriodStats> periodStats;
  final Color textColor;
  final Color gridColor;

  _SuccessRatePainter({
    required this.periodStats,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (periodStats.isEmpty) return;

    // 绘图区域边距
    const padding = EdgeInsets.only(left: 40, top: 20, right: 20, bottom: 30);
    final chartArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );

    // 绘制网格线和 Y 轴标签
    _drawGrid(canvas, chartArea);

    // 绘制柱状图
    _drawBars(canvas, chartArea);

    // 绘制 X 轴标签
    _drawXLabels(canvas, chartArea);
  }

  /// 绘制网格线和 Y 轴标签
  void _drawGrid(Canvas canvas, Rect chartArea) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // 绘制 5 条水平网格线 (0%, 25%, 50%, 75%, 100%)
    const gridCount = 4;
    for (var i = 0; i <= gridCount; i++) {
      final y = chartArea.bottom - (i / gridCount) * chartArea.height;
      final percent = (i / gridCount * 100).toInt();

      // 网格线
      canvas.drawLine(
        Offset(chartArea.left, y),
        Offset(chartArea.right, y),
        gridPaint,
      );

      // Y 轴标签
      textPainter.text = TextSpan(
        text: '$percent%',
        style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(chartArea.left - textPainter.width - 6, y - textPainter.height / 2),
      );
    }
  }

  /// 绘制柱状图
  void _drawBars(Canvas canvas, Rect chartArea) {
    final barCount = periodStats.length;
    final barWidth = chartArea.width / barCount * 0.6;
    final barSpacing = chartArea.width / barCount;

    for (var i = 0; i < barCount; i++) {
      final stat = periodStats[i];
      final x = chartArea.left + barSpacing * i + barSpacing / 2 - barWidth / 2;
      final barHeight = stat.successRate * chartArea.height;
      final y = chartArea.bottom - barHeight;

      // 根据成功率选择颜色渐变（越高越绿）
      final color = _getSuccessRateColor(stat.successRate);

      // 绘制柱子
      final barPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight.clamp(2.0, double.infinity)),
        const Radius.circular(4),
      );
      canvas.drawRRect(barRect, barPaint);

      // 绘制柱顶百分比标签
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${(stat.successRate * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x + barWidth / 2 - textPainter.width / 2, y - textPainter.height - 4),
      );
    }
  }

  /// 根据成功率获取颜色
  Color _getSuccessRateColor(double rate) {
    // 从浅绿到深绿的渐变
    if (rate >= 0.7) {
      return const Color(0xFF00AA00); // 深绿
    } else if (rate >= 0.5) {
      return const Color(0xFF44BB44); // 中绿
    } else if (rate >= 0.3) {
      return const Color(0xFF88CC88); // 浅绿
    } else {
      return const Color(0xFFBBDDBB); // 极浅绿
    }
  }

  /// 绘制 X 轴标签
  void _drawXLabels(Canvas canvas, Rect chartArea) {
    final barCount = periodStats.length;
    final barSpacing = chartArea.width / barCount;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i < barCount; i++) {
      final stat = periodStats[i];
      final x = chartArea.left + barSpacing * i + barSpacing / 2;

      textPainter.text = TextSpan(
        text: '${stat.days}天',
        style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 11),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, chartArea.bottom + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessRatePainter oldDelegate) {
    return periodStats != oldDelegate.periodStats ||
        textColor != oldDelegate.textColor ||
        gridColor != oldDelegate.gridColor;
  }
}

/// 收益分布直方图
class _ReturnDistributionChart extends StatelessWidget {
  final List<double> allMaxGains;
  final double targetGain;

  const _ReturnDistributionChart({
    required this.allMaxGains,
    required this.targetGain,
  });

  @override
  Widget build(BuildContext context) {
    if (allMaxGains.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return CustomPaint(
      size: Size.infinite,
      painter: _ReturnDistributionPainter(
        allMaxGains: allMaxGains,
        targetGain: targetGain,
        textColor: Theme.of(context).colorScheme.onSurface,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// 收益分布区间定义
class _GainRange {
  final String label;
  final double min;
  final double max;
  final Color color;

  const _GainRange(this.label, this.min, this.max, this.color);
}

/// 收益分布直方图绘制器
class _ReturnDistributionPainter extends CustomPainter {
  final List<double> allMaxGains;
  final double targetGain;
  final Color textColor;
  final Color gridColor;

  // 涨幅分布区间
  static const List<_GainRange> _ranges = [
    _GainRange('<-5%', double.negativeInfinity, -0.05, AppColors.stockDown),
    _GainRange('-5%~0%', -0.05, 0, AppColors.down0to5),
    _GainRange('0%~5%', 0, 0.05, AppColors.up0to5),
    _GainRange('5%~10%', 0.05, 0.10, AppColors.up5),
    _GainRange('>10%', 0.10, double.infinity, AppColors.stockUp),
  ];

  _ReturnDistributionPainter({
    required this.allMaxGains,
    required this.targetGain,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (allMaxGains.isEmpty) return;

    // 计算每个区间的数量
    final counts = List<int>.filled(_ranges.length, 0);
    for (final gain in allMaxGains) {
      for (var i = 0; i < _ranges.length; i++) {
        final range = _ranges[i];
        if (gain > range.min && gain <= range.max) {
          counts[i]++;
          break;
        }
      }
    }

    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return;

    // 绘图区域边距
    const padding = EdgeInsets.only(left: 30, top: 20, right: 20, bottom: 40);
    final chartArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );

    // 绘制网格线和 Y 轴标签
    _drawGrid(canvas, chartArea, maxCount);

    // 绘制柱状图
    _drawBars(canvas, chartArea, counts, maxCount);

    // 绘制 X 轴标签
    _drawXLabels(canvas, chartArea);

    // 绘制目标涨幅线
    _drawTargetLine(canvas, chartArea, size);
  }

  /// 绘制网格线和 Y 轴标签
  void _drawGrid(Canvas canvas, Rect chartArea, int maxCount) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // 绘制 4 条水平网格线
    const gridCount = 4;
    for (var i = 0; i <= gridCount; i++) {
      final y = chartArea.bottom - (i / gridCount) * chartArea.height;
      final count = (i / gridCount * maxCount).round();

      // 网格线
      canvas.drawLine(
        Offset(chartArea.left, y),
        Offset(chartArea.right, y),
        gridPaint,
      );

      // Y 轴标签
      textPainter.text = TextSpan(
        text: '$count',
        style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(chartArea.left - textPainter.width - 6, y - textPainter.height / 2),
      );
    }
  }

  /// 绘制柱状图
  void _drawBars(Canvas canvas, Rect chartArea, List<int> counts, int maxCount) {
    final barCount = _ranges.length;
    final barWidth = chartArea.width / barCount * 0.7;
    final barSpacing = chartArea.width / barCount;

    for (var i = 0; i < barCount; i++) {
      final range = _ranges[i];
      final count = counts[i];
      final x = chartArea.left + barSpacing * i + barSpacing / 2 - barWidth / 2;
      final barHeight = (count / maxCount) * chartArea.height;
      final y = chartArea.bottom - barHeight;

      // 绘制柱子
      final barPaint = Paint()
        ..color = range.color
        ..style = PaintingStyle.fill;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight.clamp(2.0, double.infinity)),
        const Radius.circular(4),
      );
      canvas.drawRRect(barRect, barPaint);

      // 绘制柱顶数量标签
      if (count > 0) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$count',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x + barWidth / 2 - textPainter.width / 2, y - textPainter.height - 2),
        );
      }
    }
  }

  /// 绘制 X 轴标签
  void _drawXLabels(Canvas canvas, Rect chartArea) {
    final barCount = _ranges.length;
    final barSpacing = chartArea.width / barCount;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i < barCount; i++) {
      final range = _ranges[i];
      final x = chartArea.left + barSpacing * i + barSpacing / 2;

      textPainter.text = TextSpan(
        text: range.label,
        style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, chartArea.bottom + 6),
      );
    }
  }

  /// 绘制目标涨幅阈值线
  void _drawTargetLine(Canvas canvas, Rect chartArea, Size size) {
    // 计算目标涨幅对应的 X 位置
    // 先找到目标涨幅所在的区间
    int targetRangeIndex = 0;
    for (var i = 0; i < _ranges.length; i++) {
      final range = _ranges[i];
      if (targetGain > range.min && targetGain <= range.max) {
        targetRangeIndex = i;
        break;
      }
    }

    // 计算在区间内的相对位置
    final range = _ranges[targetRangeIndex];
    final barSpacing = chartArea.width / _ranges.length;
    double relativePos;

    if (range.min == double.negativeInfinity) {
      relativePos = 0.5; // 第一个区间取中心
    } else if (range.max == double.infinity) {
      relativePos = 0.5; // 最后一个区间取中心
    } else {
      relativePos = (targetGain - range.min) / (range.max - range.min);
    }

    final x = chartArea.left + barSpacing * targetRangeIndex + barSpacing * relativePos;

    // 绘制垂直虚线
    final linePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashHeight = 5.0;
    const dashGap = 3.0;
    var y = chartArea.top;
    while (y < chartArea.bottom) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + dashHeight).clamp(chartArea.top, chartArea.bottom)),
        linePaint,
      );
      y += dashHeight + dashGap;
    }

    // 绘制目标涨幅标签
    final labelText = '目标: ${(targetGain * 100).toStringAsFixed(0)}%';
    final textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Color(0xFF2563EB),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // 标签背景
    final labelX = (x - textPainter.width / 2).clamp(chartArea.left, chartArea.right - textPainter.width);
    final labelY = chartArea.bottom + 20;

    final bgPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(labelX - 4, labelY - 2, textPainter.width + 8, textPainter.height + 4),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    textPainter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _ReturnDistributionPainter oldDelegate) {
    return allMaxGains != oldDelegate.allMaxGains ||
        targetGain != oldDelegate.targetGain ||
        textColor != oldDelegate.textColor ||
        gridColor != oldDelegate.gridColor;
  }
}
