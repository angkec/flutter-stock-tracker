/// 联动K线来源面板
enum LinkedPane { weekly, daily }

/// 联动触摸阶段
enum LinkedTouchPhase { start, update, end }

/// 联动状态（由协调器维护）
class LinkedCrosshairState {
  final LinkedPane sourcePane;
  final DateTime anchorDate;
  final double anchorPrice;
  final bool isLinking;

  const LinkedCrosshairState({
    required this.sourcePane,
    required this.anchorDate,
    required this.anchorPrice,
    required this.isLinking,
  });

  LinkedCrosshairState copyWith({
    LinkedPane? sourcePane,
    DateTime? anchorDate,
    double? anchorPrice,
    bool? isLinking,
  }) {
    return LinkedCrosshairState(
      sourcePane: sourcePane ?? this.sourcePane,
      anchorDate: anchorDate ?? this.anchorDate,
      anchorPrice: anchorPrice ?? this.anchorPrice,
      isLinking: isLinking ?? this.isLinking,
    );
  }
}

/// 联动触摸事件
class LinkedTouchEvent {
  final LinkedPane pane;
  final LinkedTouchPhase phase;
  final DateTime date;
  final double price;
  final int barIndex;

  const LinkedTouchEvent({
    required this.pane,
    required this.phase,
    required this.date,
    required this.price,
    required this.barIndex,
  });
}
