import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_config_store.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/industry_ema_breadth_service.dart';

class IndustryEmaBreadthSettingsScreen extends StatefulWidget {
  const IndustryEmaBreadthSettingsScreen({
    super.key,
    this.configStoreForTest,
    this.serviceForTest,
  });

  final IndustryEmaBreadthConfigStore? configStoreForTest;
  final IndustryEmaBreadthService? serviceForTest;

  @override
  State<IndustryEmaBreadthSettingsScreen> createState() =>
      _IndustryEmaBreadthSettingsScreenState();
}

class _IndustryEmaBreadthSettingsScreenState
    extends State<IndustryEmaBreadthSettingsScreen> {
  final TextEditingController _upperController = TextEditingController();
  final TextEditingController _lowerController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRecomputing = false;
  String? _validationError;

  IndustryEmaBreadthConfigStore get _store =>
      widget.configStoreForTest ?? IndustryEmaBreadthConfigStore();

  IndustryEmaBreadthService? get _service {
    if (widget.serviceForTest != null) {
      return widget.serviceForTest;
    }
    return context.read<MarketDataProvider>().industryEmaBreadthService;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfig());
  }

  @override
  void dispose() {
    _upperController.dispose();
    _lowerController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final config = await _store.load(
        defaults: IndustryEmaBreadthConfig.defaultConfig,
      );
      if (!mounted) {
        return;
      }
      _upperController.text = _formatValue(config.upperThreshold);
      _lowerController.text = _formatValue(config.lowerThreshold);
      setState(() {
        _validationError = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      _upperController.text = _formatValue(
        IndustryEmaBreadthConfig.defaultConfig.upperThreshold,
      );
      _lowerController.text = _formatValue(
        IndustryEmaBreadthConfig.defaultConfig.lowerThreshold,
      );
      setState(() {
        _validationError = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  String _formatValue(double value) {
    final rounded = value.roundToDouble();
    if (rounded == value) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  ({double lower, double upper})? _parseThresholds() {
    final upper = double.tryParse(_upperController.text.trim());
    final lower = double.tryParse(_lowerController.text.trim());
    if (upper == null || lower == null) {
      return null;
    }
    return (lower: lower, upper: upper);
  }

  String? _validateThresholds(({double lower, double upper})? values) {
    if (values == null) {
      return '请输入有效数字，且满足 0<=lower<upper<=100';
    }
    if (values.lower < 0 ||
        values.upper > 100 ||
        values.lower >= values.upper) {
      return '阈值范围无效，请满足 0<=lower<upper<=100';
    }
    return null;
  }

  Future<void> _save() async {
    final values = _parseThresholds();
    final error = _validateThresholds(values);
    if (error != null) {
      setState(() {
        _validationError = error;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _validationError = null;
    });
    try {
      final parsed = values!;
      await _store.save(
        IndustryEmaBreadthConfig(
          upperThreshold: parsed.upper,
          lowerThreshold: parsed.lower,
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('行业EMA广度阈值已保存')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _validationError = '保存失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _recompute() async {
    if (_isRecomputing) {
      return;
    }

    final service = _service;
    if (service == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('行业EMA广度服务未初始化')));
      return;
    }

    setState(() {
      _isRecomputing = true;
    });
    final progressNotifier =
        ValueNotifier<({int current, int total, String stage})>((
          current: 0,
          total: 1,
          stage: '准备重算行业EMA广度...',
        ));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _RecomputeProgressDialog(progressNotifier: progressNotifier),
    );

    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(const Duration(days: 760));
      await service.recomputeAllIndustries(
        startDate: startDate,
        endDate: endDate,
        onProgress: (current, total, stage) {
          final safeTotal = total <= 0 ? 1 : total;
          final safeCurrent = current.clamp(0, safeTotal);
          progressNotifier.value = (
            current: safeCurrent,
            total: safeTotal,
            stage: stage,
          );
        },
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('行业EMA广度重算完成')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('行业EMA广度重算失败: $e')));
    } finally {
      progressNotifier.dispose();
      if (mounted) {
        setState(() {
          _isRecomputing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('行业EMA广度设置')),
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
                    '行业EMA广度参数工作台',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '上阈值用于判定过热区，下阈值用于判定低位区。保存参数不会自动触发重算。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                children: [
                  TextField(
                    key: const ValueKey('industry_ema_upper'),
                    controller: _upperController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_isLoading && !_isSaving && !_isRecomputing,
                    decoration: const InputDecoration(labelText: '上阈值 (0-100)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('industry_ema_lower'),
                    controller: _lowerController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: !_isLoading && !_isSaving && !_isRecomputing,
                    decoration: const InputDecoration(labelText: '下阈值 (0-100)'),
                  ),
                ],
              ),
            ),
          ),
          if (_validationError != null) ...[
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
                      _validationError!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('industry_ema_save'),
            onPressed: _isLoading || _isSaving || _isRecomputing ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? '保存中...' : '保存参数'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            key: const ValueKey('industry_ema_recompute'),
            onPressed: _isLoading || _isSaving || _isRecomputing
                ? null
                : _recompute,
            icon: _isRecomputing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(_isRecomputing ? '重算中...' : '手动重算行业EMA广度'),
          ),
        ],
      ),
    );
  }
}

class _RecomputeProgressDialog extends StatelessWidget {
  const _RecomputeProgressDialog({required this.progressNotifier});

  final ValueNotifier<({int current, int total, String stage})>
  progressNotifier;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重算行业EMA广度'),
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
