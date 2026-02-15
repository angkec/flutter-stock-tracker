import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';

class MacdSettingsScreen extends StatefulWidget {
  const MacdSettingsScreen({super.key});

  @override
  State<MacdSettingsScreen> createState() => _MacdSettingsScreenState();
}

class _MacdSettingsScreenState extends State<MacdSettingsScreen> {
  late int _fastPeriod;
  late int _slowPeriod;
  late int _signalPeriod;
  late int _windowMonths;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<MacdIndicatorService>().config;
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
      await context.read<MacdIndicatorService>().updateConfig(
        MacdConfig(
          fastPeriod: _fastPeriod,
          slowPeriod: _slowPeriod,
          signalPeriod: _signalPeriod,
          windowMonths: _windowMonths,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('MACD 参数已保存')));
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
    const defaults = MacdConfig.defaults;
    setState(() {
      _fastPeriod = defaults.fastPeriod;
      _slowPeriod = defaults.slowPeriod;
      _signalPeriod = defaults.signalPeriod;
      _windowMonths = defaults.windowMonths;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final validation = _validate();

    return Scaffold(
      appBar: AppBar(title: const Text('MACD 指标设置')),
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
                  'MACD 参数工作台',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '仅保存轻量参数到本地设置；指标序列走文件缓存，避免 SharedPreferences 体积膨胀。',
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
            min: 1,
            max: 12,
            divisions: 11,
            hint: '当前策略建议保持 3 个月',
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
                  onPressed: _isSaving ? null : _resetDefaults,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('恢复默认'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
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
        ],
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
        border: Border.all(color: colorScheme.onPrimary.withValues(alpha: 0.26)),
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
