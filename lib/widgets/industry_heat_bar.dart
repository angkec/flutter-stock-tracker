import 'package:flutter/material.dart';

/// 板块热度颜色
const Color _hotColor = Color(0xFFFF4444);   // 量比>=1 红
const Color _coldColor = Color(0xFF00AA00);  // 量比<1 绿

/// 涨跌分布颜色（从涨停到跌停）
const List<Color> _changeColors = [
  Color(0xFFFF0000),  // 涨停
  Color(0xFFFF4444),  // >5%
  Color(0xFFFF8888),  // 0~5%
  Color(0xFF888888),  // 平
  Color(0xFF88CC88),  // -5~0
  Color(0xFF44AA44),  // <-5%
  Color(0xFF00AA00),  // 跌停
];

/// 涨跌分布标签
const List<String> _changeLabels = ['涨停', '>5%', '0~5%', '平', '-5~0', '<-5%', '跌停'];

/// 板块热度条组件
/// 显示行业名称、涨跌分布和量比热度
class IndustryHeatBar extends StatelessWidget {
  final String industryName;
  final int hotCount;   // 量比 >= 1 的股票数量
  final int coldCount;  // 量比 < 1 的股票数量
  final List<int>? changeDistribution;  // 涨跌分布 [涨停, >5%, 0~5%, 平, -5~0, <-5%, 跌停]

  const IndustryHeatBar({
    super.key,
    required this.industryName,
    required this.hotCount,
    required this.coldCount,
    this.changeDistribution,
  });

  @override
  Widget build(BuildContext context) {
    final total = hotCount + coldCount;
    final hotRatio = total > 0 ? hotCount / total : 0.5;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Text(
                '板块',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                industryName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 涨跌分布条
          if (changeDistribution != null) ...[
            _buildChangeDistributionBar(context),
            const SizedBox(height: 8),
          ],
          // 量比热度条
          Row(
            children: [
              // 红色数量
              Text(
                '$hotCount',
                style: const TextStyle(
                  color: _hotColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              // 进度条
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        // 红色部分
                        Expanded(
                          flex: (hotRatio * 100).round().clamp(1, 99),
                          child: Container(color: _hotColor),
                        ),
                        // 绿色部分
                        Expanded(
                          flex: ((1 - hotRatio) * 100).round().clamp(1, 99),
                          child: Container(color: _coldColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 绿色数量
              Text(
                '$coldCount',
                style: const TextStyle(
                  color: _coldColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建涨跌分布条
  Widget _buildChangeDistributionBar(BuildContext context) {
    final dist = changeDistribution!;

    return Column(
      children: [
        // 标签和数字行
        Row(
          children: List.generate(7, (i) {
            final count = dist[i];
            return Expanded(
              child: Text(
                '${_changeLabels[i]}\n$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: count > 0
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: List.generate(7, (i) {
                final count = dist[i];
                if (count == 0) return const SizedBox.shrink();
                return Expanded(
                  flex: count,
                  child: Container(color: _changeColors[i]),
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}
