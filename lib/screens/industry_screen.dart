import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/industry_detail_screen.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/widgets/sparkline_chart.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class IndustryScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const IndustryScreen({super.key, this.onIndustryTap});

  @override
  State<IndustryScreen> createState() => _IndustryScreenState();
}

class _IndustryScreenState extends State<IndustryScreen> {
  bool _hasCheckedTrend = false;
  int _fetchProgress = 0;
  int _fetchTotal = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasCheckedTrend) {
      _hasCheckedTrend = true;
      _checkAndRefreshTrend();
    }
  }

  Future<void> _checkAndRefreshTrend() async {
    final trendService = context.read<IndustryTrendService>();
    final marketProvider = context.read<MarketDataProvider>();
    final pool = context.read<TdxPool>();

    // 只有当有数据时才检查刷新
    if (marketProvider.allData.isNotEmpty) {
      await trendService.checkAndRefresh(pool, marketProvider.allData);
    }
  }

  Future<void> _manualRefreshTrend() async {
    final trendService = context.read<IndustryTrendService>();
    final marketProvider = context.read<MarketDataProvider>();
    final pool = context.read<TdxPool>();

    if (marketProvider.allData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先获取市场数据')),
        );
      }
      return;
    }

    // 显示进度对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ProgressDialog(
        getProgress: () => _fetchProgress,
        getTotal: () => _fetchTotal,
      ),
    );

    try {
      await trendService.fetchHistoricalData(
        pool,
        marketProvider.allData,
        (current, total) {
          setState(() {
            _fetchProgress = current;
            _fetchTotal = total;
          });
        },
      );

      // 关闭对话框
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('趋势数据已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取趋势数据失败: $e')),
        );
      }
    }
  }

  /// 计算行业统计
  List<IndustryStats> _calculateStats(List<StockMonitorData> data) {
    final Map<String, List<StockMonitorData>> grouped = {};

    for (final stock in data) {
      final industry = stock.industry ?? '未知';
      grouped.putIfAbsent(industry, () => []).add(stock);
    }

    final result = <String, IndustryStats>{};
    for (final entry in grouped.entries) {
      int up = 0, down = 0, flat = 0, ratioAbove = 0, ratioBelow = 0;

      for (final stock in entry.value) {
        // 涨跌统计
        if (stock.changePercent > 0.001) {
          up++;
        } else if (stock.changePercent < -0.001) {
          down++;
        } else {
          flat++;
        }
        // 量比统计
        if (stock.ratio >= 1.0) {
          ratioAbove++;
        } else {
          ratioBelow++;
        }
      }

      result[entry.key] = IndustryStats(
        name: entry.key,
        upCount: up,
        downCount: down,
        flatCount: flat,
        ratioAbove: ratioAbove,
        ratioBelow: ratioBelow,
      );
    }

    final statsList = result.values.toList()
      ..sort((a, b) => b.ratioSortValue.compareTo(a.ratioSortValue));

    return statsList;
  }

  /// 获取行业趋势数据（历史 + 今日）
  List<double> _getTrendData(
    String industry,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    final historicalData = trendService.getTrend(industry);
    final points = <double>[];

    // 添加历史数据（最近14天）
    if (historicalData != null && historicalData.points.isNotEmpty) {
      final recentPoints = historicalData.points.length > 14
          ? historicalData.points.sublist(historicalData.points.length - 14)
          : historicalData.points;
      for (final point in recentPoints) {
        points.add(point.ratioAbovePercent);
      }
    }

    // 添加今日数据
    final todayPoint = todayTrend[industry];
    if (todayPoint != null) {
      points.add(todayPoint.ratioAbovePercent);
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();
    final stats = _calculateStats(marketProvider.allData);
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);

    // 决定是否显示更新按钮
    final showRefreshButton = trendService.missingDays > 3 && !trendService.isLoading;

    return Scaffold(
      appBar: showRefreshButton
          ? AppBar(
              title: const Text('行业'),
              automaticallyImplyLeading: false,
              actions: [
                TextButton.icon(
                  onPressed: _manualRefreshTrend,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('更新趋势'),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            Expanded(
              child: stats.isEmpty && !marketProvider.isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无数据',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击刷新按钮获取数据',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // 表头
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 64,
                                child: Text(
                                  '行业',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '涨跌',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '量比',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 60,
                                child: Center(
                                  child: trendService.isLoading
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          '趋势',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () => marketProvider.refresh(),
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: stats.length,
                              itemExtent: 48,
                              itemBuilder: (context, index) => _buildRow(
                                context,
                                stats[index],
                                index,
                                trendService,
                                todayTrend,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    IndustryStats stats,
    int index,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    const upColor = Color(0xFFFF4444);
    const downColor = Color(0xFF00AA00);

    final trendData = _getTrendData(stats.name, trendService, todayTrend);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => IndustryDetailScreen(industry: stats.name),
          ),
        );
      },
      onLongPress: widget.onIndustryTap != null
          ? () => widget.onIndustryTap!(stats.name)
          : null,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: index.isOdd
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            // 行业名
            SizedBox(
              width: 64,
              child: Text(
                stats.name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 涨跌进度条 + 数字
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Row(
                        children: [
                          if (stats.upCount > 0)
                            Expanded(
                              flex: stats.upCount,
                              child: Container(height: 6, color: upColor),
                            ),
                          if (stats.downCount > 0)
                            Expanded(
                              flex: stats.downCount,
                              child: Container(height: 6, color: downColor),
                            ),
                          if (stats.upCount == 0 && stats.downCount == 0)
                            Expanded(
                              child: Container(
                                height: 6,
                                color: Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.upCount}↑ ${stats.downCount}↓',
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // 量比进度条 + 数字
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Row(
                        children: [
                          if (stats.ratioAbove > 0)
                            Expanded(
                              flex: stats.ratioAbove,
                              child: Container(height: 6, color: upColor),
                            ),
                          if (stats.ratioBelow > 0)
                            Expanded(
                              flex: stats.ratioBelow,
                              child: Container(height: 6, color: downColor),
                            ),
                          if (stats.ratioAbove == 0 && stats.ratioBelow == 0)
                            Expanded(
                              child: Container(
                                height: 6,
                                color: Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.ratioAbove}↑ ${stats.ratioBelow}↓',
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // 趋势迷你图
            SizedBox(
              width: 60,
              child: Center(
                child: trendData.isNotEmpty
                    ? SparklineChart(
                        data: trendData,
                        width: 56,
                        height: 24,
                      )
                    : Text(
                        '-',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 进度对话框
class _ProgressDialog extends StatefulWidget {
  final int Function() getProgress;
  final int Function() getTotal;

  const _ProgressDialog({
    required this.getProgress,
    required this.getTotal,
  });

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  @override
  void initState() {
    super.initState();
    _startUpdating();
  }

  void _startUpdating() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.getProgress();
    final total = widget.getTotal();

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在获取趋势数据',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            total > 0 ? '($progress/$total)' : '准备中...',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
