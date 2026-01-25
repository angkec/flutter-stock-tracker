import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class DataManagementScreen extends StatelessWidget {
  const DataManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: Consumer<MarketDataProvider>(
        builder: (_, provider, __) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 缓存总大小
              _buildSummaryCard(context, provider),
              const SizedBox(height: 16),

              // 分类缓存列表
              _buildCacheItem(
                context,
                title: '日K数据',
                subtitle: '${provider.dailyBarsCacheCount}只股票',
                size: provider.dailyBarsCacheSize,
                onClear: () => _confirmClear(context, '日K数据', () => provider.clearDailyBarsCache()),
              ),
              _buildCacheItem(
                context,
                title: '分时数据',
                subtitle: '${provider.minuteDataCacheCount}只股票',
                size: provider.minuteDataCacheSize,
                onClear: () => _confirmClear(context, '分时数据', () => provider.clearMinuteDataCache()),
              ),
              _buildCacheItem(
                context,
                title: '行业数据',
                subtitle: provider.industryDataLoaded ? '已加载' : '未加载',
                size: provider.industryDataCacheSize,
                onClear: () => _confirmClear(context, '行业数据', () => provider.clearIndustryDataCache()),
              ),

              // 历史分钟K线
              Consumer<HistoricalKlineService>(
                builder: (context, klineService, _) {
                  final range = klineService.getDateRange();
                  final missingDays = klineService.getMissingDays();
                  final subtitle = range.earliest != null
                      ? '${range.earliest} ~ ${range.latest}，缺失 $missingDays 天'
                      : '暂无数据';

                  return _buildKlineCacheItem(
                    context,
                    title: '历史分钟K线',
                    subtitle: subtitle,
                    size: klineService.cacheSizeFormatted,
                    missingDays: missingDays,
                    isLoading: klineService.isLoading,
                    onFetch: () => _fetchHistoricalKline(context),
                    onClear: () => _confirmClear(context, '历史分钟K线', () async {
                      await klineService.clear();
                      // TODO: 同时清空依赖的服务缓存（clearCache方法将在后续任务中添加）
                      // if (context.mounted) {
                      //   context.read<IndustryTrendService>().clearCache();
                      //   context.read<IndustryRankService>().clearCache();
                      // }
                    }),
                  );
                },
              ),

              const SizedBox(height: 24),

              // 刷新进度提示
              if (provider.isLoading) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            provider.stageDescription ?? '刷新中...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _confirmClearAll(context, provider),
                      child: const Text('清空所有缓存'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: provider.isLoading
                          ? null
                          : () => provider.refresh(),
                      child: const Text('刷新数据'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, MarketDataProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('缓存总大小'),
            Text(provider.totalCacheSizeFormatted),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String? size,
    required VoidCallback onClear,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (size != null) Text(size),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onClear,
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  Widget _buildKlineCacheItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String size,
    required int missingDays,
    required bool isLoading,
    required VoidCallback onFetch,
    required VoidCallback onClear,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(size),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (missingDays > 0)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isLoading ? null : onFetch,
                      icon: isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download, size: 18),
                      label: Text(isLoading ? '拉取中...' : '拉取缺失'),
                    ),
                  ),
                if (missingDays > 0) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClear,
                    child: const Text('清空'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchHistoricalKline(BuildContext context) async {
    final klineService = context.read<HistoricalKlineService>();
    final marketProvider = context.read<MarketDataProvider>();
    final pool = context.read<TdxPool>();
    // ignore: unused_local_variable
    final trendService = context.read<IndustryTrendService>();
    // ignore: unused_local_variable
    final rankService = context.read<IndustryRankService>();

    if (marketProvider.allData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先刷新市场数据')),
      );
      return;
    }

    final stocks = marketProvider.allData.map((d) => d.stock).toList();
    await klineService.fetchMissingDays(pool, stocks, null);

    // 拉取完成后，触发重算
    // TODO: recalculateFromKlineData 方法将在 Tasks 8 和 9 中添加
    if (context.mounted) {
      // await trendService.recalculateFromKlineData(klineService, marketProvider.allData);
      // await rankService.recalculateFromKlineData(klineService, marketProvider.allData);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('历史数据已更新')),
      );
    }
  }

  void _confirmClear(BuildContext context, String title, VoidCallback onClear) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认清空'),
        content: Text('确定要清空 $title 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              onClear();
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, MarketDataProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空所有缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.clearAllCache();
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
