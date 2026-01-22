import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/backtest_config.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/backtest_service.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/widgets/backtest_chart.dart';
import 'package:stock_rtwatcher/widgets/backtest_signal_list.dart';
import 'package:stock_rtwatcher/widgets/breakout_config_dialog.dart';

/// 回测分析页面
class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  bool _isRunning = false;
  BacktestResult? _result;
  String? _errorMessage;

  // 临时编辑的回测配置
  late List<int> _observationDays;
  late double _targetGain;
  late BuyPriceReference _buyPriceReference;

  // 新增观察周期的输入控制器
  final TextEditingController _newDaysController = TextEditingController();
  final TextEditingController _targetGainController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final backtestService = context.read<BacktestService>();
    _observationDays = List.from(backtestService.config.observationDays);
    _targetGain = backtestService.config.targetGain;
    _buyPriceReference = backtestService.config.buyPriceReference;
    _targetGainController.text = (_targetGain * 100).toStringAsFixed(1);
  }

  @override
  void dispose() {
    _newDaysController.dispose();
    _targetGainController.dispose();
    super.dispose();
  }

  /// 保存配置变更
  Future<void> _saveConfig() async {
    final backtestService = context.read<BacktestService>();
    final newConfig = BacktestConfig(
      observationDays: _observationDays,
      targetGain: _targetGain,
      buyPriceReference: _buyPriceReference,
    );
    await backtestService.updateConfig(newConfig);
  }

  /// 添加观察周期
  void _addObservationDay() {
    final days = int.tryParse(_newDaysController.text);
    if (days != null && days > 0 && !_observationDays.contains(days)) {
      setState(() {
        _observationDays.add(days);
        _observationDays.sort();
      });
      _newDaysController.clear();
      _saveConfig();
    }
  }

  /// 删除观察周期
  void _removeObservationDay(int days) {
    if (_observationDays.length > 1) {
      setState(() {
        _observationDays.remove(days);
      });
      _saveConfig();
    }
  }

  /// 更新目标涨幅
  void _updateTargetGain(String value) {
    final gain = double.tryParse(value);
    if (gain != null && gain > 0) {
      setState(() {
        _targetGain = gain / 100;
      });
      _saveConfig();
    }
  }

  /// 更新买入价基准
  void _updateBuyPriceReference(BuyPriceReference value) {
    setState(() {
      _buyPriceReference = value;
    });
    _saveConfig();
  }

  /// 运行回测
  Future<void> _runBacktest() async {
    final provider = context.read<MarketDataProvider>();
    final backtestService = context.read<BacktestService>();
    final breakoutService = context.read<BreakoutService>();

    // 检查数据是否就绪
    if (provider.dailyBarsCacheCount == 0) {
      setState(() {
        _errorMessage = '请先在全市场页面刷新数据';
      });
      return;
    }

    if (provider.allData.isEmpty) {
      setState(() {
        _errorMessage = '暂无股票数据';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      // 在后台线程运行回测（数据量大时耗时）
      await Future.delayed(const Duration(milliseconds: 100)); // UI更新

      final result = backtestService.runBacktest(
        dailyBarsMap: provider.dailyBarsCache,
        stockDataMap: provider.stockDataMap,
        breakoutService: breakoutService,
      );

      setState(() {
        _result = result;
        _isRunning = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '回测失败: $e';
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final breakoutService = context.watch<BreakoutService>();
    final backtestService = context.watch<BacktestService>();
    final provider = context.watch<MarketDataProvider>();

    final breakoutConfig = breakoutService.config;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回测分析'),
      ),
      body: Column(
        children: [
          // 操作栏
          _buildActionBar(context),

          // 可滚动内容
          Expanded(
            child: _isRunning
                ? _buildLoadingView(context)
                : _errorMessage != null
                    ? _buildErrorView(context)
                    : _buildContent(context, breakoutConfig, backtestService.config, provider),
          ),
        ],
      ),
    );
  }

  /// 构建操作栏
  Widget _buildActionBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 修改配置按钮
          OutlinedButton.icon(
            onPressed: () => showBreakoutConfigSheet(context),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('修改配置'),
          ),
          const SizedBox(width: 12),
          // 开始回测按钮
          Expanded(
            child: FilledButton.icon(
              onPressed: _isRunning ? null : _runBacktest,
              icon: _isRunning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow, size: 18),
              label: Text(_isRunning ? '回测中...' : '开始回测'),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建加载视图
  Widget _buildLoadingView(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在运行回测...'),
        ],
      ),
    );
  }

  /// 构建错误视图
  Widget _buildErrorView(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _runBacktest,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 构建主内容
  Widget _buildContent(
    BuildContext context,
    BreakoutConfig breakoutConfig,
    BacktestConfig backtestConfig,
    MarketDataProvider provider,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 配置摘要
        _buildConfigSummary(context, breakoutConfig),
        const SizedBox(height: 16),

        // 回测参数配置
        _buildBacktestParams(context),
        const SizedBox(height: 16),

        // 回测结果（如果有）
        if (_result != null) ...[
          // 成功率汇总卡片
          _buildSuccessRateSummary(context),
          const SizedBox(height: 16),

          // 图表区
          _buildChartSection(context),
          const SizedBox(height: 16),

          // 详情列表
          _buildSignalListSection(context),
        ] else ...[
          // 未运行回测时的提示
          _buildEmptyHint(context, provider),
        ],
      ],
    );
  }

  /// 构建配置摘要（可折叠）
  Widget _buildConfigSummary(BuildContext context, BreakoutConfig config) {
    final theme = Theme.of(context);

    return Card(
      child: ExpansionTile(
        leading: Icon(
          Icons.settings,
          color: theme.colorScheme.primary,
        ),
        title: const Text('突破配置'),
        subtitle: Text(
          '量>${config.breakVolumeMultiplier}x 前高${config.highBreakDays}天 回踩${config.minPullbackDays}-${config.maxPullbackDays}天',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConfigRow(
                  '突破日条件',
                  '量>${config.breakVolumeMultiplier}x '
                      '${config.maBreakDays > 0 ? "MA${config.maBreakDays} " : ""}'
                      '前高${config.highBreakDays}天 '
                      '${config.maxUpperShadowRatio > 0 ? "上引<${config.maxUpperShadowRatio.toStringAsFixed(1)}" : ""}',
                  theme,
                ),
                const SizedBox(height: 8),
                _buildConfigRow(
                  '回踩条件',
                  '天数${config.minPullbackDays}-${config.maxPullbackDays} '
                      '跌<${(config.maxTotalDrop * 100).toStringAsFixed(0)}% '
                      '量比<${config.maxAvgVolumeRatio}',
                  theme,
                ),
                const SizedBox(height: 8),
                _buildConfigRow(
                  '跌幅参考点',
                  config.dropReferencePoint == DropReferencePoint.breakoutClose
                      ? '突破日收盘价'
                      : '突破日最高价',
                  theme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(String label, String value, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// 构建回测参数配置
  Widget _buildBacktestParams(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '回测参数',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // 观察周期
            Text(
              '观察周期',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._observationDays.map((days) => Chip(
                      label: Text('$days天'),
                      deleteIcon: _observationDays.length > 1
                          ? const Icon(Icons.close, size: 16)
                          : null,
                      onDeleted: _observationDays.length > 1
                          ? () => _removeObservationDay(days)
                          : null,
                    )),
                // 添加按钮
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                  onPressed: () => _showAddDaysDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 目标涨幅
            Row(
              children: [
                Text(
                  '目标涨幅',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _targetGainController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    decoration: const InputDecoration(
                      suffixText: '%',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _updateTargetGain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 买入价基准
            Text(
              '买入价基准',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<BuyPriceReference>(
              segments: const [
                ButtonSegment(
                  value: BuyPriceReference.breakoutHigh,
                  label: Text('突破日最高', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: BuyPriceReference.breakoutClose,
                  label: Text('突破日收盘', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: BuyPriceReference.pullbackAverage,
                  label: Text('回踩均价', style: TextStyle(fontSize: 12)),
                ),
                ButtonSegment(
                  value: BuyPriceReference.pullbackLow,
                  label: Text('回踩最低', style: TextStyle(fontSize: 12)),
                ),
              ],
              selected: {_buyPriceReference},
              onSelectionChanged: (selected) {
                _updateBuyPriceReference(selected.first);
              },
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }

  /// 显示添加天数对话框
  void _showAddDaysDialog(BuildContext context) {
    _newDaysController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加观察周期'),
        content: TextField(
          controller: _newDaysController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '天数',
            suffixText: '天',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) {
            _addObservationDay();
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              _addObservationDay();
              Navigator.of(context).pop();
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 构建成功率汇总卡片
  Widget _buildSuccessRateSummary(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '成功率汇总',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '共${result.totalSignals}个信号',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                children: result.periodStats.asMap().entries.map((entry) {
                  final index = entry.key;
                  final stat = entry.value;
                  final isLast = index == result.periodStats.length - 1;

                  return Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : Border(
                                right: BorderSide(
                                  color: theme.dividerColor,
                                  width: 1,
                                ),
                              ),
                      ),
                      child: _buildStatCard(context, stat),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, PeriodStats stat) {
    final theme = Theme.of(context);
    final successPercent = (stat.successRate * 100).toStringAsFixed(0);
    final avgGainPercent = (stat.avgMaxGain * 100).toStringAsFixed(1);

    // 根据成功率选择颜色
    Color successColor;
    if (stat.successRate >= 0.7) {
      successColor = const Color(0xFF00AA00);
    } else if (stat.successRate >= 0.5) {
      successColor = const Color(0xFF44BB44);
    } else if (stat.successRate >= 0.3) {
      successColor = const Color(0xFF88CC88);
    } else {
      successColor = theme.colorScheme.onSurfaceVariant;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${stat.days}天',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$successPercent%',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: successColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${stat.successCount}/${_result!.periodStats.isNotEmpty ? _result!.signals.where((s) => s.successByPeriod.containsKey(stat.days)).length : 0}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '均涨: $avgGainPercent%',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建图表区
  Widget _buildChartSection(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '图表分析',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            BacktestChart(
              result: result,
              targetGain: _targetGain,
              height: 200,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建信号列表区
  Widget _buildSignalListSection(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result!;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '信号详情',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${result.signals.length}条',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 限制列表高度，使用 SizedBox 包裹
          SizedBox(
            height: 400,
            child: BacktestSignalList(
              signals: result.signals,
              observationDays: _observationDays,
              targetGain: _targetGain,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyHint(BuildContext context, MarketDataProvider provider) {
    final theme = Theme.of(context);

    final hasData = provider.dailyBarsCacheCount > 0 && provider.allData.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasData ? Icons.analytics_outlined : Icons.cloud_download_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              hasData ? '点击"开始回测"运行分析' : '请先在全市场页面刷新数据',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasData
                  ? '回测将使用当前的突破配置和回测参数'
                  : '回测需要日K线数据支持',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasData) ...[
              const SizedBox(height: 16),
              Text(
                '已加载 ${provider.dailyBarsCacheCount} 只股票的日K数据',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
