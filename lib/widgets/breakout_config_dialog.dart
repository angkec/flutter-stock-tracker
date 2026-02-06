import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';

/// 显示突破条件配置 BottomSheet
void showBreakoutConfigSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const BreakoutConfigSheet(),
  );
}

/// 突破条件配置 BottomSheet
class BreakoutConfigSheet extends StatefulWidget {
  const BreakoutConfigSheet({super.key});

  @override
  State<BreakoutConfigSheet> createState() => _BreakoutConfigSheetState();
}

class _BreakoutConfigSheetState extends State<BreakoutConfigSheet> {
  late TextEditingController _breakVolumeController;
  late TextEditingController _maBreakDaysController;
  late TextEditingController _highBreakDaysController;
  late TextEditingController _maxUpperShadowRatioController;
  late TextEditingController _minBreakoutMinuteRatioController;
  late TextEditingController _minPullbackDaysController;
  late TextEditingController _maxPullbackDaysController;
  late TextEditingController _maxTotalDropController;
  late TextEditingController _maxSingleDayDropController;
  late TextEditingController _maxSingleDayGainController;
  late TextEditingController _maxTotalGainController;
  late TextEditingController _maxAvgVolumeRatioController;
  late TextEditingController _minMinuteRatioController;
  late TextEditingController _surgeThresholdController;
  late DropReferencePoint _dropReferencePoint;
  late BreakReferencePoint _breakReferencePoint;
  late bool _filterSurgeAfterPullback;

  @override
  void initState() {
    super.initState();
    final config = context.read<BreakoutService>().config;
    _breakVolumeController = TextEditingController(
      text: config.breakVolumeMultiplier.toStringAsFixed(1),
    );
    _maBreakDaysController = TextEditingController(
      text: config.maBreakDays.toString(),
    );
    _highBreakDaysController = TextEditingController(
      text: config.highBreakDays.toString(),
    );
    _maxUpperShadowRatioController = TextEditingController(
      text: config.maxUpperShadowRatio.toStringAsFixed(1),
    );
    _minBreakoutMinuteRatioController = TextEditingController(
      text: config.minBreakoutMinuteRatio.toStringAsFixed(2),
    );
    _minPullbackDaysController = TextEditingController(
      text: config.minPullbackDays.toString(),
    );
    _maxPullbackDaysController = TextEditingController(
      text: config.maxPullbackDays.toString(),
    );
    _maxTotalDropController = TextEditingController(
      text: (config.maxTotalDrop * 100).toStringAsFixed(1),
    );
    _maxSingleDayDropController = TextEditingController(
      text: (config.maxSingleDayDrop * 100).toStringAsFixed(1),
    );
    _maxSingleDayGainController = TextEditingController(
      text: (config.maxSingleDayGain * 100).toStringAsFixed(1),
    );
    _maxTotalGainController = TextEditingController(
      text: (config.maxTotalGain * 100).toStringAsFixed(1),
    );
    _maxAvgVolumeRatioController = TextEditingController(
      text: config.maxAvgVolumeRatio.toStringAsFixed(2),
    );
    _minMinuteRatioController = TextEditingController(
      text: config.minMinuteRatio.toStringAsFixed(2),
    );
    _surgeThresholdController = TextEditingController(
      text: (config.surgeThreshold * 100).toStringAsFixed(1),
    );
    _dropReferencePoint = config.dropReferencePoint;
    _breakReferencePoint = config.breakReferencePoint;
    _filterSurgeAfterPullback = config.filterSurgeAfterPullback;
  }

