import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/theme/theme.dart';

/// 统计区间数据
class StatsInterval {
  final String label;
  final int count;
  final Color color;

  const StatsInterval({
    required this.label,
    required this.count,
    required this.color,
  });
}

/// 市场统计条
class MarketStatsBar extends StatelessWidget {
  final List<StockMonitorData> stocks;

  const MarketStatsBar({super.key, required this.stocks});

  /// 计算涨跌分布
  List<StatsInterval> _calculateChangeDistribution() {
    int limitUp = 0;    // >= 9.8%
    int up5 = 0;        // 5% ~ 9.8%
    int up0to5 = 0;     // 0 < x < 5%
    int flat = 0;       // == 0
    int down0to5 = 0;   // -5% < x < 0
    int down5 = 0;      // -9.8% < x <= -5%
    int limitDown = 0;  // <= -9.8%

    for (final stock in stocks) {
      final cp = stock.changePercent;
      if (cp >= 9.8) {
        limitUp++;
      } else if (cp >= 5) {
        up5++;
      } else if (cp > 0) {
        up0to5++;
      } else if (cp.abs() < 0.001) {  // effectively zero
        flat++;
      } else if (cp > -5) {
        down0to5++;
      } else if (cp > -9.8) {
        down5++;
      } else {
        limitDown++;
      }
    }

    return [
      StatsInterval(label: '涨停', count: limitUp, color: AppColors.limitUp),
      StatsInterval(label: '>5%', count: up5, color: AppColors.up5),
      StatsInterval(label: '0~5%', count: up0to5, color: AppColors.up0to5),
      StatsInterval(label: '平', count: flat, color: AppColors.flat),
      StatsInterval(label: '-5~0', count: down0to5, color: AppColors.down0to5),
      StatsInterval(label: '<-5%', count: down5, color: AppColors.down5),
      StatsInterval(label: '跌停', count: limitDown, color: AppColors.limitDown),
    ];
  }

  /// 计算量比分布
  (int above, int below) _calculateRatioDistribution() {
    int above = 0;
    int below = 0;
    for (final stock in stocks) {
      if (stock.ratio >= 1.0) {
        above++;
      } else {
        below++;
      }
    }
    return (above, below);
  }

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty) return const SizedBox.shrink();

    final changeStats = _calculateChangeDistribution();
    final (ratioAbove, ratioBelow) = _calculateRatioDistribution();
    final total = stocks.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 涨跌分布
          _buildChangeRow(context, changeStats),
          const SizedBox(height: 8),
          // 量比分布
          _buildRatioRow(context, ratioAbove, ratioBelow, total),
        ],
      ),
    );
  }

  Widget _buildChangeRow(BuildContext context, List<StatsInterval> stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签和数字行 - 等宽布局，确保标签不会被压缩
        Row(
          children: stats.map((s) => Expanded(
            child: Text(
              '${s.label}\n${s.count}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: s.count > 0
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 4),
        // 进度条 - 按比例显示
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: () {
              final nonZeroStats = stats.where((s) => s.count > 0).toList();
              return nonZeroStats.asMap().entries.map((entry) {
                final index = entry.key;
                final s = entry.value;
                final isLast = index == nonZeroStats.length - 1;
                return Expanded(
                  flex: s.count,
                  child: Container(
                    height: 8,
                    margin: isLast ? null : const EdgeInsets.only(right: 1),
                    color: s.color,
                  ),
                );
              }).toList();
            }(),
          ),
        ),
      ],
    );
  }

  Widget _buildRatioRow(BuildContext context, int above, int below, int total) {
    final abovePercent = total > 0 ? (above / total * 100).toStringAsFixed(0) : '0';
    final belowPercent = total > 0 ? (below / total * 100).toStringAsFixed(0) : '0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签行 - 等宽布局
        Row(
          children: [
            Expanded(
              child: Text(
                '量比>1: $above ($abovePercent%)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '量比<1: $below ($belowPercent%)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 进度条 - 按比例显示
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              if (above > 0)
                Expanded(
                  flex: above,
                  child: Container(
                    height: 8,
                    color: AppColors.stockUp,
                  ),
                ),
              if (below > 0)
                Expanded(
                  flex: below,
                  child: Container(
                    height: 8,
                    color: AppColors.stockDown,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
