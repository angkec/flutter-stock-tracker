import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/power_system_indicator_service.dart';

class PowerSystemCacheManagementScreen extends StatefulWidget {
  const PowerSystemCacheManagementScreen({super.key});

  @override
  State<PowerSystemCacheManagementScreen> createState() =>
      _PowerSystemCacheManagementScreenState();
}

class _PowerSystemCacheManagementScreenState
    extends State<PowerSystemCacheManagementScreen> {
  bool _isRecomputingDaily = false;
  bool _isRecomputingWeekly = false;
  bool _isApplyingMark = false;

  DateRange _buildDateRange(KLineDataType dataType) {
    const weeklyRangeDays = 760;
    const dailyRangeDays = 400;
    final end = DateTime.now();
    final start = end.subtract(
      Duration(
        days: dataType == KLineDataType.weekly
            ? weeklyRangeDays
            : dailyRangeDays,
      ),
    );
    return DateRange(start, end);
  }

  Future<void> _recomputeDaily() async {
    if (_isRecomputingDaily) return;

    final provider = context.read<MarketDataProvider>();
    final powerSystemService = context.read<PowerSystemIndicatorService>();
    final stockCodes = provider.allData
        .map((item) => item.stock.code)
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (stockCodes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先刷新市场数据')));
      return;
    }

    setState(() => _isRecomputingDaily = true);

    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备重算日线 Power System...',
        ));

    _showProgressDialog(
      title: '重算日线 Power System',
      progressNotifier: progressNotifier,
    );

    try {
      await powerSystemService.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.daily,
        dateRange: _buildDateRange(KLineDataType.daily),
        forceRecompute: true,
        onProgress: (current, total) {
          progressNotifier.value = (
            current: current,
            total: total,
            stage: '正在重算日线... $current/$total',
          );
        },
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日线 Power System 重算完成')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('日线 Power System 重算失败: $e')));
      }
    } finally {
      progressNotifier.dispose();
      if (mounted) setState(() => _isRecomputingDaily = false);
    }
  }

  Future<void> _recomputeWeekly() async {
    if (_isRecomputingWeekly) return;

    final provider = context.read<MarketDataProvider>();
    final powerSystemService = context.read<PowerSystemIndicatorService>();
    final stockCodes = provider.allData
        .map((item) => item.stock.code)
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (stockCodes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先刷新市场数据')));
      return;
    }

    setState(() => _isRecomputingWeekly = true);

    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备重算周线 Power System...',
        ));

    _showProgressDialog(
      title: '重算周线 Power System',
      progressNotifier: progressNotifier,
    );

    try {
      await powerSystemService.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: _buildDateRange(KLineDataType.weekly),
        forceRecompute: true,
        onProgress: (current, total) {
          progressNotifier.value = (
            current: current,
            total: total,
            stage: '正在重算周线... $current/$total',
          );
        },
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('周线 Power System 重算完成')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('周线 Power System 重算失败: $e')));
      }
    } finally {
      progressNotifier.dispose();
      if (mounted) setState(() => _isRecomputingWeekly = false);
    }
  }

  Future<void> _applyMarking() async {
    if (_isApplyingMark) return;

    final provider = context.read<MarketDataProvider>();

    setState(() => _isApplyingMark = true);

    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备应用标记...',
        ));

    _showProgressDialog(title: '应用双涨标记', progressNotifier: progressNotifier);

    try {
      await provider.recalculatePowerSystemUp(
        onProgress: (current, total) {
          progressNotifier.value = (
            current: current,
            total: total,
            stage: '正在检测双涨标记... $current/$total',
          );
        },
      );

      // Count how many stocks have the mark
      final markedCount = provider.allData
          .where((d) => d.isPowerSystemUp)
          .length;

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('双涨标记应用完成: $markedCount 只股票标记')));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('双涨标记应用失败: $e')));
      }
    } finally {
      progressNotifier.dispose();
      if (mounted) setState(() => _isApplyingMark = false);
    }
  }

  void _showProgressDialog({
    required String title,
    required ValueNotifier<({int current, int total, String stage})>
    progressNotifier,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ProgressDialog(title: title, progressNotifier: progressNotifier),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('动力系统标注管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          // 说明卡片
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '动力系统双涨标记',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当日线 Power System 和周线 Power System 同时为上涨状态（state=1）时，股票列表显示紫色 ▲ 标记。\n\n操作流程：\n1. 先重算日线动力系统\n2. 再重算周线动力系统\n3. 最后应用双涨标记',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 重算日线按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed:
                  _isRecomputingDaily || _isRecomputingWeekly || _isApplyingMark
                  ? null
                  : _recomputeDaily,
              icon: _isRecomputingDaily
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_isRecomputingDaily ? '重算中...' : '重新计算日线动力系统'),
            ),
          ),
          const SizedBox(height: 12),

          // 重算周线按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed:
                  _isRecomputingDaily || _isRecomputingWeekly || _isApplyingMark
                  ? null
                  : _recomputeWeekly,
              icon: _isRecomputingWeekly
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_isRecomputingWeekly ? '重算中...' : '重新计算周线动力系统'),
            ),
          ),
          const SizedBox(height: 12),

          // 应用标记按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  _isRecomputingDaily || _isRecomputingWeekly || _isApplyingMark
                  ? null
                  : _applyMarking,
              icon: _isApplyingMark
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(_isApplyingMark ? '应用中...' : '应用双涨标记'),
            ),
          ),
          const SizedBox(height: 24),

          // 当前标记状态
          Consumer<MarketDataProvider>(
            builder: (context, provider, _) {
              final markedCount = provider.allData
                  .where((d) => d.isPowerSystemUp)
                  .length;
              final totalCount = provider.allData.length;
              return Card(
                margin: EdgeInsets.zero,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.label_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '当前标记: $markedCount / $totalCount 只股票',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.title, required this.progressNotifier});

  final String title;
  final ValueNotifier<({int current, int total, String stage})>
  progressNotifier;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: ValueListenableBuilder<({int current, int total, String stage})>(
        valueListenable: progressNotifier,
        builder: (context, progress, _) {
          final ratio = progress.total <= 0
              ? 0.0
              : (progress.current / progress.total).clamp(0.0, 1.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: ratio),
              const SizedBox(height: 10),
              Text('已处理 ${progress.current}/${progress.total}'),
              const SizedBox(height: 8),
              Text(
                progress.stage,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
