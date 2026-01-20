import 'package:flutter/material.dart';

/// 板块热度颜色
const Color _hotColor = Color(0xFFFF4444);   // 量比>=1 红
const Color _coldColor = Color(0xFF00AA00);  // 量比<1 绿

/// 板块热度条组件
/// 显示行业名称和红绿进度条
class IndustryHeatBar extends StatelessWidget {
  final String industryName;
  final int hotCount;   // 量比 >= 1 的股票数量
  final int coldCount;  // 量比 < 1 的股票数量

  const IndustryHeatBar({
    super.key,
    required this.industryName,
    required this.hotCount,
    required this.coldCount,
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
                '板块热度',
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
          // 进度条
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
}
