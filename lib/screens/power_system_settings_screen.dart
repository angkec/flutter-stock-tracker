import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/power_system_indicator_service.dart';

class PowerSystemSettingsScreen extends StatefulWidget {
  const PowerSystemSettingsScreen({
    super.key,
    this.dataType = KLineDataType.daily,
  });

  final KLineDataType dataType;

  @override
  State<PowerSystemSettingsScreen> createState() =>
      _PowerSystemSettingsScreenState();
}

class _PowerSystemSettingsScreenState extends State<PowerSystemSettingsScreen> {
  bool _isRecomputing = false;

  bool get _isWeekly => widget.dataType == KLineDataType.weekly;
  String get _scopeLabel => _isWeekly ? '周线' : '日线';

  DateRange _buildRecomputeDateRange() {
    const weeklyRangeDays = 760;
    const dailyRangeDays = 400;
    final end = DateTime.now();
    final start = end.subtract(
      Duration(days: _isWeekly ? weeklyRangeDays : dailyRangeDays),
    );
    return DateRange(start, end);
  }

  Future<void> _recompute() async {
    if (_isRecomputing) {
      return;
    }

    final provider = context.read<MarketDataProvider>();
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

    setState(() {
      _isRecomputing = true;
    });

    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备重算$_scopeLabel Power System...',
        ));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PowerSystemRecomputeProgressDialog(
        scopeLabel: _scopeLabel,
        progressNotifier: progressNotifier,
      ),
    );

    try {
      final prewarmStopwatch = Stopwatch()..start();
      await context.read<PowerSystemIndicatorService>().prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: widget.dataType,
        dateRange: _buildRecomputeDateRange(),
        forceRecompute: true,
        onProgress: (current, total) {
          final safeTotal = total <= 0 ? 1 : total;
          final safeCurrent = current.clamp(0, safeTotal);
          final elapsedSeconds = prewarmStopwatch.elapsedMilliseconds / 1000;
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
            stage: '速率 ${speed.toStringAsFixed(1)}只/秒 · 预计剩余 $etaLabel',
          );
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$_scopeLabel Power System重算完成')));

      // 重算完成后自动刷新列表数据
      final provider = context.read<MarketDataProvider>();
      await provider.refresh();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_scopeLabel Power System重算失败: $e')),
      );
    } finally {
      progressNotifier.dispose();
      if (mounted) {
        setState(() {
          _isRecomputing = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$_scopeLabel Power System设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_scopeLabel Power System 缓存工作台',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '该指标基于 EMA 坡度与 MACD 柱体坡度组合，缓存仅在匹配到同日期K线时参与蜡烛着色。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: ValueKey('power_system_recompute_${widget.dataType.name}'),
              onPressed: _isRecomputing ? null : _recompute,
              icon: _isRecomputing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _isRecomputing ? '重算中...' : '重算$_scopeLabel Power System',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerSystemRecomputeProgressDialog extends StatelessWidget {
  const _PowerSystemRecomputeProgressDialog({
    required this.scopeLabel,
    required this.progressNotifier,
  });

  final String scopeLabel;
  final ValueNotifier<({int current, int total, String stage})>
  progressNotifier;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('重算$scopeLabel Power System'),
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
