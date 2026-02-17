import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/models/adx_config.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';

class AdxSettingsScreen extends StatefulWidget {
  const AdxSettingsScreen({super.key, this.dataType = KLineDataType.daily});

  final KLineDataType dataType;

  @override
  State<AdxSettingsScreen> createState() => _AdxSettingsScreenState();
}

class _AdxSettingsScreenState extends State<AdxSettingsScreen> {
  static const int _weeklyRecomputeFetchBatchSize = 120;
  static const int _weeklyRecomputePersistConcurrency = 8;

  late int _period;
  late double _threshold;
  bool _isSaving = false;
  bool _isRecomputing = false;

  bool get _isWeekly => widget.dataType == KLineDataType.weekly;
  String get _scopeLabel => _isWeekly ? '周线' : '日线';

  @override
  void initState() {
    super.initState();
    final config = context.read<AdxIndicatorService>().configFor(
      widget.dataType,
    );
    _period = config.period;
    _threshold = config.threshold;
  }

  String? _validate() {
    if (_period <= 0) {
      return '周期必须大于0';
    }
    if (_threshold <= 0) {
      return '阈值必须大于0';
    }
    return null;
  }

  Future<void> _save() async {
    final validation = _validate();
    if (validation != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation)));
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      await context.read<AdxIndicatorService>().updateConfigFor(
        dataType: widget.dataType,
        newConfig: AdxConfig(period: _period, threshold: _threshold),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$_scopeLabel ADX参数已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _resetDefaults() async {
    final defaults = AdxIndicatorService.defaultConfigFor(widget.dataType);
    setState(() {
      _period = defaults.period;
      _threshold = defaults.threshold;
    });
    await _save();
  }

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
          stage: '准备重算$_scopeLabel ADX...',
        ));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdxRecomputeProgressDialog(
        scopeLabel: _scopeLabel,
        progressNotifier: progressNotifier,
      ),
    );

    try {
      final prewarmStopwatch = Stopwatch()..start();
      await context.read<AdxIndicatorService>().prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: widget.dataType,
        dateRange: _buildRecomputeDateRange(),
        forceRecompute: _isWeekly,
        fetchBatchSize: _isWeekly ? _weeklyRecomputeFetchBatchSize : null,
        maxConcurrentPersistWrites: _isWeekly
            ? _weeklyRecomputePersistConcurrency
            : null,
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
          final elapsedLabel = _formatEtaSeconds(
            prewarmStopwatch.elapsed.inSeconds,
          );

          progressNotifier.value = (
            current: safeCurrent,
            total: safeTotal,
            stage:
                '速率 ${speed.toStringAsFixed(1)}只/秒 · 预计剩余 $etaLabel · '
                '已耗时 $elapsedLabel',
          );
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$_scopeLabel ADX重算完成')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$_scopeLabel ADX重算失败: $e')));
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
    final validation = _validate();

    return Scaffold(
      appBar: AppBar(title: Text('${_scopeLabel}ADX设置')),
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
                    '$_scopeLabel ADX 参数工作台',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ADX 使用 Wilder 公式，默认周期 14，趋势阈值 25。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _IntParameterCard(
            title: '周期 (Period)',
            hint: '建议 8~30，越小越敏感',
            value: _period,
            min: 5,
            max: 60,
            divisions: 55,
            onChanged: (value) => setState(() => _period = value),
          ),
          const SizedBox(height: 12),
          _DoubleParameterCard(
            title: '阈值线 (Threshold)',
            hint: '常用 20/25/30 作为趋势强度参考',
            value: _threshold,
            min: 10,
            max: 50,
            divisions: 80,
            onChanged: (value) => setState(() => _threshold = value),
          ),
          if (validation != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      validation,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving || _isRecomputing
                      ? null
                      : _resetDefaults,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('恢复默认'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSaving || _isRecomputing ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? '保存中...' : '保存参数'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              key: ValueKey('adx_recompute_${widget.dataType.name}'),
              onPressed: _isSaving || _isRecomputing ? null : _recompute,
              icon: _isRecomputing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_isRecomputing ? '重算中...' : '重算$_scopeLabel ADX'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdxRecomputeProgressDialog extends StatelessWidget {
  const _AdxRecomputeProgressDialog({
    required this.scopeLabel,
    required this.progressNotifier,
  });

  final String scopeLabel;
  final ValueNotifier<({int current, int total, String stage})>
  progressNotifier;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('重算$scopeLabel ADX'),
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

class _IntParameterCard extends StatelessWidget {
  const _IntParameterCard({
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text('$value', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(hint, style: theme.textTheme.bodySmall),
            Row(
              children: [
                IconButton(
                  onPressed: value > min ? () => onChanged(value - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Expanded(
                  child: Slider(
                    value: value.toDouble(),
                    min: min.toDouble(),
                    max: max.toDouble(),
                    divisions: divisions,
                    label: '$value',
                    onChanged: (raw) => onChanged(raw.round()),
                  ),
                ),
                IconButton(
                  onPressed: value < max ? () => onChanged(value + 1) : null,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DoubleParameterCard extends StatelessWidget {
  const _DoubleParameterCard({
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  value.toStringAsFixed(1),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(hint, style: theme.textTheme.bodySmall),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(1),
              onChanged: (raw) => onChanged((raw * 10).round() / 10),
            ),
          ],
        ),
      ),
    );
  }
}
