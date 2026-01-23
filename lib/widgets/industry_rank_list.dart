import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_rank.dart';
import 'package:stock_rtwatcher/screens/industry_detail_screen.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/widgets/sparkline_chart.dart';

/// 行业排名趋势列表组件
class IndustryRankList extends StatelessWidget {
  static const List<int> _dayOptions = [5, 10, 20];

  const IndustryRankList({super.key});

  @override
  Widget build(BuildContext context) {
    final rankService = context.watch<IndustryRankService>();
    final config = rankService.config;
    final histories = rankService.getAllRankHistories(config.displayDays);

    if (histories.isEmpty && !rankService.isLoading) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 时间段切换按钮组
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Text('排名趋势', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              ..._dayOptions.map((days) => Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _DayChip(
                  days: days,
                  isSelected: config.displayDays == days,
                  onTap: () => rankService.updateConfig(
                    config.copyWith(displayDays: days),
                  ),
                ),
              )),
            ],
          ),
        ),
        // 表头
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: const Row(
            children: [
              SizedBox(width: 28, child: Text('排名', style: TextStyle(fontSize: 10))),
              SizedBox(width: 56, child: Text('行业', style: TextStyle(fontSize: 10))),
              SizedBox(width: 40, child: Text('量比', style: TextStyle(fontSize: 10))),
              Spacer(),
              SizedBox(
                width: 64,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('趋势', style: TextStyle(fontSize: 10)),
                ),
              ),
            ],
          ),
        ),
        // 排名列表
        if (rankService.isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          ...histories.take(20).map((history) => _RankRow(
            history: history,
            config: config,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IndustryDetailScreen(industry: history.industryName),
              ),
            ),
          )),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  final int days;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayChip({
    required this.days,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$days日',
          style: TextStyle(
            fontSize: 11,
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final IndustryRankHistory history;
  final IndustryRankConfig config;
  final VoidCallback onTap;

  const _RankRow({
    required this.history,
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rank = history.currentRank ?? 0;
    final ratio = history.currentRatio ?? 0.0;
    final change = history.rankChange ?? 0;
    final isHot = history.isInHotZone(config.hotZoneTopN);
    final isRecovery = history.isInRecoveryZone(config);

    // 背景颜色
    Color? bgColor;
    if (isHot) {
      bgColor = Colors.orange.withValues(alpha: 0.08);
    } else if (isRecovery) {
      bgColor = Colors.cyan.withValues(alpha: 0.08);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            left: BorderSide(
              color: isHot
                  ? Colors.orange
                  : isRecovery
                      ? Colors.cyan
                      : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // 排名
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isHot ? Colors.orange : null,
                ),
              ),
            ),
            // 行业名
            SizedBox(
              width: 56,
              child: Text(
                history.industryName,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 量比
            SizedBox(
              width: 40,
              child: Text(
                ratio.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 11,
                  color: ratio >= 1.0 ? const Color(0xFFFF4444) : const Color(0xFF00AA00),
                ),
              ),
            ),
            // 排名变化标记
            SizedBox(
              width: 28,
              child: _ChangeIndicator(change: change),
            ),
            // Sparkline
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: history.rankSeries.length >= 2
                    ? SparklineChart(
                        data: history.rankSeries,
                        width: 56,
                        height: 20,
                      )
                    : const Text('-', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeIndicator extends StatelessWidget {
  final int change;

  const _ChangeIndicator({required this.change});

  @override
  Widget build(BuildContext context) {
    if (change == 0) {
      return const Text('→', style: TextStyle(fontSize: 10, color: Colors.grey));
    }

    final isUp = change > 0;
    return Text(
      '${isUp ? "↑" : "↓"}${change.abs()}',
      style: TextStyle(
        fontSize: 9,
        color: isUp ? const Color(0xFFFF4444) : const Color(0xFF00AA00),
      ),
    );
  }
}
