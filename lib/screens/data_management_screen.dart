import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/config/debug_config.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';

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

              // 历史分钟K线 (managed by DataRepository)
              Consumer<DataRepository>(
                builder: (context, repository, _) {
                  return FutureBuilder<({String subtitle, int missingDays})>(
                    future: _getKlineStatus(repository, provider),
                    builder: (context, snapshot) {
                      final status = snapshot.data ?? (subtitle: '加载中...', missingDays: 0);

                      return _buildKlineCacheItem(
                        context,
                        title: '历史分钟K线',
                        subtitle: status.subtitle,
                        size: '-', // Size is managed by DataRepository
                        missingDays: status.missingDays,
                        isLoading: false, // Loading state handled by progress dialog
                        onFetch: () => _fetchHistoricalKline(context),
                        onClear: () => _confirmClear(context, '历史分钟K线', () async {
                          // Clear all minute K-line data by cleaning up with a future date
                          await repository.cleanupOldData(
                            beforeDate: DateTime.now().add(const Duration(days: 1)),
                          );
                          if (context.mounted) {
                            context.read<IndustryTrendService>().clearCache();
                            context.read<IndustryRankService>().clearCache();
                          }
                        }),
                      );
                    },
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

  /// Get status of kline data from DataRepository
  Future<({String subtitle, int missingDays})> _getKlineStatus(
    DataRepository repository,
    MarketDataProvider provider,
  ) async {
    if (provider.allData.isEmpty) {
      return (subtitle: '暂无数据', missingDays: 0);
    }

    try {
      final stockCodes = provider.allData.map((d) => d.stock.code).toList();
      final freshness = await repository.checkFreshness(
        stockCodes: stockCodes,
        dataType: KLineDataType.oneMinute,
      );

      int missingCount = 0;
      int staleCount = 0;
      int freshCount = 0;
      for (final entry in freshness.entries) {
        switch (entry.value) {
          case Missing():
            missingCount++;
          case Stale():
            staleCount++;
          case Fresh():
            freshCount++;
        }
      }

      final total = stockCodes.length;
      final dateRange = DateRange(
        DateTime.now().subtract(const Duration(days: 30)),
        DateTime.now(),
      );
      final dateRangeStr = '${dateRange.start.toString().split(' ')[0]} ~ ${dateRange.end.toString().split(' ')[0]}';

      // 判断数据完整性：以股票覆盖率为准
      // - 如果 >95% 的股票有数据，视为数据完整
      // - 否则显示缺失的股票数量
      final coveragePercent = total > 0 ? (freshCount + staleCount) * 100 ~/ total : 0;

      if (missingCount == 0 && staleCount == 0) {
        // 全部 Fresh
        return (subtitle: '$dateRangeStr，数据完整', missingDays: 0);
      } else if (coveragePercent >= 95) {
        // 绝大多数有数据，忽略少量缺失
        return (subtitle: '$dateRangeStr，数据完整', missingDays: 0);
      } else if (freshCount == 0 && staleCount == 0) {
        // 完全没有数据
        return (subtitle: '$dateRangeStr，暂无数据', missingDays: 30);
      } else {
        // 有明显缺失
        return (subtitle: '$dateRangeStr，$missingCount 只股票缺失数据', missingDays: missingCount);
      }
    } catch (e) {
      debugPrint('[DataManagement] 获取K线状态失败: $e');
      return (subtitle: '状态未知', missingDays: 0);
    }
  }

  Future<void> _fetchHistoricalKline(BuildContext context) async {
    final klineService = context.read<HistoricalKlineService>();
    final marketProvider = context.read<MarketDataProvider>();
    final repository = context.read<DataRepository>();
    final trendService = context.read<IndustryTrendService>();
    final rankService = context.read<IndustryRankService>();

    if (marketProvider.allData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先刷新市场数据')),
      );
      return;
    }

    // 显示进度对话框
    final progressNotifier = ValueNotifier<({int current, int total, String stage})>(
      (current: 0, total: 1, stage: '准备中...'),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(progressNotifier: progressNotifier),
    );

    try {
      var stocks = marketProvider.allData.map((d) => d.stock).toList();

      // Debug 模式下限制股票数量
      stocks = DebugConfig.limitStocks(stocks);

      final stockCodes = stocks.map((s) => s.code).toList();
      final dateRange = DateRange(
        DateTime.now().subtract(const Duration(days: 30)),
        DateTime.now(),
      );

      debugPrint('[DataManagement] 开始拉取历史数据, ${stockCodes.length} 只股票');
      await repository.fetchMissingData(
        stockCodes: stockCodes,
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
        onProgress: (current, total) {
          progressNotifier.value = (
            current: current,
            total: total,
            stage: '1/3 拉取K线数据',
          );
        },
      );
      debugPrint('[DataManagement] K线数据已保存');

      // Get current data version for cache validation
      final dataVersion = await repository.getCurrentVersion();

      // 计算行业趋势和排名（数据来自 DataRepository）
      if (context.mounted) {
        debugPrint('[DataManagement] 开始计算行业趋势');
        progressNotifier.value = (current: 0, total: 1, stage: '2/3 计算行业趋势...');
        await trendService.recalculateFromKlineData(klineService, marketProvider.allData, dataVersion: dataVersion);
        debugPrint('[DataManagement] 行业趋势计算完成');

        debugPrint('[DataManagement] 开始计算行业排名');
        progressNotifier.value = (current: 0, total: 1, stage: '3/3 计算行业排名...');
        await rankService.recalculateFromKlineData(klineService, marketProvider.allData, dataVersion: dataVersion);
        debugPrint('[DataManagement] 行业排名计算完成');
      }
    } finally {
      // 关闭进度对话框
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('历史数据已更新')),
        );
      }
      progressNotifier.dispose();
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

class _ProgressDialog extends StatelessWidget {
  final ValueNotifier<({int current, int total, String stage})> progressNotifier;

  const _ProgressDialog({required this.progressNotifier});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('拉取历史数据'),
      content: ValueListenableBuilder<({int current, int total, String stage})>(
        valueListenable: progressNotifier,
        builder: (context, progress, _) {
          final isProcessing = progress.stage.contains('处理');
          final percent = progress.total > 0
              ? (progress.current / progress.total * 100).toStringAsFixed(1)
              : '0.0';
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: isProcessing ? null : (progress.total > 0 ? progress.current / progress.total : null),
              ),
              const SizedBox(height: 16),
              Text(progress.stage),
              const SizedBox(height: 8),
              if (!isProcessing)
                Text(
                  '${progress.current} / ${progress.total} ($percent%)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          );
        },
      ),
    );
  }
}
