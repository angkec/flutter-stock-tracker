import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/power_system_point.dart';

/// 动力系统状态指示器 - 显示最近5天的状态
class PowerSystemStateIndicator extends StatelessWidget {
  final List<PowerSystemDayState> states;
  final double iconSize;

  const PowerSystemStateIndicator({
    super.key,
    required this.states,
    this.iconSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (states.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: states.map((state) => _buildIcon(state)).toList(),
    );
  }

  Widget _buildIcon(PowerSystemDayState state) {
    switch (state.state) {
      case PowerSystemDailyState.bullish:
        // 向上红箭头 - 上涨
        return Icon(
          Icons.arrow_upward,
          color: Colors.red.shade700,
          size: iconSize,
        );
      case PowerSystemDailyState.bearish:
        // 向下绿箭头 - 下跌
        return Icon(
          Icons.arrow_downward,
          color: Colors.green.shade700,
          size: iconSize,
        );
      case PowerSystemDailyState.divergent:
        // 蓝色方块 - 分歧
        return Container(
          width: iconSize,
          height: iconSize,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            borderRadius: BorderRadius.circular(2),
          ),
        );
    }
  }
}
