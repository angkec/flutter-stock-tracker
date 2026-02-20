import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';

class MacdSettingsScreen extends StatefulWidget {
  const MacdSettingsScreen({super.key, this.dataType = KLineDataType.daily});

  final KLineDataType dataType;

  @override
  State<MacdSettingsScreen> createState() => _MacdSettingsScreenState();
}

class _MacdSettingsScreenState extends State<MacdSettingsScreen> {
  static const int _weeklyRecomputeFetchBatchSize = 120;
  static const int _weeklyRecomputePersistConcurrency = 8;

  late int _fastPeriod;
  late int _slowPeriod;
  late int _signalPeriod;
  late int _windowMonths;
  bool _isSaving = false;
  bool _isRecomputing = false;

  bool get _isWeekly => widget.dataType == KLineDataType.weekly;
  String get _scopeLabel => _isWeekly ? '周线' : '日线';

  @override
  void initState() {
    super.initState();
    final config = context.read<MacdIndicatorService>().configFor(
      widget.dataType,
    );
    _fastPeriod = config.fastPeriod;
    _slowPeriod = config.slowPeriod;
    _signalPeriod = config.signalPeriod;
    _windowMonths = config.windowMonths;
  }

  String? _validate() {
    if (_fastPeriod <= 0 ||
        _slowPeriod <= 0 ||
        _signalPeriod <= 0 ||
        _windowMonths <= 0) {
      return '参数必须大于0';
    }
    if (_fastPeriod >= _slowPeriod) {
      return '快线周期必须小于慢线周期';
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
      await context.read<MacdIndicatorService>().updateConfigFor(
        dataType: widget.dataType,
        newConfig: MacdConfig(
          fastPeriod: _fastPeriod,
          slowPeriod: _slowPeriod,
          signalPeriod: _signalPeriod,
          windowMonths: _windowMonths,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$_scopeLabel MACD参数已保存')));
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
    final defaults = MacdIndicatorService.defaultConfigFor(widget.dataType);
    setState(() {
      _fastPeriod = defaults.fastPeriod;
      _slowPeriod = defaults.slowPeriod;
      _signalPeriod = defaults.signalPeriod;
      _windowMonths = defaults.windowMonths;
    });
    await _save();
  }

  DateRange _buildRecomputeDateRange() {
    const weeklyRangeDays = 760;
    const dailyRangeDays = 540;
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
          stage: '准备重算$_scopeLabel MACD...',
        ));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MacdRecomputeProgressDialog(
        scopeLabel: _scopeLabel,
        progressNotifier: progressNotifier,
      ),
    );

    try {
      final prewarmStopwatch = Stopwatch()..start();
      await context.read<MacdIndicatorService>().prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: widget.dataType,
        dateRange: _buildRecomputeDateRange(),
        forceRecompute: false,
        // Manual recompute should not be short-circuited by the prewarm snapshot.
        ignoreSnapshot: true,
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
      ).showSnackBar(SnackBar(content: Text('$_scopeLabel MACD重算完成')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$_scopeLabel MACD重算失败: $e')));
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final validation = _validate();

    return Scaffold(
      appBar: AppBar(title: Text('${_scopeLabel}MACD设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.92),
                  colorScheme.secondary.withValues(alpha: 0.86),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.24),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_scopeLabel MACD 参数工作台',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '仅保存$_scopeLabel轻量参数到本地设置；指标序列走文件缓存，避免 SharedPreferences 体积膨胀。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimary.withValues(alpha: 0.92),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(label: 'Fast $_fastPeriod'),
                    _InfoChip(label: 'Slow $_slowPeriod'),
                    _InfoChip(label: 'Signal $_signalPeriod'),
                    _InfoChip(label: '窗口 $_windowMonths 月'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ParameterCard(
            title: '快线周期 (Fast EMA)',
            value: _fastPeriod,
            min: 3,
            max: 30,
            divisions: 27,
            hint: '建议 6~15，越小越敏感',
            onChanged: (value) => setState(() => _fastPeriod = value),
          ),
          const SizedBox(height: 12),
          _ParameterCard(
            title: '慢线周期 (Slow EMA)',
            value: _slowPeriod,
            min: 10,
            max: 120,
            divisions: 110,
            hint: '建议 20~60，越大越平滑',
            onChanged: (value) => setState(() => _slowPeriod = value),
          ),
          const SizedBox(height: 12),
          _ParameterCard(
            title: '信号线周期 (DEA)',
            value: _signalPeriod,
            min: 3,
            max: 30,
            divisions: 27,
            hint: '建议 5~12，用于控制柱体节奏',
            onChanged: (value) => setState(() => _signalPeriod = value),
          ),
          const SizedBox(height: 12),
          _ParameterCard(
            title: '缓存窗口（月）',
            value: _windowMonths,
            min: _isWeekly ? 12 : 1,
            max: _isWeekly ? 12 : 24,
            divisions: _isWeekly ? 1 : 23,
            hint: _isWeekly ? '周线固定为 12 个月（1年）' : '当前策略建议保持 12~18 个月',
            onChanged: (value) => setState(() => _windowMonths = value),
          ),
          if (validation != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      validation,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
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
              key: ValueKey('macd_recompute_${widget.dataType.name}'),
              onPressed: _isSaving || _isRecomputing ? null : _recompute,
              icon: _isRecomputing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_isRecomputing ? '重算中...' : '重算${_scopeLabel}MACD'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacdRecomputeProgressDialog extends StatelessWidget {
  const _MacdRecomputeProgressDialog({
    required this.scopeLabel,
    required this.progressNotifier,
  });

  final String scopeLabel;
  final ValueNotifier<({int current, int total, String stage})>
  progressNotifier;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('重算$scopeLabel MACD'),
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

class _ParameterCard extends StatelessWidget {
  final String title;
  final String hint;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final ValueChanged<int> onChanged;

  const _ParameterCard({
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$value',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: colorScheme.onPrimary.withValues(alpha: 0.14),
        border: Border.all(
          color: colorScheme.onPrimary.withValues(alpha: 0.26),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
