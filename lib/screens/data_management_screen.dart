import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:stock_rtwatcher/config/debug_config.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  // 用于强制刷新 FutureBuilder
  int _refreshKey = 0;
  static const double _minTradingDateCoverageRatio = 0.3;
  static const int _minCompleteMinuteBars = 220;
  static const int _latestTradingDayProbeDays = 20;

  void _triggerRefresh() {
    setState(() {
      _refreshKey++;
    });
  }

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
                onClear: () => _confirmClear(
                  context,
                  '日K数据',
                  () => provider.clearDailyBarsCache(),
                ),
              ),
              _buildCacheItem(
                context,
                title: '分时数据',
                subtitle: '${provider.minuteDataCacheCount}只股票',
                size: provider.minuteDataCacheSize,
                onClear: () => _confirmClear(
                  context,
                  '分时数据',
                  () => provider.clearMinuteDataCache(),
                ),
              ),
              _buildCacheItem(
                context,
                title: '行业数据',
                subtitle: provider.industryDataLoaded ? '已加载' : '未加载',
                size: provider.industryDataCacheSize,
                onClear: () => _confirmClear(
                  context,
                  '行业数据',
                  () => provider.clearIndustryDataCache(),
                ),
              ),

              // 历史分钟K线 (managed by DataRepository)
              Consumer<DataRepository>(
                builder: (context, repository, _) {
                  return FutureBuilder<({String subtitle, int missingDays})>(
                    key: ValueKey(_refreshKey),
                    future: _getKlineStatus(repository, provider),
                    builder: (context, snapshot) {
                      final status =
                          snapshot.data ?? (subtitle: '加载中...', missingDays: 0);

                      return _buildKlineCacheItem(
                        context,
                        title: '历史分钟K线',
                        subtitle: status.subtitle,
                        size: '-', // Size is managed by DataRepository
                        missingDays: status.missingDays,
                        isLoading:
                            false, // Loading state handled by progress dialog
                        onFetch: () => _fetchHistoricalKline(context),
                        onRecheck: () =>
                            _recheckDataFreshness(context, repository),
                        onClear: () => _confirmClear(context, '历史分钟K线', () async {
                          // Clear all minute K-line data by cleaning up with a future date
                          await repository.cleanupOldData(
                            beforeDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                            dataType: KLineDataType.oneMinute,
                          );
                          if (context.mounted) {
                            context.read<IndustryTrendService>().clearCache();
                            context.read<IndustryRankService>().clearCache();
                            _triggerRefresh();
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
          TextButton(onPressed: onClear, child: const Text('清空')),
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
    required VoidCallback onRecheck,
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
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
                  child: OutlinedButton.icon(
                    onPressed: onRecheck,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重新检测'),
                  ),
                ),
                const SizedBox(width: 8),
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
  ///
  /// 简化检查：只抽样检查少量股票，避免遍历全部股票导致卡顿
  Future<({String subtitle, int missingDays})> _getKlineStatus(
    DataRepository repository,
    MarketDataProvider provider,
  ) async {
    if (provider.allData.isEmpty) {
      return (subtitle: '暂无数据', missingDays: 0);
    }

    try {
      final allStockCodes = provider.allData.map((d) => d.stock.code).toList();

      // 只抽样检查前 20 只股票，避免检查全部导致卡顿
      const sampleSize = 20;
      final sampleCodes = allStockCodes.length > sampleSize
          ? allStockCodes.sublist(0, sampleSize)
          : allStockCodes;

      final dateRange = DateRange(
        DateTime.now().subtract(const Duration(days: 30)),
        DateTime.now(),
      );
      final dateRangeStr =
          '${dateRange.start.toString().split(' ')[0]} ~ ${dateRange.end.toString().split(' ')[0]}';

      final tradingDays = await repository.getTradingDates(dateRange);
      if (!_hasReliableTradingDateCoverage(tradingDays, dateRange)) {
        final lastTradingStatus = await _evaluateLatestTradingDayStatus(
          repository: repository,
          stockCodes: sampleCodes,
        );

        final lastTradingDate = lastTradingStatus.lastTradingDate;
        if (lastTradingDate == null) {
          return (subtitle: '$dateRangeStr，交易日基线不足，历史完整性待确认', missingDays: 30);
        }

        final issueCount =
            lastTradingStatus.missingStocks +
            lastTradingStatus.incompleteStocks;
        final dateStr = _formatDate(lastTradingDate);

        if (issueCount == 0) {
          return (
            subtitle:
                '$dateRangeStr，交易日基线不足；最后交易日($dateStr)数据完整 (${lastTradingStatus.completeStocks}/${sampleCodes.length})',
            missingDays: 0,
          );
        }

        final issueParts = <String>[];
        if (lastTradingStatus.missingStocks > 0) {
          issueParts.add('缺失${lastTradingStatus.missingStocks}只');
        }
        if (lastTradingStatus.incompleteStocks > 0) {
          issueParts.add('不完整${lastTradingStatus.incompleteStocks}只');
        }

        return (
          subtitle:
              '$dateRangeStr，交易日基线不足；最后交易日($dateStr)${issueParts.join('，')}',
          missingDays: issueCount,
        );
      }

      // 使用 findMissingMinuteDatesBatch 获取真实的完整性状态
      final results = await repository.findMissingMinuteDatesBatch(
        stockCodes: sampleCodes,
        dateRange: dateRange,
      );

      int completeCount = 0;
      int totalMissingDays = 0;
      int totalIncompleteDays = 0;

      for (final entry in results.entries) {
        final result = entry.value;
        if (result.missingDates.isEmpty && result.incompleteDates.isEmpty) {
          // 数据完整
          completeCount++;
        }
        totalMissingDays += result.missingDates.length;
        totalIncompleteDays += result.incompleteDates.length;
      }

      // 判断整体状态
      if (completeCount == 0 &&
          totalMissingDays == 0 &&
          totalIncompleteDays == 0) {
        // 没有交易日数据（可能日K也没有）
        return (subtitle: '$dateRangeStr，暂无数据', missingDays: 30);
      } else if (completeCount >= sampleCodes.length * 0.8) {
        return (
          subtitle: '$dateRangeStr，数据完整 ($completeCount/${sampleCodes.length})',
          missingDays: 0,
        );
      } else if (totalMissingDays > 0 || totalIncompleteDays > 0) {
        final issue = totalMissingDays > 0
            ? '缺失$totalMissingDays天'
            : '不完整$totalIncompleteDays天';
        return (
          subtitle: '$dateRangeStr，$issue',
          missingDays: totalMissingDays + totalIncompleteDays,
        );
      } else {
        return (
          subtitle: '$dateRangeStr，部分完整 ($completeCount/${sampleCodes.length})',
          missingDays: 1,
        );
      }
    } catch (e) {
      debugPrint('[DataManagement] 获取K线状态失败: $e');
      return (subtitle: '状态未知', missingDays: 0);
    }
  }

  /// 重新检测数据完整性（清除缓存后重新检查）
  Future<void> _recheckDataFreshness(
    BuildContext context,
    DataRepository repository,
  ) async {
    final marketProvider = context.read<MarketDataProvider>();

    if (marketProvider.allData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先刷新市场数据')));
      return;
    }

    // 显示进度对话框
    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '清除缓存...',
        ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(progressNotifier: progressNotifier),
    );

    try {
      // 1. 清除检测缓存
      final clearedCount = await repository.clearFreshnessCache(
        dataType: KLineDataType.oneMinute,
      );
      debugPrint('[DataManagement] 已清除 $clearedCount 条检测缓存');

      // 2. 获取所有股票代码
      var stocks = marketProvider.allData.map((d) => d.stock).toList();
      stocks = DebugConfig.limitStocks(stocks);
      final stockCodes = stocks.map((s) => s.code).toList();

      final dateRange = DateRange(
        DateTime.now().subtract(const Duration(days: 30)),
        DateTime.now(),
      );

      progressNotifier.value = (
        current: 0,
        total: stockCodes.length,
        stage: '重新检测数据完整性...',
      );

      // 3. 重新检测所有股票
      await repository.findMissingMinuteDatesBatch(
        stockCodes: stockCodes,
        dateRange: dateRange,
        onProgress: (current, total) {
          progressNotifier.value = (
            current: current,
            total: total,
            stage: '重新检测数据完整性...',
          );
        },
      );

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已完成 ${stockCodes.length} 只股票的数据完整性检测')),
        );
        _triggerRefresh();
      }
    } catch (e) {
      debugPrint('[DataManagement] 重新检测失败: $e');
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检测失败: $e')));
      }
    } finally {
      progressNotifier.dispose();
    }
  }

  Future<void> _fetchHistoricalKline(BuildContext context) async {
    final klineService = context.read<HistoricalKlineService>();
    final marketProvider = context.read<MarketDataProvider>();
    final repository = context.read<DataRepository>();
    final trendService = context.read<IndustryTrendService>();
    final rankService = context.read<IndustryRankService>();

    if (marketProvider.allData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先刷新市场数据')));
      return;
    }

    // 显示进度对话框
    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备中...',
        ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(progressNotifier: progressNotifier),
    );

    // 阻止锁屏
    await WakelockPlus.enable();

    String? completionMessage;
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
      final fetchResult = await repository.fetchMissingData(
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

      // 0 条新增时，强制复检是否仍有缺失，防止“看起来成功但实际没拉到数据”。
      if (fetchResult.totalRecords == 0) {
        final tradingDays = await repository.getTradingDates(dateRange);
        if (!_hasReliableTradingDateCoverage(tradingDays, dateRange)) {
          final sampleCodes = stockCodes.length > 20
              ? stockCodes.sublist(0, 20)
              : stockCodes;
          final lastTradingStatus = await _evaluateLatestTradingDayStatus(
            repository: repository,
            stockCodes: sampleCodes,
          );
          final lastTradingDate = lastTradingStatus.lastTradingDate;

          if (lastTradingDate == null) {
            throw Exception('交易日基线不足，且未找到可验证的最近分钟K交易日');
          }

          final issueCount =
              lastTradingStatus.missingStocks +
              lastTradingStatus.incompleteStocks;
          if (issueCount > 0) {
            final issueParts = <String>[];
            if (lastTradingStatus.missingStocks > 0) {
              issueParts.add('缺失${lastTradingStatus.missingStocks}只');
            }
            if (lastTradingStatus.incompleteStocks > 0) {
              issueParts.add('不完整${lastTradingStatus.incompleteStocks}只');
            }
            throw Exception(
              '交易日基线不足，最近交易日(${_formatDate(lastTradingDate)})仍有问题：${issueParts.join('，')}',
            );
          }
        }

        progressNotifier.value = (
          current: 0,
          total: stockCodes.length,
          stage: '1/3 复检缺失状态',
        );

        final verifyResults = await repository.findMissingMinuteDatesBatch(
          stockCodes: stockCodes,
          dateRange: dateRange,
          onProgress: (current, total) {
            progressNotifier.value = (
              current: current,
              total: total,
              stage: '1/3 复检缺失状态',
            );
          },
        );

        final stillMissingStocks = verifyResults.values.where((result) {
          return result.missingDates.isNotEmpty ||
              result.incompleteDates.isNotEmpty;
        }).length;

        if (stillMissingStocks > 0) {
          throw Exception('拉取后仍有 $stillMissingStocks 只股票分钟K线缺失');
        }
      }

      if (fetchResult.failureCount > 0) {
        completionMessage =
            '历史数据已更新（${fetchResult.failureCount}/${fetchResult.totalStocks} 只拉取失败）';
      } else {
        completionMessage = '历史数据已更新';
      }

      // Get current data version for cache validation
      final dataVersion = await repository.getCurrentVersion();

      // 计算行业趋势和排名（数据来自 DataRepository）
      if (context.mounted) {
        debugPrint('[DataManagement] 开始计算行业趋势');
        progressNotifier.value = (current: 0, total: 1, stage: '2/3 计算行业趋势...');
        await trendService.recalculateFromKlineData(
          klineService,
          marketProvider.allData,
          dataVersion: dataVersion,
        );
        debugPrint('[DataManagement] 行业趋势计算完成');

        debugPrint('[DataManagement] 开始计算行业排名');
        progressNotifier.value = (current: 0, total: 1, stage: '3/3 计算行业排名...');
        await rankService.recalculateFromKlineData(
          klineService,
          marketProvider.allData,
          dataVersion: dataVersion,
        );
        debugPrint('[DataManagement] 行业排名计算完成');
      }
    } catch (e, stackTrace) {
      debugPrint('[DataManagement] 拉取历史数据失败: $e');
      debugPrint('$stackTrace');
      completionMessage = '历史数据拉取失败: $e';
    } finally {
      // 恢复锁屏
      await WakelockPlus.disable();

      // 关闭进度对话框
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(completionMessage ?? '历史数据未变化')));
        _triggerRefresh();
      }
      progressNotifier.dispose();
    }
  }

  bool _hasReliableTradingDateCoverage(
    List<DateTime> tradingDates,
    DateRange dateRange,
  ) {
    if (tradingDates.isEmpty) return false;

    final startDate = DateTime(
      dateRange.start.year,
      dateRange.start.month,
      dateRange.start.day,
    );
    final endDate = DateTime(
      dateRange.end.year,
      dateRange.end.month,
      dateRange.end.day,
    );
    final calendarDays = endDate.difference(startDate).inDays + 1;
    if (calendarDays <= 5) return true;

    final minExpectedTradingDates =
        (calendarDays * _minTradingDateCoverageRatio).ceil();
    return tradingDates.length >= minExpectedTradingDates;
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _normalizeDate(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  Future<
    ({
      DateTime? lastTradingDate,
      int completeStocks,
      int incompleteStocks,
      int missingStocks,
    })
  >
  _evaluateLatestTradingDayStatus({
    required DataRepository repository,
    required List<String> stockCodes,
  }) async {
    if (stockCodes.isEmpty) {
      return (
        lastTradingDate: null,
        completeStocks: 0,
        incompleteStocks: 0,
        missingStocks: 0,
      );
    }

    final now = DateTime.now();
    final probeRange = DateRange(
      now.subtract(const Duration(days: _latestTradingDayProbeDays)),
      now,
    );
    final klinesByStock = await repository.getKlines(
      stockCodes: stockCodes,
      dateRange: probeRange,
      dataType: KLineDataType.oneMinute,
    );

    DateTime? lastTradingDate;
    for (final bars in klinesByStock.values) {
      for (final bar in bars) {
        final dateOnly = _normalizeDate(bar.datetime);
        if (lastTradingDate == null || dateOnly.isAfter(lastTradingDate)) {
          lastTradingDate = dateOnly;
        }
      }
    }

    if (lastTradingDate == null) {
      return (
        lastTradingDate: null,
        completeStocks: 0,
        incompleteStocks: 0,
        missingStocks: stockCodes.length,
      );
    }

    var completeStocks = 0;
    var incompleteStocks = 0;
    var missingStocks = 0;

    for (final stockCode in stockCodes) {
      final bars = klinesByStock[stockCode] ?? const [];
      final barCount = bars
          .where((bar) => _normalizeDate(bar.datetime) == lastTradingDate)
          .length;

      if (barCount >= _minCompleteMinuteBars) {
        completeStocks++;
      } else if (barCount == 0) {
        missingStocks++;
      } else {
        incompleteStocks++;
      }
    }

    return (
      lastTradingDate: lastTradingDate,
      completeStocks: completeStocks,
      incompleteStocks: incompleteStocks,
      missingStocks: missingStocks,
    );
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
  final ValueNotifier<({int current, int total, String stage})>
  progressNotifier;

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
                value: isProcessing
                    ? null
                    : (progress.total > 0
                          ? progress.current / progress.total
                          : null),
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
