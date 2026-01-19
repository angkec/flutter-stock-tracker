import 'package:flutter/material.dart';

/// 市场状态枚举
enum MarketStatus {
  preMarket, // 盘前
  morningTrading, // 上午交易
  lunchBreak, // 午休
  afternoonTrading, // 下午交易
  closed, // 已收盘
}

/// 获取当前市场状态
MarketStatus getCurrentMarketStatus() {
  final now = DateTime.now();
  final weekday = now.weekday;
  final hour = now.hour;
  final minute = now.minute;
  final timeMinutes = hour * 60 + minute;

  // 周末休市
  if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
    return MarketStatus.closed;
  }

  // 盘前 (9:15 之前)
  if (timeMinutes < 9 * 60 + 15) {
    return MarketStatus.preMarket;
  }

  // 上午交易 (9:30 - 11:30)
  if (timeMinutes >= 9 * 60 + 30 && timeMinutes < 11 * 60 + 30) {
    return MarketStatus.morningTrading;
  }

  // 午休 (11:30 - 13:00)
  if (timeMinutes >= 11 * 60 + 30 && timeMinutes < 13 * 60) {
    return MarketStatus.lunchBreak;
  }

  // 下午交易 (13:00 - 15:00)
  if (timeMinutes >= 13 * 60 && timeMinutes < 15 * 60) {
    return MarketStatus.afternoonTrading;
  }

  // 收盘
  return MarketStatus.closed;
}

/// 获取市场状态文本
String getMarketStatusText(MarketStatus status) {
  switch (status) {
    case MarketStatus.preMarket:
      return '盘前';
    case MarketStatus.morningTrading:
      return '交易中';
    case MarketStatus.lunchBreak:
      return '午休';
    case MarketStatus.afternoonTrading:
      return '交易中';
    case MarketStatus.closed:
      return '已收盘';
  }
}

/// 获取市场状态颜色
Color getMarketStatusColor(MarketStatus status) {
  switch (status) {
    case MarketStatus.preMarket:
      return Colors.orange;
    case MarketStatus.morningTrading:
    case MarketStatus.afternoonTrading:
      return Colors.green;
    case MarketStatus.lunchBreak:
      return Colors.yellow;
    case MarketStatus.closed:
      return Colors.grey;
  }
}

/// 状态栏组件
class StatusBar extends StatelessWidget {
  final String? updateTime;
  final int? progress;
  final int? total;
  final bool isLoading;
  final String? errorMessage;

  const StatusBar({
    super.key,
    this.updateTime,
    this.progress,
    this.total,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final marketStatus = getCurrentMarketStatus();
    final statusText = getMarketStatusText(marketStatus);
    final statusColor = getMarketStatusColor(marketStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          // 标题
          Text(
            'A股涨跌量比监控',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 16),
          // 市场状态
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // 错误信息
          if (errorMessage != null) ...[
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 16),
          ],
          // 加载进度
          if (isLoading && progress != null && total != null) ...[
            SizedBox(
              width: 150,
              child: LinearProgressIndicator(
                value: total! > 0 ? progress! / total! : 0,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$progress / $total',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 16),
          ] else if (isLoading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
          ],
          // 更新时间
          if (updateTime != null)
            Text(
              '更新: $updateTime',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}
