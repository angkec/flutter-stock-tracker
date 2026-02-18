import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/services/audit_service.dart';
import 'package:stock_rtwatcher/config/debug_config.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/adx_settings_screen.dart';
import 'package:stock_rtwatcher/screens/macd_settings_screen.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/widgets/data_management_audit_console.dart';

enum _WeeklySyncStage { precheck, fetch, write }

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key});

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  // 用于强制刷新 FutureBuilder
  int _refreshKey = 0;
  bool _isSyncingWeeklyKline = false;
  static const double _minTradingDateCoverageRatio = 0.3;
  static const int _minCompleteMinuteBars = 220;
  static const int _latestTradingDayProbeDays = 20;
  static const int _baselineFallbackFullCheckStockLimit = 500;
  static const int _baselineFallbackSampleSize = 60;
  static const int _weeklyTargetBars = 100;
  static const int _weeklyRangeDays = 760;
  static const int _weeklyMacdFetchBatchSize = 120;
  static const int _weeklyMacdPersistConcurrency = 8;
  static const int _weeklyAdxFetchBatchSize = 120;
  static const int _weeklyAdxPersistConcurrency = 8;

  void _triggerRefresh() {
    setState(() {
      _refreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '数据管理',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Consumer2<MarketDataProvider, AuditService>(
        builder: (_, provider, auditService, __) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              _buildSummaryCard(context, provider),
              const SizedBox(height: 12),
              _buildAuditConsole(context, auditService),
              const SizedBox(height: 12),

              _buildSectionTitle(context, '基础数据'),
              const SizedBox(height: 6),
              _buildDailyCacheItem(
                context,
                title: '日K数据',
                subtitle: '${provider.dailyBarsCacheCount}只股票',
                size: provider.dailyBarsCacheSize,
                statusLabel: provider.dailyBarsCacheCount > 0 ? '已缓存' : '待拉取',
                isReady: provider.dailyBarsCacheCount > 0,
                isBusy: provider.isLoading,
                onIncrementalFetch: () => _syncDailyIncremental(context),
                onForceFullFetch: () => _confirmForceRefetch(
                  context,
                  '日K数据（强制全量）',
                  () => _syncDailyForceFull(context),
                ),
              ),
              _buildCacheItem(
                context,
                title: '分时数据',
                subtitle: '${provider.minuteDataCacheCount}只股票',
                size: provider.minuteDataCacheSize,
                statusLabel: provider.minuteDataCacheCount > 0 ? '已缓存' : '待拉取',
                isReady: provider.minuteDataCacheCount > 0,
                isBusy: provider.isLoading,
                onForceRefetch: () => _confirmForceRefetch(
                  context,
                  '分时数据',
                  () => _forceRefetchMinuteData(context),
                ),
              ),
              _buildCacheItem(
                context,
                title: '行业数据',
                subtitle: provider.industryDataLoaded ? '已加载' : '未加载',
                size: provider.industryDataCacheSize,
                statusLabel: provider.industryDataLoaded ? '已加载' : '待拉取',
                isReady: provider.industryDataLoaded,
                isBusy: provider.isLoading,
                onForceRefetch: () => _confirmForceRefetch(
                  context,
                  '行业数据',
                  () => _forceRefetchIndustryData(context),
                ),
              ),
              Consumer<DataRepository>(
                builder: (context, repository, _) {
                  return FutureBuilder<({String subtitle, int missingStocks})>(
                    key: ValueKey('weekly_kline_$_refreshKey'),
                    future: _getWeeklyKlineStatus(repository, provider),
                    builder: (context, snapshot) {
                      final status =
                          snapshot.data ??
                          (subtitle: '加载中...', missingStocks: 0);
                      return _buildWeeklyKlineCacheItem(
                        context,
                        title: '周K数据',
                        subtitle: status.subtitle,
                        missingStocks: status.missingStocks,
                        isLoading: _isSyncingWeeklyKline,
                        onFetch: () => _fetchWeeklyKline(context),
                        onForceRefetch: () => _confirmForceRefetch(
                          context,
                          '周K数据',
                          () => _fetchWeeklyKline(context, forceRefetch: true),
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 10),
              _buildSectionTitle(context, '技术指标'),
              const SizedBox(height: 6),
              _buildMacdSettingsItem(context, dataType: KLineDataType.daily),
              _buildMacdSettingsItem(context, dataType: KLineDataType.weekly),
              _buildAdxSettingsItem(context, dataType: KLineDataType.daily),
              _buildAdxSettingsItem(context, dataType: KLineDataType.weekly),

              const SizedBox(height: 10),
              _buildSectionTitle(context, '历史分钟K线'),
              const SizedBox(height: 6),
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
                        size: '-',
                        missingDays: status.missingDays,
                        isLoading: false,
                        onFetch: () => _fetchHistoricalKline(context),
                        onForceRefetch: () => _confirmForceRefetch(
                          context,
                          '历史分钟K线',
                          () => _fetchHistoricalKline(
                            context,
                            forceRefetch: true,
                          ),
                        ),
                        onRecheck: () =>
                            _recheckDataFreshness(context, repository),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 16),
              if (provider.isLoading) ...[
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: Text(provider.stageDescription ?? '刷新中...'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: provider.isLoading
                      ? null
                      : () => provider.refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新数据'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, MarketDataProvider provider) {
    final dataDateText = provider.dataDate == null
        ? '数据日期未知'
        : '数据日期 ${_formatDate(provider.dataDate!)}';
    final updateTimeText = provider.updateTime == null
        ? '最近刷新：未记录'
        : '最近刷新：${provider.updateTime}';

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.storage_rounded),
        title: const Text('本地缓存概览'),
        subtitle: Text('$updateTimeText\n$dataDateText'),
        isThreeLine: true,
        trailing: Text(
          provider.totalCacheSizeFormatted,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildAuditConsole(BuildContext context, AuditService auditService) {
    final latest = auditService.latest;
    if (latest == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Latest Audit'),
          subtitle: const Text('暂无审计记录，执行一次数据管理操作后生成'),
          trailing: TextButton(
            onPressed: () => _exportRecentAudits(context, auditService),
            child: const Text('导出7天'),
          ),
        ),
      );
    }

    final reasonCodes = latest.reasonCodes;
    final verdict = latest.verdict.name.toUpperCase();
    final metrics =
        'errors ${latest.errorCount} · missing ${latest.missingCount} · '
        'incomplete ${latest.incompleteCount} · unknown ${latest.unknownStateCount} · '
        'elapsed ${latest.elapsedMs}ms';

    return DataManagementAuditConsole(
      title: 'Latest Audit',
      verdictLabel: verdict,
      operationLabel: latest.operation.wireName,
      completedAtLabel: _formatDateTime(latest.completedAt),
      reasonCodes: reasonCodes,
      metricsLabel: metrics,
      onViewDetails: () => _showAuditDetails(context, latest),
      onExportLatest: () => _exportLatestAudit(context, auditService),
      onExportRecent: () => _exportRecentAudits(context, auditService),
    );
  }

  Future<void> _exportLatestAudit(
    BuildContext context,
    AuditService auditService,
  ) async {
    final latest = auditService.latest;
    if (latest == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂无可导出的审计记录')));
      }
      return;
    }

    try {
      final file = await auditService.exporter.exportLatestRun(
        runId: latest.runId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('审计日志已导出: ${file.path}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出审计日志失败: $e')));
      }
    }
  }

  Future<void> _exportRecentAudits(
    BuildContext context,
    AuditService auditService,
  ) async {
    try {
      final file = await auditService.exporter.exportRecentDays(days: 7);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('近7天审计日志已导出: ${file.path}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出近7天审计日志失败: $e')));
      }
    }
  }

  Future<void> _showAuditDetails(
    BuildContext context,
    AuditRunSummary summary,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '审计详情',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text('Run: ${summary.runId}'),
              Text('操作: ${summary.operation.wireName}'),
              Text('完成: ${_formatDateTime(summary.completedAt)}'),
              Text('结论: ${summary.verdict.name.toUpperCase()}'),
              const SizedBox(height: 12),
              Text(
                '失败原因',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (summary.reasonCodes.isEmpty)
                const Text('无')
              else
                ...summary.reasonCodes.map((code) => Text('• $code')),
              const SizedBox(height: 12),
              Text(
                '指标',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'errors ${summary.errorCount}, missing ${summary.missingCount}, '
                'incomplete ${summary.incompleteCount}, unknown ${summary.unknownStateCount}',
              ),
              Text(
                'updated ${summary.updatedStockCount}, records ${summary.totalRecords}, '
                'elapsed ${summary.elapsedMs}ms',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  IconData _iconForCacheType(String title) {
    switch (title) {
      case '日K数据':
        return Icons.candlestick_chart;
      case '周K数据':
        return Icons.stacked_line_chart_rounded;
      case '分时数据':
        return Icons.show_chart_rounded;
      case '行业数据':
        return Icons.account_tree_outlined;
      case '历史分钟K线':
        return Icons.timeline_rounded;
      default:
        return Icons.dataset_outlined;
    }
  }

  Widget _buildCacheItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String? size,
    required String statusLabel,
    required bool isReady,
    required bool isBusy,
    required VoidCallback onForceRefetch,
  }) {
    final summary = '$subtitle · ${size ?? '-'} · $statusLabel';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(_iconForCacheType(title)),
        title: Text(title),
        subtitle: Text(summary),
        trailing: FilledButton.tonal(
          onPressed: isBusy ? null : onForceRefetch,
          child: const Text('强制拉取'),
        ),
      ),
    );
  }

  Widget _buildDailyCacheItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String? size,
    required String statusLabel,
    required bool isReady,
    required bool isBusy,
    required VoidCallback onIncrementalFetch,
    required VoidCallback onForceFullFetch,
  }) {
    final summary = '$subtitle · ${size ?? '-'} · $statusLabel';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(_iconForCacheType(title)),
        title: Text(title),
        subtitle: Text(summary),
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            FilledButton.tonal(
              onPressed: isBusy ? null : onIncrementalFetch,
              child: const Text('增量拉取'),
            ),
            FilledButton.tonal(
              onPressed: isBusy ? null : onForceFullFetch,
              child: const Text('强制全量拉取'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacdSettingsItem(
    BuildContext context, {
    required KLineDataType dataType,
  }) {
    final macdService = context.watch<MacdIndicatorService?>();
    final config = macdService?.configFor(dataType);
    final isWeekly = dataType == KLineDataType.weekly;
    final title = isWeekly ? '周线MACD参数设置' : '日线MACD参数设置';
    final summary = config == null
        ? '服务未初始化'
        : '快线${config.fastPeriod} · 慢线${config.slowPeriod} · 信号${config.signalPeriod} · ${config.windowMonths}个月';

    Future<void> navigateToSettings() async {
      if (macdService == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('MACD服务未初始化')));
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MacdSettingsScreen(dataType: dataType),
        ),
      );
      _triggerRefresh();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.auto_graph_rounded),
        title: Text(title),
        subtitle: Text(summary),
        trailing: FilledButton.tonal(
          onPressed: navigateToSettings,
          child: const Text('进入'),
        ),
        onTap: navigateToSettings,
      ),
    );
  }

  Widget _buildAdxSettingsItem(
    BuildContext context, {
    required KLineDataType dataType,
  }) {
    final adxService = context.watch<AdxIndicatorService?>();
    final config = adxService?.configFor(dataType);
    final isWeekly = dataType == KLineDataType.weekly;
    final title = isWeekly ? '周线ADX参数设置' : '日线ADX参数设置';
    final summary = config == null
        ? '服务未初始化'
        : '周期${config.period} · 阈值${config.threshold.toStringAsFixed(1)}';

    Future<void> navigateToSettings() async {
      if (adxService == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ADX服务未初始化')));
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AdxSettingsScreen(dataType: dataType),
        ),
      );
      _triggerRefresh();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.show_chart_rounded),
        title: Text(title),
        subtitle: Text(summary),
        trailing: FilledButton.tonal(
          onPressed: navigateToSettings,
          child: const Text('进入'),
        ),
        onTap: navigateToSettings,
      ),
    );
  }

  Widget _buildKlineActionButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    bool filled = false,
    bool enabled = true,
  }) {
    final style = Theme.of(context).textTheme.bodySmall;
    if (filled) {
      return FilledButton.tonal(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Text(label, style: style),
      );
    }

    return TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Text(label, style: style),
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
    required VoidCallback onForceRefetch,
    required VoidCallback onRecheck,
  }) {
    final dataComplete = missingDays <= 0;
    final statusLabel = dataComplete ? '数据完整' : '待补全 $missingDays';
    final summary = '$subtitle · $statusLabel';

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(_iconForCacheType(title)),
            title: Text(title),
            subtitle: Text(summary),
            trailing: dataComplete
                ? _buildKlineActionButton(
                    context: context,
                    label: '强制重拉',
                    onPressed: onForceRefetch,
                    filled: true,
                  )
                : _buildKlineActionButton(
                    context: context,
                    label: isLoading ? '拉取中...' : '拉取缺失',
                    onPressed: onFetch,
                    filled: true,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!dataComplete)
                  _buildKlineActionButton(
                    context: context,
                    label: '强制重拉',
                    onPressed: onForceRefetch,
                  ),
                _buildKlineActionButton(
                  context: context,
                  label: '重新检测',
                  onPressed: onRecheck,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyKlineCacheItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required int missingStocks,
    required bool isLoading,
    required VoidCallback onFetch,
    required VoidCallback onForceRefetch,
  }) {
    final dataComplete = missingStocks <= 0;
    final statusLabel = dataComplete ? '数据完整' : '待补全 $missingStocks只';
    final summary = '$subtitle · $statusLabel';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: Icon(_iconForCacheType(title)),
            title: Text(title),
            subtitle: Text(summary),
            trailing: _buildKlineActionButton(
              context: context,
              label: isLoading ? '拉取中...' : '拉取缺失',
              onPressed: onFetch,
              filled: true,
              enabled: !isLoading,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildKlineActionButton(
                  context: context,
                  label: '强制重拉',
                  onPressed: onForceRefetch,
                  enabled: !isLoading,
                ),
              ],
            ),
          ),
        ],
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

      // 交易日基线不足时优先全量核验（中小规模），避免“前序样本完整但整体缺失”的误报。
      final sampleCodes = _buildBaselineFallbackCheckCodes(allStockCodes);

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

  Future<({String subtitle, int missingStocks})> _getWeeklyKlineStatus(
    DataRepository repository,
    MarketDataProvider provider,
  ) async {
    if (provider.allData.isEmpty) {
      return (subtitle: '暂无数据', missingStocks: 0);
    }

    try {
      final allStockCodes = provider.allData.map((d) => d.stock.code).toList();
      final sampleCodes = _buildBaselineFallbackCheckCodes(allStockCodes);
      final dateRange = _buildWeeklyDateRange();

      final klinesByStock = await repository.getKlines(
        stockCodes: sampleCodes,
        dateRange: dateRange,
        dataType: KLineDataType.weekly,
      );

      var coveredStocks = 0;
      for (final stockCode in sampleCodes) {
        final bars = klinesByStock[stockCode] ?? const [];
        if (bars.length >= _weeklyTargetBars) {
          coveredStocks++;
        }
      }

      final missingStocks = sampleCodes.length - coveredStocks;
      final dateRangeStr =
          '${_formatDate(dateRange.start)} ~ ${_formatDate(dateRange.end)}';

      return (
        subtitle:
            '$dateRangeStr，覆盖 $coveredStocks/${sampleCodes.length}（目标 $_weeklyTargetBars 周）',
        missingStocks: missingStocks,
      );
    } catch (e) {
      debugPrint('[DataManagement] 获取周K状态失败: $e');
      return (subtitle: '状态未知', missingStocks: 0);
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

  Future<void> _fetchHistoricalKline(
    BuildContext context, {
    bool forceRefetch = false,
  }) async {
    final klineService = context.read<HistoricalKlineService>();
    final marketProvider = context.read<MarketDataProvider>();
    final repository = context.read<DataRepository>();
    final trendService = context.read<IndustryTrendService>();
    final rankService = context.read<IndustryRankService>();
    final auditService = context.read<AuditService>();

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
    String? baselineVerificationWarning;
    var hasVerifiedNoMissingAfterFetch = false;
    StreamSubscription<DataStatus>? statusSubscription;
    DateTime? lastAuditProgressAt;
    String? lastAuditProgressStage;
    var lastAuditProgressCurrent = -1;
    var lastAuditProgressTotal = -1;
    const auditProgressMinInterval = Duration(milliseconds: 400);

    bool shouldEmitAuditProgress(String stage, int current, int total) {
      final now = DateTime.now();
      final stageChanged = stage != lastAuditProgressStage;
      final totalChanged = total != lastAuditProgressTotal;
      final reachedEnd = current >= total;
      final progressed = current > lastAuditProgressCurrent;
      final reachedInterval =
          lastAuditProgressAt == null ||
          now.difference(lastAuditProgressAt!) >= auditProgressMinInterval;

      if (!(stageChanged ||
          totalChanged ||
          reachedEnd ||
          (progressed && reachedInterval))) {
        return false;
      }

      lastAuditProgressAt = now;
      lastAuditProgressStage = stage;
      lastAuditProgressCurrent = current;
      lastAuditProgressTotal = total;
      return true;
    }

    try {
      await auditService.runner.run(
        operation: AuditOperationType.historicalFetchMissing,
        body: (audit) async {
          audit.stageStarted(
            forceRefetch
                ? 'historical_force_refetch'
                : 'historical_fetch_missing',
          );
          var stocks = marketProvider.allData.map((d) => d.stock).toList();

          // Debug 模式下限制股票数量
          stocks = DebugConfig.limitStocks(stocks);

          final stockCodes = stocks.map((s) => s.code).toList();
          final dateRange = DateRange(
            DateTime.now().subtract(const Duration(days: 30)),
            DateTime.now(),
          );

          statusSubscription = repository.statusStream.listen((status) {
            if (status is! DataFetching) {
              return;
            }

            final safeTotal = status.total <= 0 ? 1 : status.total;
            final safeCurrent = status.current.clamp(0, safeTotal);

            if (status.currentStock == '__WRITE__') {
              progressNotifier.value = (
                current: safeCurrent,
                total: safeTotal,
                stage: '2/4 写入K线数据',
              );
              if (shouldEmitAuditProgress(
                'write_kline',
                safeCurrent,
                safeTotal,
              )) {
                audit.stageProgress(
                  'write_kline',
                  current: safeCurrent,
                  total: safeTotal,
                );
              }
              return;
            }

            progressNotifier.value = (
              current: safeCurrent,
              total: safeTotal,
              stage: forceRefetch ? '1/4 强制拉取K线数据' : '1/4 拉取K线数据',
            );
            if (shouldEmitAuditProgress(
              'fetch_kline',
              safeCurrent,
              safeTotal,
            )) {
              audit.stageProgress(
                'fetch_kline',
                current: safeCurrent,
                total: safeTotal,
              );
            }
          });

          debugPrint(
            '[DataManagement] 开始${forceRefetch ? '强制' : ''}拉取历史数据, ${stockCodes.length} 只股票',
          );
          final fetchResult = forceRefetch
              ? await repository.refetchData(
                  stockCodes: stockCodes,
                  dateRange: dateRange,
                  dataType: KLineDataType.oneMinute,
                  onProgress: (current, total) {
                    final safeTotal = total <= 0 ? 1 : total;
                    final safeCurrent = current.clamp(0, safeTotal);
                    progressNotifier.value = (
                      current: safeCurrent,
                      total: safeTotal,
                      stage: '1/4 强制拉取K线数据',
                    );
                    if (shouldEmitAuditProgress(
                      'fetch_kline',
                      safeCurrent,
                      safeTotal,
                    )) {
                      audit.stageProgress(
                        'fetch_kline',
                        current: safeCurrent,
                        total: safeTotal,
                      );
                    }
                  },
                )
              : await repository.fetchMissingData(
                  stockCodes: stockCodes,
                  dateRange: dateRange,
                  dataType: KLineDataType.oneMinute,
                  onProgress: (current, total) {
                    final safeTotal = total <= 0 ? 1 : total;
                    final safeCurrent = current.clamp(0, safeTotal);
                    progressNotifier.value = (
                      current: safeCurrent,
                      total: safeTotal,
                      stage: '1/4 拉取K线数据',
                    );
                    if (shouldEmitAuditProgress(
                      'fetch_kline',
                      safeCurrent,
                      safeTotal,
                    )) {
                      audit.stageProgress(
                        'fetch_kline',
                        current: safeCurrent,
                        total: safeTotal,
                      );
                    }
                  },
                );
          debugPrint('[DataManagement] K线数据已保存');
          audit.record(AuditEventType.fetchResult, {
            'updated_stock_count': fetchResult.successCount,
            'total_records': fetchResult.totalRecords,
            'failure_count': fetchResult.failureCount,
          });

          // 0 条新增时，强制复检是否仍有缺失，防止“看起来成功但实际没拉到数据”。
          if (!forceRefetch && fetchResult.totalRecords == 0) {
            final tradingDays = await repository.getTradingDates(dateRange);
            if (!_hasReliableTradingDateCoverage(tradingDays, dateRange)) {
              final sampleCodes = _buildBaselineFallbackCheckCodes(stockCodes);
              final lastTradingStatus = await _evaluateLatestTradingDayStatus(
                repository: repository,
                stockCodes: sampleCodes,
              );
              final lastTradingDate = lastTradingStatus.lastTradingDate;

              if (lastTradingDate == null) {
                baselineVerificationWarning = '交易日基线不足，最近分钟K交易日暂不可验证，建议交易日复检';
                debugPrint('[DataManagement] $baselineVerificationWarning');
              }

              if (lastTradingDate != null) {
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
            }

            progressNotifier.value = (
              current: 0,
              total: stockCodes.length,
              stage: '2/4 复检缺失状态',
            );

            final verifyResults = await repository.findMissingMinuteDatesBatch(
              stockCodes: stockCodes,
              dateRange: dateRange,
              onProgress: (current, total) {
                final safeTotal = total <= 0 ? 1 : total;
                final safeCurrent = current.clamp(0, safeTotal);
                progressNotifier.value = (
                  current: safeCurrent,
                  total: safeTotal,
                  stage: '2/4 复检缺失状态',
                );
                if (shouldEmitAuditProgress(
                  'verify_missing',
                  safeCurrent,
                  safeTotal,
                )) {
                  audit.stageProgress(
                    'verify_missing',
                    current: safeCurrent,
                    total: safeTotal,
                  );
                }
              },
            );

            final stillMissingStocks = verifyResults.values.where((result) {
              return result.missingDates.isNotEmpty ||
                  result.incompleteDates.isNotEmpty;
            }).length;
            final stillIncompleteStocks = verifyResults.values.where((result) {
              return result.incompleteDates.isNotEmpty;
            }).length;

            audit.record(AuditEventType.verificationResult, {
              'missing_count': stillMissingStocks,
              'incomplete_count': stillIncompleteStocks,
            });

            if (stillMissingStocks > 0) {
              throw Exception('拉取后仍有 $stillMissingStocks 只股票分钟K线缺失');
            }

            hasVerifiedNoMissingAfterFetch = true;
          }

          if (fetchResult.failureCount > 0) {
            completionMessage =
                '${forceRefetch ? '历史数据已强制更新' : '历史数据已更新'}（${fetchResult.failureCount}/${fetchResult.totalStocks} 只拉取失败）';
          } else {
            completionMessage = forceRefetch ? '历史数据已强制更新' : '历史数据已更新';
          }
          if (baselineVerificationWarning != null &&
              !hasVerifiedNoMissingAfterFetch) {
            completionMessage =
                '$completionMessage；$baselineVerificationWarning';
          }

          final shouldRecalculateIndustry =
              forceRefetch || fetchResult.totalRecords > 0;
          if (shouldRecalculateIndustry) {
            // Get current data version for cache validation
            final dataVersion = await repository.getCurrentVersion();
            audit.record(AuditEventType.indicatorRecomputeResult, {
              'data_changed': true,
              'scope_count': stockCodes.length,
            });

            // 计算行业趋势和排名（数据来自 DataRepository）
            if (context.mounted) {
              final industryCalcStopwatch = Stopwatch()..start();

              debugPrint('[DataManagement] 开始计算行业趋势');
              progressNotifier.value = (
                current: 0,
                total: 1,
                stage: '3/4 计算行业趋势...',
              );
              audit.stageStarted('recompute_industry_trend');
              final trendStopwatch = Stopwatch()..start();
              await trendService.recalculateFromKlineData(
                klineService,
                marketProvider.allData,
                dataVersion: dataVersion,
              );
              trendStopwatch.stop();
              audit.stageCompleted(
                'recompute_industry_trend',
                durationMs: trendStopwatch.elapsedMilliseconds,
              );
              debugPrint('[DataManagement] 行业趋势计算完成');
              debugPrint(
                '[DataManagement][timing] trendMs=${trendStopwatch.elapsedMilliseconds}',
              );

              debugPrint('[DataManagement] 开始计算行业排名');
              progressNotifier.value = (
                current: 0,
                total: 1,
                stage: '4/4 计算行业排名...',
              );
              audit.stageStarted('recompute_industry_rank');
              final rankStopwatch = Stopwatch()..start();
              await rankService.recalculateFromKlineData(
                klineService,
                marketProvider.allData,
                dataVersion: dataVersion,
              );
              rankStopwatch.stop();
              audit.stageCompleted(
                'recompute_industry_rank',
                durationMs: rankStopwatch.elapsedMilliseconds,
              );
              debugPrint('[DataManagement] 行业排名计算完成');
              industryCalcStopwatch.stop();
              debugPrint(
                '[DataManagement][timing] rankMs=${rankStopwatch.elapsedMilliseconds}, '
                'industryCalcTotalMs=${industryCalcStopwatch.elapsedMilliseconds}',
              );
            }
          } else {
            debugPrint('[DataManagement] 历史分钟K无新增记录，跳过行业趋势/排名重算以缩短等待时间');
            audit.record(AuditEventType.indicatorRecomputeResult, {
              'data_changed': false,
              'scope_count': 0,
            });
          }
          audit.stageCompleted(
            forceRefetch
                ? 'historical_force_refetch'
                : 'historical_fetch_missing',
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint('[DataManagement] 拉取历史数据失败: $e');
      debugPrint('$stackTrace');
      completionMessage = '历史数据拉取失败: $e';
    } finally {
      await statusSubscription?.cancel();
      await _refreshAuditLatestSafely(auditService);

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

  DateRange _buildWeeklyDateRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999);
    final start = end.subtract(const Duration(days: _weeklyRangeDays));
    return DateRange(start, end);
  }

  Future<void> _fetchWeeklyKline(
    BuildContext context, {
    bool forceRefetch = false,
  }) async {
    final marketProvider = context.read<MarketDataProvider>();
    final repository = context.read<DataRepository>();
    final macdService = context.read<MacdIndicatorService?>();
    final adxService = context.read<AdxIndicatorService?>();
    final auditService = context.read<AuditService>();

    if (marketProvider.allData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先刷新市场数据')));
      return;
    }

    setState(() {
      _isSyncingWeeklyKline = true;
    });

    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备拉取周K数据...',
        ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(progressNotifier: progressNotifier),
    );

    await WakelockPlus.enable();

    StreamSubscription<DataStatus>? statusSubscription;
    StreamSubscription<DataUpdatedEvent>? updatedSubscription;
    String completionMessage = forceRefetch ? '周K数据已强制更新' : '周K数据已更新';
    DateTime? lastAuditProgressAt;
    String? lastAuditProgressStage;
    var lastAuditProgressCurrent = -1;
    var lastAuditProgressTotal = -1;
    const auditProgressMinInterval = Duration(milliseconds: 400);

    bool shouldEmitAuditProgress(String stage, int current, int total) {
      final now = DateTime.now();
      final stageChanged = stage != lastAuditProgressStage;
      final totalChanged = total != lastAuditProgressTotal;
      final reachedEnd = current >= total;
      final progressed = current > lastAuditProgressCurrent;
      final reachedInterval =
          lastAuditProgressAt == null ||
          now.difference(lastAuditProgressAt!) >= auditProgressMinInterval;

      if (!(stageChanged ||
          totalChanged ||
          reachedEnd ||
          (progressed && reachedInterval))) {
        return false;
      }

      lastAuditProgressAt = now;
      lastAuditProgressStage = stage;
      lastAuditProgressCurrent = current;
      lastAuditProgressTotal = total;
      return true;
    }

    try {
      await auditService.runner.run(
        operation: forceRefetch
            ? AuditOperationType.weeklyForceRefetch
            : AuditOperationType.weeklyFetchMissing,
        body: (audit) async {
          audit.stageStarted(
            forceRefetch ? 'weekly_force_refetch' : 'weekly_fetch_missing',
          );
          var stocks = marketProvider.allData.map((d) => d.stock).toList();
          stocks = DebugConfig.limitStocks(stocks);
          final stockCodes = stocks.map((s) => s.code).toList();
          final dateRange = _buildWeeklyDateRange();

          final stageDurations = <_WeeklySyncStage, Duration>{
            _WeeklySyncStage.precheck: Duration.zero,
            _WeeklySyncStage.fetch: Duration.zero,
            _WeeklySyncStage.write: Duration.zero,
          };
          final stageProgressCurrent = <_WeeklySyncStage, int>{
            _WeeklySyncStage.precheck: 0,
            _WeeklySyncStage.fetch: 0,
            _WeeklySyncStage.write: 0,
          };
          final stageProgressTotal = <_WeeklySyncStage, int>{
            _WeeklySyncStage.precheck: 1,
            _WeeklySyncStage.fetch: 1,
            _WeeklySyncStage.write: 1,
          };
          _WeeklySyncStage? activeStage;
          DateTime? activeStageStartedAt;
          var activeStageStartProgress = 0;
          final updatedWeeklyStockCodes = <String>{};

          Duration elapsedForStage(_WeeklySyncStage stage, DateTime now) {
            final base = stageDurations[stage] ?? Duration.zero;
            if (activeStage == stage && activeStageStartedAt != null) {
              return base + now.difference(activeStageStartedAt!);
            }
            return base;
          }

          String formatStageDuration(Duration duration) {
            final seconds = duration.inMilliseconds / 1000;
            return '${seconds.toStringAsFixed(1)}s';
          }

          _WeeklySyncStage resolveStage(String currentStock) {
            if (currentStock == '__PRECHECK__') {
              return _WeeklySyncStage.precheck;
            }
            if (currentStock == '__WRITE__') {
              return _WeeklySyncStage.write;
            }
            return _WeeklySyncStage.fetch;
          }

          void switchToStage(_WeeklySyncStage nextStage, int progressCurrent) {
            final now = DateTime.now();
            if (activeStage == nextStage) {
              return;
            }

            if (activeStage != null && activeStageStartedAt != null) {
              stageDurations[activeStage!] =
                  (stageDurations[activeStage!] ?? Duration.zero) +
                  now.difference(activeStageStartedAt!);
            }

            activeStage = nextStage;
            activeStageStartedAt = now;
            activeStageStartProgress = progressCurrent;
          }

          String buildStageMetrics(int current, int total) {
            final now = DateTime.now();
            final precheckElapsed = elapsedForStage(
              _WeeklySyncStage.precheck,
              now,
            );
            final fetchElapsed = elapsedForStage(_WeeklySyncStage.fetch, now);
            final writeElapsed = elapsedForStage(_WeeklySyncStage.write, now);

            String formatStageProgress(_WeeklySyncStage stage) {
              final progressCurrent = stageProgressCurrent[stage] ?? 0;
              final progressTotal = stageProgressTotal[stage] ?? 1;
              return '$progressCurrent/$progressTotal';
            }

            var speedLabel = '--';
            if (activeStage != null) {
              final activeElapsed = elapsedForStage(activeStage!, now);
              final processedInStage = (current - activeStageStartProgress)
                  .clamp(0, total);
              final seconds = activeElapsed.inMilliseconds / 1000;
              if (seconds > 0) {
                speedLabel =
                    '${(processedInStage / seconds).toStringAsFixed(1)}项/秒';
              } else {
                speedLabel = '0.0项/秒';
              }
            }

            return '阶段耗时 预检 ${formatStageDuration(precheckElapsed)} · '
                '拉取 ${formatStageDuration(fetchElapsed)} · '
                '写入 ${formatStageDuration(writeElapsed)}\n'
                '阶段进度 预检 ${formatStageProgress(_WeeklySyncStage.precheck)} · '
                '拉取 ${formatStageProgress(_WeeklySyncStage.fetch)} · '
                '写入 ${formatStageProgress(_WeeklySyncStage.write)} · '
                '速率 $speedLabel';
          }

          statusSubscription = repository.statusStream.listen((status) {
            if (status is! DataFetching) {
              return;
            }

            final safeTotal = status.total <= 0 ? 1 : status.total;
            final safeCurrent = status.current.clamp(0, safeTotal);
            final stage = resolveStage(status.currentStock);
            stageProgressCurrent[stage] = safeCurrent;
            stageProgressTotal[stage] = safeTotal;
            switchToStage(stage, safeCurrent);
            final stageTitle = stage == _WeeklySyncStage.precheck
                ? '预检查周K覆盖...'
                : stage == _WeeklySyncStage.write
                ? '写入周K数据...'
                : (forceRefetch ? '强制拉取周K数据...' : '拉取周K数据...');

            progressNotifier.value = (
              current: safeCurrent,
              total: safeTotal,
              stage:
                  '$stageTitle\n${buildStageMetrics(safeCurrent, safeTotal)}',
            );
            if (shouldEmitAuditProgress(stageTitle, safeCurrent, safeTotal)) {
              audit.stageProgress(
                stageTitle,
                current: safeCurrent,
                total: safeTotal,
              );
            }
          });
          updatedSubscription = repository.dataUpdatedStream.listen((event) {
            if (event.dataType == KLineDataType.weekly) {
              updatedWeeklyStockCodes.addAll(event.stockCodes);
            }
          });

          final fetchResult = forceRefetch
              ? await repository.refetchData(
                  stockCodes: stockCodes,
                  dateRange: dateRange,
                  dataType: KLineDataType.weekly,
                )
              : await repository.fetchMissingData(
                  stockCodes: stockCodes,
                  dateRange: dateRange,
                  dataType: KLineDataType.weekly,
                );
          audit.record(AuditEventType.fetchResult, {
            'updated_stock_count': fetchResult.successCount,
            'total_records': fetchResult.totalRecords,
            'failure_count': fetchResult.failureCount,
          });

          if (fetchResult.failureCount > 0) {
            completionMessage =
                '${forceRefetch ? '周K数据已强制更新' : '周K数据已更新'}（${fetchResult.failureCount}/${fetchResult.totalStocks} 只拉取失败）';
          }

          final shouldPrewarmWeeklyIndicators =
              (macdService != null || adxService != null) &&
              (forceRefetch || fetchResult.totalRecords > 0);
          if (shouldPrewarmWeeklyIndicators) {
            final prewarmStockCodes = forceRefetch
                ? stockCodes
                : stockCodes
                      .where((code) => updatedWeeklyStockCodes.contains(code))
                      .toList(growable: false);
            final effectivePrewarmStockCodes = prewarmStockCodes.isNotEmpty
                ? prewarmStockCodes
                : stockCodes;
            audit.record(AuditEventType.indicatorRecomputeResult, {
              'data_changed': true,
              'scope_count': effectivePrewarmStockCodes.length,
            });

            Future<void> prewarmWithProgress({
              required String preparingLabel,
              required String workingLabel,
              required String stageKey,
              required Future<void> Function(
                void Function(int current, int total)? onProgress,
              )
              action,
            }) async {
              progressNotifier.value = (
                current: 0,
                total: 1,
                stage:
                    '$preparingLabel（${effectivePrewarmStockCodes.length}只）...',
              );
              final prewarmStopwatch = Stopwatch()..start();
              await action((current, total) {
                final safeTotal = total <= 0 ? 1 : total;
                final safeCurrent = current.clamp(0, safeTotal);
                final elapsedSeconds =
                    prewarmStopwatch.elapsedMilliseconds / 1000;
                final speed = elapsedSeconds <= 0
                    ? 0.0
                    : safeCurrent / elapsedSeconds;
                final remaining = safeTotal - safeCurrent;
                final etaLabel = speed <= 0
                    ? '--'
                    : _formatEtaSeconds((remaining / speed).ceil());

                progressNotifier.value = (
                  current: safeCurrent,
                  total: safeTotal,
                  stage:
                      '$workingLabel...\n'
                      '速率 ${speed.toStringAsFixed(1)}只/秒 · 预计剩余 $etaLabel',
                );
                if (shouldEmitAuditProgress(stageKey, safeCurrent, safeTotal)) {
                  audit.stageProgress(
                    stageKey,
                    current: safeCurrent,
                    total: safeTotal,
                  );
                }
              });
            }

            if (macdService != null) {
              await prewarmWithProgress(
                preparingLabel: '准备更新周线MACD缓存',
                workingLabel: '更新周线MACD缓存',
                stageKey: 'weekly_macd_prewarm',
                action: (onProgress) {
                  return macdService.prewarmFromRepository(
                    stockCodes: effectivePrewarmStockCodes,
                    dataType: KLineDataType.weekly,
                    dateRange: dateRange,
                    fetchBatchSize: _weeklyMacdFetchBatchSize,
                    maxConcurrentPersistWrites: _weeklyMacdPersistConcurrency,
                    onProgress: onProgress,
                  );
                },
              );
            }

            if (adxService != null) {
              await prewarmWithProgress(
                preparingLabel: '准备更新周线ADX缓存',
                workingLabel: '更新周线ADX缓存',
                stageKey: 'weekly_adx_prewarm',
                action: (onProgress) {
                  return adxService.prewarmFromRepository(
                    stockCodes: effectivePrewarmStockCodes,
                    dataType: KLineDataType.weekly,
                    dateRange: dateRange,
                    fetchBatchSize: _weeklyAdxFetchBatchSize,
                    maxConcurrentPersistWrites: _weeklyAdxPersistConcurrency,
                    onProgress: onProgress,
                  );
                },
              );
            }
          } else {
            audit.record(AuditEventType.indicatorRecomputeResult, {
              'data_changed': false,
              'scope_count': 0,
            });
          }
          audit.stageCompleted(
            forceRefetch ? 'weekly_force_refetch' : 'weekly_fetch_missing',
          );
        },
      );
    } catch (e) {
      completionMessage = '周K数据拉取失败: $e';
      debugPrint('[DataManagement] 拉取周K数据失败: $e');
    } finally {
      await statusSubscription?.cancel();
      await updatedSubscription?.cancel();
      await _refreshAuditLatestSafely(auditService);
      await WakelockPlus.disable();

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(completionMessage)));
        _triggerRefresh();
      }
      progressNotifier.dispose();

      if (mounted) {
        setState(() {
          _isSyncingWeeklyKline = false;
        });
      }
    }
  }

  String _formatEtaSeconds(int seconds) {
    if (seconds <= 0) {
      return '0s';
    }
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}m${remainingSeconds.toString().padLeft(2, '0')}s';
  }

  Future<void> _forceRefetchMinuteData(BuildContext context) async {
    final provider = context.read<MarketDataProvider>();
    try {
      await provider.refresh(forceMinuteRefetch: true);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分时数据已强制重新拉取')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分时数据强制拉取失败: $e')));
      }
    }
  }

  Future<void> _syncDailyIncremental(BuildContext context) async {
    await _runDailySync(context, forceFull: false);
  }

  Future<void> _syncDailyForceFull(BuildContext context) async {
    await _runDailySync(context, forceFull: true);
  }

  Future<void> _runDailySync(
    BuildContext context, {
    required bool forceFull,
  }) async {
    final provider = context.read<MarketDataProvider>();
    final auditService = context.read<AuditService>();
    if (provider.allData.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先刷新市场数据')));
      return;
    }

    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备拉取日K数据...',
        ));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(progressNotifier: progressNotifier),
    );

    await WakelockPlus.enable();

    DateTime? writeStageStartedAt;
    var writeStageStartProgress = 0;
    DateTime? lastAuditProgressAt;
    String? lastAuditProgressStage;
    var lastAuditProgressCurrent = -1;
    var lastAuditProgressTotal = -1;
    const auditProgressMinInterval = Duration(milliseconds: 400);
    final operation = forceFull
        ? AuditOperationType.dailyForceRefetch
        : AuditOperationType.dailyFetchIncremental;
    final stageLabel = forceFull
        ? 'daily_force_refetch'
        : 'daily_fetch_incremental';

    bool shouldEmitAuditProgress(String stage, int current, int total) {
      final now = DateTime.now();
      final stageChanged = stage != lastAuditProgressStage;
      final totalChanged = total != lastAuditProgressTotal;
      final reachedEnd = current >= total;
      final progressed = current > lastAuditProgressCurrent;
      final reachedInterval =
          lastAuditProgressAt == null ||
          now.difference(lastAuditProgressAt!) >= auditProgressMinInterval;

      if (!(stageChanged ||
          totalChanged ||
          reachedEnd ||
          (progressed && reachedInterval))) {
        return false;
      }

      lastAuditProgressAt = now;
      lastAuditProgressStage = stage;
      lastAuditProgressCurrent = current;
      lastAuditProgressTotal = total;
      return true;
    }

    try {
      await auditService.runner.run(
        operation: operation,
        body: (audit) async {
          audit.stageStarted(stageLabel);
          final syncRunner = forceFull
              ? provider.syncDailyBarsForceFull
              : provider.syncDailyBarsIncremental;
          await syncRunner(
            onProgress: (stage, current, total) {
              final safeTotal = total <= 0 ? 1 : total;
              final safeCurrent = current.clamp(0, safeTotal);
              var stageLabel = stage;

              if (stage.startsWith('2/4 写入日K文件')) {
                final now = DateTime.now();
                writeStageStartedAt ??= now;
                if (writeStageStartProgress <= 0) {
                  writeStageStartProgress = safeCurrent;
                }

                final elapsedMs = now
                    .difference(writeStageStartedAt!)
                    .inMilliseconds;
                var speedLabel = '--';
                if (elapsedMs > 0) {
                  final processed = (safeCurrent - writeStageStartProgress + 1)
                      .clamp(0, safeTotal);
                  final speed = processed / (elapsedMs / 1000);
                  speedLabel = '${speed.toStringAsFixed(1)}股/秒';
                }
                stageLabel = '$stage · 速率 $speedLabel';
              } else {
                writeStageStartedAt = null;
                writeStageStartProgress = 0;
              }

              progressNotifier.value = (
                current: safeCurrent,
                total: safeTotal,
                stage: stageLabel,
              );
              if (shouldEmitAuditProgress(stage, safeCurrent, safeTotal)) {
                audit.stageProgress(
                  stage,
                  current: safeCurrent,
                  total: safeTotal,
                );
              }
            },
          );
          audit.record(AuditEventType.fetchResult, {
            'updated_stock_count': provider.dailyBarsCacheCount,
            'total_records': 0,
            'failure_count': 0,
          });
          audit.record(AuditEventType.indicatorRecomputeResult, {
            'data_changed': true,
            'scope_count': provider.allData.length,
          });
          audit.record(AuditEventType.completenessState, {
            'state': provider.lastDailySyncCompletenessStateWire,
          });
          audit.stageCompleted(stageLabel);
        },
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(forceFull ? '日K数据已强制全量拉取' : '日K数据已增量拉取')),
        );
        _triggerRefresh();
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(forceFull ? '日K数据强制全量拉取失败: $e' : '日K数据增量拉取失败: $e'),
          ),
        );
      }
    } finally {
      await _refreshAuditLatestSafely(auditService);
      await WakelockPlus.disable();
      progressNotifier.dispose();
    }
  }

  Future<void> _refreshAuditLatestSafely(AuditService auditService) async {
    try {
      await auditService.refreshLatest();
    } catch (error) {
      debugPrint('[DataManagement] refresh latest audit failed: $error');
    }
  }

  Future<void> _forceRefetchIndustryData(BuildContext context) async {
    final provider = context.read<MarketDataProvider>();
    try {
      await provider.forceReloadIndustryData();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('行业数据已强制重新拉取')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('行业数据强制拉取失败: $e')));
      }
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

  String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} '
        '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')}:'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  DateTime _normalizeDate(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  List<String> _buildBaselineFallbackCheckCodes(List<String> allStockCodes) {
    if (allStockCodes.length <= _baselineFallbackFullCheckStockLimit) {
      return allStockCodes;
    }
    return _buildUniformSample(allStockCodes, _baselineFallbackSampleSize);
  }

  List<String> _buildUniformSample(List<String> source, int sampleSize) {
    if (source.length <= sampleSize) return source;
    if (sampleSize <= 0) return const <String>[];
    if (sampleSize == 1) return <String>[source.first];

    final sampled = <String>[];
    final usedIndexes = <int>{};
    for (var i = 0; i < sampleSize; i++) {
      final index = ((i * (source.length - 1)) / (sampleSize - 1)).round();
      if (usedIndexes.add(index)) {
        sampled.add(source[index]);
      }
    }

    if (sampled.length < sampleSize) {
      for (var i = 0; i < source.length && sampled.length < sampleSize; i++) {
        if (usedIndexes.add(i)) {
          sampled.add(source[i]);
        }
      }
    }
    return sampled;
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

  void _confirmForceRefetch(
    BuildContext context,
    String title,
    Future<void> Function() onForceRefetch,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认强制拉取'),
        content: Text('确定要强制重新拉取$title吗？这将覆盖现有缓存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await onForceRefetch();
              if (context.mounted) {
                _triggerRefresh();
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _ProgressDialog extends StatefulWidget {
  final ValueNotifier<({int current, int total, String stage})>
  progressNotifier;

  const _ProgressDialog({required this.progressNotifier});

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  static const Duration _idleHintThreshold = Duration(seconds: 5);

  late String _lastBusinessSignal;
  int _idleSeconds = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _lastBusinessSignal = _buildBusinessSignal(widget.progressNotifier.value);
    widget.progressNotifier.addListener(_onProgressChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _idleSeconds++;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.progressNotifier.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onProgressChanged() {
    final signal = _buildBusinessSignal(widget.progressNotifier.value);
    if (signal != _lastBusinessSignal) {
      _lastBusinessSignal = signal;
      _idleSeconds = 0;
    }

    if (mounted) {
      setState(() {});
    }
  }

  String _buildBusinessSignal(
    ({int current, int total, String stage}) progress,
  ) {
    return '${progress.stage}|${progress.current}|${progress.total}';
  }

  @override
  Widget build(BuildContext context) {
    final showIdleHint = _idleSeconds > _idleHintThreshold.inSeconds;
    final idleHint = '已等待 ${_idleSeconds}s，正在处理，请稍候...';

    return AlertDialog(
      title: const Text('拉取历史数据'),
      content: ValueListenableBuilder<({int current, int total, String stage})>(
        valueListenable: widget.progressNotifier,
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
              if (showIdleHint)
                Text(idleHint, style: Theme.of(context).textTheme.bodySmall),
              if (showIdleHint) const SizedBox(height: 8),
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
