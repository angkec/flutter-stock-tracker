import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/backtest_config.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/screens/stock_detail_screen.dart';
import 'package:stock_rtwatcher/theme/theme.dart';

/// 回测信号列表组件
class BacktestSignalList extends StatelessWidget {
  /// 信号列表
  final List<SignalDetail> signals;

  /// 观察周期天数（用于列头显示）
  final List<int> observationDays;

  /// 目标涨幅（用于高亮成功）
  final double targetGain;

  const BacktestSignalList({
    super.key,
    required this.signals,
    required this.observationDays,
    required this.targetGain,
  });

  /// 从股票代码推断市场
  int _inferMarket(String code) {
    // 上海: 6开头
    if (code.startsWith('6')) return 1;
    // 深圳: 0、3开头
    return 0;
  }

  /// 格式化涨幅百分比
  String _formatGain(double gain) {
    final sign = gain >= 0 ? '+' : '';
    return '$sign${(gain * 100).toStringAsFixed(1)}%';
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 导航到股票详情页
  void _navigateToDetail(BuildContext context, SignalDetail signal) {
    final stock = Stock(
      code: signal.stockCode,
      name: signal.stockName,
      market: _inferMarket(signal.stockCode),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StockDetailScreen(stock: stock),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (signals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无信号数据',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '请先运行回测',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: signals.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) => _buildSignalItem(context, signals[index]),
    );
  }

  Widget _buildSignalItem(BuildContext context, SignalDetail signal) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => _navigateToDetail(context, signal),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：股票名称和突破日期
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 股票名称和代码
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: signal.stockName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: ' (${signal.stockCode})',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 突破日期
                  Text(
                    '突破日: ${_formatDate(signal.breakoutDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 第二行：买入价
              Text(
                '买入价: ${signal.buyPrice.toStringAsFixed(2)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // 第三行：各周期涨幅表格
              _buildPeriodGainsTable(context, signal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodGainsTable(BuildContext context, SignalDetail signal) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.dividerColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: observationDays.asMap().entries.map((entry) {
            final index = entry.key;
            final days = entry.value;
            final gain = signal.maxGainByPeriod[days] ?? 0.0;
            final isSuccess = signal.successByPeriod[days] ?? false;
            final isLast = index == observationDays.length - 1;

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
                child: _buildPeriodCell(context, days, gain, isSuccess),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPeriodCell(
    BuildContext context,
    int days,
    double gain,
    bool isSuccess,
  ) {
    final theme = Theme.of(context);
    final gainColor = isSuccess
        ? AppColors.stockUp
        : (gain >= 0 ? theme.colorScheme.onSurfaceVariant : AppColors.stockDown);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 天数标题
          Text(
            '$days天',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          // 涨幅和成功标记
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatGain(gain),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: gainColor,
                  fontWeight: isSuccess ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'monospace',
                ),
              ),
              if (isSuccess) ...[
                const SizedBox(width: 2),
                const Icon(
                  Icons.check,
                  size: 14,
                  color: AppColors.stockUp,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
