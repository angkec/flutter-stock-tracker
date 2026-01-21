import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/pullback_config.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';

/// 回踩配置对话框
class PullbackConfigDialog extends StatefulWidget {
  const PullbackConfigDialog({super.key});

  @override
  State<PullbackConfigDialog> createState() => _PullbackConfigDialogState();
}

class _PullbackConfigDialogState extends State<PullbackConfigDialog> {
  late TextEditingController _volumeController;
  late TextEditingController _gainController;
  late TextEditingController _dropController;
  late TextEditingController _ratioController;
  late TextEditingController _minuteRatioController;

  @override
  void initState() {
    super.initState();
    final config = context.read<PullbackService>().config;
    _volumeController = TextEditingController(
      text: config.volumeMultiplier.toStringAsFixed(1),
    );
    _gainController = TextEditingController(
      text: (config.minYesterdayGain * 100).toStringAsFixed(0),
    );
    _dropController = TextEditingController(
      text: (config.maxDropRatio * 100).toStringAsFixed(0),
    );
    _ratioController = TextEditingController(
      text: config.minDailyRatio.toStringAsFixed(2),
    );
    _minuteRatioController = TextEditingController(
      text: config.minMinuteRatio.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _volumeController.dispose();
    _gainController.dispose();
    _dropController.dispose();
    _ratioController.dispose();
    _minuteRatioController.dispose();
    super.dispose();
  }

  void _save() {
    final volume = double.tryParse(_volumeController.text) ?? 1.5;
    final gain = (double.tryParse(_gainController.text) ?? 3) / 100;
    final drop = (double.tryParse(_dropController.text) ?? 50) / 100;
    final ratio = double.tryParse(_ratioController.text) ?? 0.85;
    final minuteRatio = double.tryParse(_minuteRatioController.text) ?? 0.8;

    final newConfig = PullbackConfig(
      volumeMultiplier: volume,
      minYesterdayGain: gain,
      maxDropRatio: drop,
      minDailyRatio: ratio,
      minMinuteRatio: minuteRatio,
    );

    context.read<PullbackService>().updateConfig(newConfig);
    Navigator.of(context).pop();
  }

  void _reset() {
    const defaults = PullbackConfig.defaults;
    _volumeController.text = defaults.volumeMultiplier.toStringAsFixed(1);
    _gainController.text = (defaults.minYesterdayGain * 100).toStringAsFixed(0);
    _dropController.text = (defaults.maxDropRatio * 100).toStringAsFixed(0);
    _ratioController.text = defaults.minDailyRatio.toStringAsFixed(2);
    _minuteRatioController.text = defaults.minMinuteRatio.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('回踩条件配置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(
              controller: _volumeController,
              label: '昨日高量倍数',
              hint: '昨日成交量 > 前5日均量 × 此值',
              suffix: '倍',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _gainController,
              label: '昨日最小涨幅',
              hint: '昨日收盘 > 开盘 × (1 + 此值%)',
              suffix: '%',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _dropController,
              label: '最大跌幅比例',
              hint: '今日跌幅 < 昨日涨幅 × 此值%',
              suffix: '%',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _ratioController,
              label: '最小日K量比',
              hint: '今日成交量 / 前5日均量',
              suffix: '',
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _minuteRatioController,
              label: '最小分钟量比',
              hint: '分钟涨量 / 分钟跌量',
              suffix: '',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 2,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
