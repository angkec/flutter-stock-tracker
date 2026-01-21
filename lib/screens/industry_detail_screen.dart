import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

/// 行业详情页
class IndustryDetailScreen extends StatelessWidget {
  final String industry;

  const IndustryDetailScreen({
    super.key,
    required this.industry,
  });

  /// 获取行业趋势数据（历史 + 今日）
  List<double> _getTrendData(
    IndustryTrendService trendService,
    DailyRatioPoint? todayPoint,
  ) {
    final historicalData = trendService.getTrend(industry);
    final points = <double>[];

    // 添加历史数据（最近30天）
    if (historicalData != null && historicalData.points.isNotEmpty) {
      for (final point in historicalData.points) {
        points.add(point.ratioAbovePercent);
      }
    }

    // 添加今日数据
    if (todayPoint != null) {
      points.add(todayPoint.ratioAbovePercent);
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    // 筛选该行业的股票
    final industryStocks = marketProvider.allData
        .where((data) => data.industry == industry)
        .toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));

    // 计算今日数据
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);
    final todayPoint = todayTrend[industry];

    // 获取趋势数据
    final trendData = _getTrendData(trendService, todayPoint);

    // 计算今日统计
    final totalStocks = industryStocks.length;
    final ratioAboveCount = industryStocks.where((s) => s.ratio > 1.0).length;
    final ratioAbovePercent = totalStocks > 0
        ? (ratioAboveCount / totalStocks * 100).toStringAsFixed(0)
        : '0';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(industry, style: const TextStyle(fontSize: 18)),
            const Text(
              '量比趋势',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 趋势图区域
          Container(
            height: 150,
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: trendData.isNotEmpty
                ? _TrendChartPlaceholder(data: trendData)
                : Center(
                    child: Text(
                      '暂无趋势数据',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),

          // 今日摘要
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    '今日: $ratioAbovePercent%',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '($ratioAboveCount/$totalStocks 只放量)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 成分股列表标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '成分股列表',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),

          // 成分股表格
          Expanded(
            child: StockTable(
              stocks: industryStocks,
              isLoading: marketProvider.isLoading,
            ),
          ),
        ],
      ),
    );
  }
}

/// 趋势图占位组件（Task 6 会替换为真正的图表）
class _TrendChartPlaceholder extends StatelessWidget {
  final List<double> data;

  const _TrendChartPlaceholder({required this.data});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SimpleTrendPainter(
        data: data,
        lineColor: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
      ),
      child: Container(),
    );
  }
}

/// 简单趋势图绘制器
class _SimpleTrendPainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final Color gridColor;

  _SimpleTrendPainter({
    required this.data,
    required this.lineColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const padding = EdgeInsets.all(16);
    final chartArea = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.horizontal,
      size.height - padding.vertical,
    );

    // 计算数据范围
    final minValue = data.reduce((a, b) => a < b ? a : b);
    final maxValue = data.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;
    final adjustedMin = range > 0 ? minValue - range * 0.1 : minValue - 5;
    final adjustedMax = range > 0 ? maxValue + range * 0.1 : maxValue + 5;
    final adjustedRange = adjustedMax - adjustedMin;

    // 绘制50%参考线
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final y50 = chartArea.bottom -
        ((50 - adjustedMin) / adjustedRange) * chartArea.height;
    if (y50 >= chartArea.top && y50 <= chartArea.bottom) {
      canvas.drawLine(
        Offset(chartArea.left, y50),
        Offset(chartArea.right, y50),
        gridPaint..strokeWidth = 1,
      );
      // 绘制50%标签
      final textPainter = TextPainter(
        text: TextSpan(
          text: '50%',
          style: TextStyle(color: gridColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(chartArea.left, y50 - textPainter.height - 2));
    }

    // 绘制折线
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = chartArea.left + (i / (data.length - 1)) * chartArea.width;
      final y = chartArea.bottom -
          ((data[i] - adjustedMin) / adjustedRange) * chartArea.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    // 绘制最后一个点
    final lastX = chartArea.right;
    final lastY = chartArea.bottom -
        ((data.last - adjustedMin) / adjustedRange) * chartArea.height;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(lastX, lastY), 4, dotPaint);

    // 绘制最后一个值标签
    final valuePainter = TextPainter(
      text: TextSpan(
        text: '${data.last.toStringAsFixed(0)}%',
        style: TextStyle(color: lineColor, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    valuePainter.layout();
    valuePainter.paint(
      canvas,
      Offset(lastX - valuePainter.width - 8, lastY - valuePainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SimpleTrendPainter oldDelegate) {
    return data != oldDelegate.data ||
        lineColor != oldDelegate.lineColor ||
        gridColor != oldDelegate.gridColor;
  }
}