  @override
  void dispose() {
    _breakVolumeController.dispose();
    _maBreakDaysController.dispose();
    _highBreakDaysController.dispose();
    _maxUpperShadowRatioController.dispose();
    _minBreakoutMinuteRatioController.dispose();
    _minPullbackDaysController.dispose();
    _maxPullbackDaysController.dispose();
    _maxTotalDropController.dispose();
    _maxSingleDayDropController.dispose();
    _maxSingleDayGainController.dispose();
    _maxTotalGainController.dispose();
    _maxAvgVolumeRatioController.dispose();
    _minMinuteRatioController.dispose();
    _surgeThresholdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final breakVolume = double.tryParse(_breakVolumeController.text) ?? 1.5;
    final maBreakDays = int.tryParse(_maBreakDaysController.text) ?? 20;
    final highBreakDays = int.tryParse(_highBreakDaysController.text) ?? 5;
    final maxUpperShadowRatio =
        double.tryParse(_maxUpperShadowRatioController.text) ?? 0;
    final minBreakoutMinuteRatio =
        double.tryParse(_minBreakoutMinuteRatioController.text) ?? 0;
    final minPullbackDays = int.tryParse(_minPullbackDaysController.text) ?? 1;
    final maxPullbackDays = int.tryParse(_maxPullbackDaysController.text) ?? 5;
    final maxTotalDrop =
        (double.tryParse(_maxTotalDropController.text) ?? 10) / 100;
    final maxSingleDayDrop =
        (double.tryParse(_maxSingleDayDropController.text) ?? 0) / 100;
    final maxSingleDayGain =
        (double.tryParse(_maxSingleDayGainController.text) ?? 0) / 100;
    final maxTotalGain =
        (double.tryParse(_maxTotalGainController.text) ?? 0) / 100;
    final maxAvgVolumeRatio =
        double.tryParse(_maxAvgVolumeRatioController.text) ?? 0.7;
    final minMinuteRatio =
        double.tryParse(_minMinuteRatioController.text) ?? 1.0;
    final surgeThreshold =
        (double.tryParse(_surgeThresholdController.text) ?? 5) / 100;

    final newConfig = BreakoutConfig(
      breakVolumeMultiplier: breakVolume,
      maBreakDays: maBreakDays,
      highBreakDays: highBreakDays,
      breakReferencePoint: _breakReferencePoint,
      maxUpperShadowRatio: maxUpperShadowRatio,
      minBreakoutMinuteRatio: minBreakoutMinuteRatio,
      minPullbackDays: minPullbackDays,
      maxPullbackDays: maxPullbackDays,
      maxTotalDrop: maxTotalDrop,
      maxSingleDayDrop: maxSingleDayDrop,
      maxSingleDayGain: maxSingleDayGain,
      maxTotalGain: maxTotalGain,
      dropReferencePoint: _dropReferencePoint,
      maxAvgVolumeRatio: maxAvgVolumeRatio,
      minMinuteRatio: minMinuteRatio,
      filterSurgeAfterPullback: _filterSurgeAfterPullback,
      surgeThreshold: surgeThreshold,
    );

    context.read<BreakoutService>().updateConfig(newConfig);

    // 显示进度对话框
    final progressNotifier = ValueNotifier<(int, int)>((0, 1));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progressNotifier,
            builder: (_, progress, __) {
              final (current, total) = progress;
              final percent = total > 0 ? current / total : 0.0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('正在重算突破回踩...'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: percent),
                  const SizedBox(height: 8),
                  Text('$current / $total'),
                ],
              );
            },
          ),
        ),
      ),
    );

    await context.read<MarketDataProvider>().recalculateBreakouts(
      onProgress: (current, total) {
        progressNotifier.value = (current, total);
      },
    );

    progressNotifier.dispose();

    if (mounted) {
      Navigator.of(context).pop(); // 关闭进度对话框
      Navigator.of(context).pop(); // 关闭配置 BottomSheet
    }
  }

  void _reset() {
    const defaults = BreakoutConfig.defaults;
    _breakVolumeController.text =
        defaults.breakVolumeMultiplier.toStringAsFixed(1);
    _maBreakDaysController.text = defaults.maBreakDays.toString();
    _highBreakDaysController.text = defaults.highBreakDays.toString();
    _maxUpperShadowRatioController.text =
        defaults.maxUpperShadowRatio.toStringAsFixed(1);
    _minBreakoutMinuteRatioController.text =
        defaults.minBreakoutMinuteRatio.toStringAsFixed(2);
    _minPullbackDaysController.text = defaults.minPullbackDays.toString();
    _maxPullbackDaysController.text = defaults.maxPullbackDays.toString();
    _maxTotalDropController.text =
        (defaults.maxTotalDrop * 100).toStringAsFixed(1);
    _maxSingleDayDropController.text =
        (defaults.maxSingleDayDrop * 100).toStringAsFixed(1);
    _maxSingleDayGainController.text =
        (defaults.maxSingleDayGain * 100).toStringAsFixed(1);
    _maxTotalGainController.text =
        (defaults.maxTotalGain * 100).toStringAsFixed(1);
    _maxAvgVolumeRatioController.text =
        defaults.maxAvgVolumeRatio.toStringAsFixed(2);
    _minMinuteRatioController.text = defaults.minMinuteRatio.toStringAsFixed(2);
    _surgeThresholdController.text =
        (defaults.surgeThreshold * 100).toStringAsFixed(1);
    setState(() {
      _dropReferencePoint = defaults.dropReferencePoint;
      _breakReferencePoint = defaults.breakReferencePoint;
      _filterSurgeAfterPullback = defaults.filterSurgeAfterPullback;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 拖动条
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '多日回踩配置',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _reset,
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
            ),
            const Divider(),
            // 内容区域
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // 突破日条件
                  ExpansionTile(
                    title: const Text('突破日条件'),
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
                    children: [
                      _buildTextField(
                        controller: _breakVolumeController,
                        label: '放量倍数',
                        hint: '突破日成交量 > 前5日均量 × 此值',
                        suffix: '倍',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maBreakDaysController,
                        label: '突破N日均线',
                        hint: '0=不检测',
                        suffix: '天',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _highBreakDaysController,
                        label: '突破前N日高点',
                        hint: '0=不检测',
                        suffix: '天',
                      ),
                      const SizedBox(height: 12),
                      _buildSegmentedField(
                        label: '突破参考点',
                        hint: '判断是否突破前N日高点时使用',
                        child: SegmentedButton<BreakReferencePoint>(
                          segments: const [
                            ButtonSegment(
                              value: BreakReferencePoint.high,
                              label: Text('最高价'),
                            ),
                            ButtonSegment(
                              value: BreakReferencePoint.close,
                              label: Text('收盘价'),
                            ),
                          ],
                          selected: {_breakReferencePoint},
                          onSelectionChanged: (selected) {
                            setState(() {
                              _breakReferencePoint = selected.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maxUpperShadowRatioController,
                        label: '最大上引线比例',
                        hint: '上引线/实体，0=不检测',
                        suffix: '',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _minBreakoutMinuteRatioController,
                        label: '最小分钟量比',
                        hint: '突破日分钟涨跌量比，0=不检测',
                        suffix: '',
                      ),
                    ],
                  ),
                  // 回踩阶段条件
                  ExpansionTile(
                    title: const Text('回踩阶段条件'),
                    initiallyExpanded: false,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
                    children: [
                      _buildTextField(
                        controller: _minPullbackDaysController,
                        label: '最小回踩天数',
                        hint: '回踩期间最少天数',
                        suffix: '天',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maxPullbackDaysController,
                        label: '最大回踩天数',
                        hint: '回踩期间最多天数',
                        suffix: '天',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maxTotalDropController,
                        label: '最大总跌幅',
                        hint: '今日收盘相对参考价的跌幅',
                        suffix: '%',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maxSingleDayDropController,
                        label: '最大单日跌幅',
                        hint: '回踩阶段单天最低价相对参考价的最大跌幅，0=不检测',
                        suffix: '%',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maxSingleDayGainController,
                        label: '最大单日涨幅',
                        hint: '回踩阶段单天最高价相对参考价的最大涨幅，0=不检测',
                        suffix: '%',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maxTotalGainController,
                        label: '最大总涨幅',
                        hint: '回踩阶段最高价相对参考价的最大涨幅，0=不检测',
                        suffix: '%',
                      ),
                      const SizedBox(height: 12),
                      _buildSegmentedField(
                        label: '跌幅参考点',
                        hint: '计算跌幅时的参考价格',
                        child: SegmentedButton<DropReferencePoint>(
                          segments: const [
                            ButtonSegment(
                              value: DropReferencePoint.breakoutClose,
                              label: Text('突破日收盘'),
                            ),
                            ButtonSegment(
                              value: DropReferencePoint.breakoutHigh,
                              label: Text('突破日最高'),
                            ),
                          ],
                          selected: {_dropReferencePoint},
                          onSelectionChanged: (selected) {
                            setState(() {
                              _dropReferencePoint = selected.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _maxAvgVolumeRatioController,
                        label: '最大平均量比',
                        hint: '回踩期间平均成交量 / 突破日成交量',
                        suffix: '',
                      ),
                    ],
                  ),
                  // 今日条件
                  ExpansionTile(
                    title: const Text('今日条件'),
                    initiallyExpanded: false,
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
                    children: [
                      _buildTextField(
                        controller: _minMinuteRatioController,
                        label: '最小分钟量比',
                        hint: '今日分钟涨跌量比',
                        suffix: '',
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('过滤回踩后暴涨'),
                        subtitle: const Text('今日涨幅超过阈值则排除'),
                        value: _filterSurgeAfterPullback,
                        onChanged: (value) {
                          setState(() {
                            _filterSurgeAfterPullback = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_filterSurgeAfterPullback)
                        _buildTextField(
                          controller: _surgeThresholdController,
                          label: '暴涨阈值',
                          hint: '今日涨幅超过此值视为暴涨',
                          suffix: '%',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
        isDense: true,
      ),
    );
  }

  Widget _buildSegmentedField({
    required String label,
    required String hint,
    required Widget child,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      child: child,
    );
  }
}

/// 保持向后兼容的 Dialog 包装器
class BreakoutConfigDialog extends StatelessWidget {
  const BreakoutConfigDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // 关闭 Dialog 并显示 BottomSheet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pop();
      showBreakoutConfigSheet(context);
    });
    return const SizedBox.shrink();
  }
}
