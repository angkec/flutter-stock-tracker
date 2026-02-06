import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/data_management_screen.dart';

class RefreshStatusWidget extends StatelessWidget {
  const RefreshStatusWidget({super.key});

  /// 用于 Flutter Driver 测试的 Key
  static const refreshButtonKey = ValueKey<String>('refresh_status_widget');

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketDataProvider>(
      builder: (_, provider, __) {
        return GestureDetector(
          key: refreshButtonKey,
          onTap: () {
            if (!provider.isLoading) {
              provider.refresh();
            }
          },
          onLongPress: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataManagementScreen()),
            );
          },
          child: _buildContent(context, provider),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, MarketDataProvider provider) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    // 错误状态
    if (provider.stage == RefreshStage.error) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.orange, size: 18),
          const SizedBox(width: 4),
          Text(
            provider.stageDescription ?? '刷新失败',
            style: theme.textTheme.bodySmall?.copyWith(color: textColor),
          ),
        ],
      );
    }

    // 刷新中
    if (provider.isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: textColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            provider.stageDescription ?? '刷新中...',
            style: theme.textTheme.bodySmall?.copyWith(color: textColor),
          ),
        ],
      );
    }

    // 空闲状态
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          provider.updateTime ?? '--:--:--',
          style: theme.textTheme.bodySmall?.copyWith(color: textColor),
        ),
        const SizedBox(width: 4),
        Icon(Icons.refresh, size: 18, color: textColor),
      ],
    );
  }
}
