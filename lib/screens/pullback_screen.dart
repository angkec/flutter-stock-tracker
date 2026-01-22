import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/pullback_config.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';
import 'package:stock_rtwatcher/widgets/pullback_config_dialog.dart';

/// 回踩页面 - 显示所有高质量回踩的股票
class PullbackScreen extends StatelessWidget {
  final void Function(String industry)? onIndustryTap;

  const PullbackScreen({super.key, this.onIndustryTap});

  String _dropModeText(DropMode mode) {
    switch (mode) {
      case DropMode.todayDown:
        return '今跌';
      case DropMode.belowYesterdayHigh:
        return '低昨高';
      case DropMode.none:
        return '';
    }
  }

  void _showConfigDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const PullbackConfigDialog(),
    );
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
    final pullbackService = context.watch<PullbackService>();
    final watchlist = context.watch<WatchlistService>();
    final trendService = context.watch<IndustryTrendService>();

    // 筛选出回踩股票
    final pullbackStocks = provider.allData
        .where((data) => data.isPullback)
        .toList();

    // 计算今日实时趋势数据
    final todayTrend = trendService.calculateTodayTrend(provider.allData);

    return Scaffold(
      appBar: AppBar(
        title: const Text('单日回踩'),
        actions: [
          // 重算按钮
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: '重算回踩',
            onPressed: () {
              final error = provider.recalculatePullbacks();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(error ?? '已重算回踩'),
                  duration: const Duration(seconds: 2),
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
                    '昨涨>${(pullbackService.config.minYesterdayGain * 100).toStringAsFixed(0)}% '
                    '量>${pullbackService.config.volumeMultiplier}x '
                    '${_dropModeText(pullbackService.config.dropMode)} '
                    '跌<${(pullbackService.config.maxDropRatio * 100).toStringAsFixed(0)}% '
                    '日量比<${pullbackService.config.maxDailyRatio} '
                    '分量比>${pullbackService.config.minMinuteRatio}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  '${pullbackStocks.length}只',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // 股票列表
          Expanded(
            child: pullbackStocks.isEmpty
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
                    stocks: pullbackStocks,
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
