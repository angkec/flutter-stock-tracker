import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';

/// 量比颜色
const Color _upColor = Color(0xFFFF4444);   // ≥1 红
const Color _downColor = Color(0xFF00AA00); // <1 绿

/// 星期名称
const List<String> _weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 量比历史列表组件
class RatioHistoryList extends StatelessWidget {
  final List<DailyRatio> ratios;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const RatioHistoryList({
    super.key,
    required this.ratios,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      );
    }

    if (ratios.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂无数据')),
      );
    }

    // 计算统计数据
    final validRatios = ratios.where((r) => r.ratio != null).toList();
    final redCount = validRatios.where((r) => r.ratio! >= 1.0).length;
    final greenCount = validRatios.where((r) => r.ratio! < 1.0).length;
    final avgRatio = validRatios.isNotEmpty
        ? validRatios.map((r) => r.ratio!).reduce((a, b) => a + b) / validRatios.length
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '量比历史',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // 统计信息
              if (validRatios.isNotEmpty) ...[
                Text(
                  '均值 ',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  avgRatio!.toStringAsFixed(2),
                  style: TextStyle(
                    color: avgRatio >= 1.0 ? _upColor : _downColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$redCount',
                  style: const TextStyle(color: _upColor, fontWeight: FontWeight.w500, fontSize: 13),
                ),
                Text(
                  ':',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '$greenCount',
                  style: const TextStyle(color: _downColor, fontWeight: FontWeight.w500, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        ...ratios.map((r) => _buildRow(context, r)),
      ],
    );
  }

  Widget _buildRow(BuildContext context, DailyRatio ratio) {
    final dateStr = '${ratio.date.month.toString().padLeft(2, '0')}-${ratio.date.day.toString().padLeft(2, '0')}';
    final weekday = _weekdays[ratio.date.weekday];
    final ratioStr = ratio.ratio != null ? ratio.ratio!.toStringAsFixed(2) : '-';
    final color = ratio.ratio != null
        ? (ratio.ratio! >= 1.0 ? _upColor : _downColor)
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$dateStr $weekday',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          Text(
            ratioStr,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
