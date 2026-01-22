import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';
import 'package:stock_rtwatcher/widgets/breakout_config_dialog.dart';
import 'package:stock_rtwatcher/screens/backtest_screen.dart';

/// 放量突破页面 - 显示所有放量突破后回踩的股票
class BreakoutScreen extends StatelessWidget {
  final void Function(String industry)? onIndustryTap;

  const BreakoutScreen({super.key, this.onIndustryTap});

  void _showConfigDialog(BuildContext context) {
    showBreakoutConfigSheet(context);
  }

  void _handleLongPress(BuildContext context, dynamic data) {
    final watchlist = context.read<WatchlistService>();
    final code = data.stock.code;
    final name = data.stock.name;
    final isInWatchlist = watchlist.contains(code);

    if (isInWatchlist) {
      watchlist.removeStock(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已从自选移除: $name'),
          duration: const Duration(seconds: 1),
        ),
      );
    } else {
      watchlist.addStock(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加到自选: $name'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MarketDataProvider>();
    final breakoutService = context.watch<BreakoutService>();
    final watchlist = context.watch<WatchlistService>();
    final trendService = context.watch<IndustryTrendService>();

    // 筛选出突破股票
    final breakoutStocks = provider.allData
        .where((data) => data.isBreakout)
        .toList();

    final config = breakoutService.config;

    // 计算今日实时趋势数据
    final todayTrend = trendService.calculateTodayTrend(provider.allData);

    return Scaffold(
      appBar: AppBar(
        title: const Text('多日回踩'),
        actions: [
          // 回测分析按钮
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: '回测分析',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BacktestScreen(),
                ),
              );
            },
          ),
          // 配置按钮
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '配置条件',
            onPressed: () => _showConfigDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 配置摘要
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '量>${config.breakVolumeMultiplier}x '
                    'MA${config.maBreakDays} '
                    '前高${config.highBreakDays}天 '
                    '${config.maxUpperShadowRatio > 0 ? "上引<${config.maxUpperShadowRatio.toStringAsFixed(1)} " : ""}'
                    '回${config.minPullbackDays}-${config.maxPullbackDays}天 '
                    '跌<${(config.maxTotalDrop * 100).toStringAsFixed(0)}%'
                    '(${config.dropReferencePoint == DropReferencePoint.breakoutClose ? "收" : "高"}) '
                    '${config.filterSurgeAfterPullback ? "滤涨>${(config.surgeThreshold * 100).toStringAsFixed(0)}%" : ""}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  '${breakoutStocks.length}只',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // 股票列表
          Expanded(
            child: breakoutStocks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无符合条件的股票',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '请先在全市场页面刷新数据',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : StockTable(
                    stocks: breakoutStocks,
                    highlightCodes: watchlist.watchlist.toSet(),
                    onLongPress: (data) => _handleLongPress(context, data),
                    onIndustryTap: onIndustryTap,
                    industryTrendData: trendService.trendData,
                    todayTrendData: todayTrend,
                  ),
          ),
        ],
      ),
    );
  }
}
