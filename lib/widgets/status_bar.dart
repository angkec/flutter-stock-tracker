import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/data_management_screen.dart';
import 'package:stock_rtwatcher/theme/theme.dart';

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
      return AppColors.statusPreMarket;
    case MarketStatus.morningTrading:
    case MarketStatus.afternoonTrading:
      return AppColors.statusTrading;
    case MarketStatus.lunchBreak:
      return AppColors.statusLunchBreak;
    case MarketStatus.closed:
      return AppColors.statusClosed;
  }
}

/// 判断是否是历史数据（数据日期不是今天）
bool _isHistoricalData(DateTime? dataDate) {
  if (dataDate == null) return false;
  final today = DateTime.now();
  return dataDate.year != today.year ||
      dataDate.month != today.month ||
      dataDate.day != today.day;
}

/// 状态栏组件
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MarketDataProvider>();
    final marketStatus = getCurrentMarketStatus();
    final statusColor = getMarketStatusColor(marketStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 400;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行: 标题 + 状态 + 时间 + 刷新/进度
              Row(
                children: [
                  // 市场状态指示点
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 标题
                  Text(
                    isNarrow ? '涨跌量比' : 'A股涨跌量比监控',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  // 更新时间
                  if (provider.updateTime != null && !provider.isLoading) ...[
                    Builder(
                      builder: (context) {
                        final isHistorical = _isHistoricalData(provider.dataDate);
                        final displayText = isHistorical
                            ? '${provider.dataDate!.month.toString().padLeft(2, '0')}-${provider.dataDate!.day.toString().padLeft(2, '0')} ${provider.updateTime!}'
                            : provider.updateTime!;
                        return Text(
                          displayText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isHistorical
                                    ? AppColors.statusPreMarket
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(width: 8),
                  // 右上角：刷新按钮 或 进度指示器
                  _buildRefreshArea(context, provider),
                ],
              ),
              // 第二行: 错误信息
              if (provider.errorMessage != null && !provider.isLoading) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        provider.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRefreshArea(BuildContext context, MarketDataProvider provider) {
    if (provider.isLoading) {
      // 加载中：显示小进度指示器 + 阶段描述
      return GestureDetector(
        onLongPress: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DataManagementScreen()),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text(
              provider.stageDescription ?? '${provider.progress}/${provider.total}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      );
    } else if (provider.errorMessage != null) {
      // 错误：显示橙色重试按钮
      return GestureDetector(
        onLongPress: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DataManagementScreen()),
          );
        },
        child: SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () => provider.refresh(),
            icon: const Icon(
              Icons.refresh,
              size: 20,
              color: Colors.orange,
            ),
            tooltip: '重试',
          ),
        ),
      );
    } else {
      // 空闲：显示刷新按钮
      return GestureDetector(
        onLongPress: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DataManagementScreen()),
          );
        },
        child: SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () => provider.refresh(),
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新数据 (长按管理缓存)',
          ),
        ),
      );
    }
  }
}
