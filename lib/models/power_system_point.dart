class PowerSystemPoint {
  const PowerSystemPoint({required this.datetime, required this.state});

  final DateTime datetime;
  final int state;

  Map<String, dynamic> toJson() => {
    'datetime': datetime.toIso8601String(),
    'state': state,
  };

  factory PowerSystemPoint.fromJson(Map<String, dynamic> json) {
    return PowerSystemPoint(
      datetime: DateTime.parse(json['datetime'] as String),
      state: json['state'] as int,
    );
  }
}

/// 双增标记状态类型
enum PowerSystemDailyState {
  /// 日周双涨（上涨）- 红色向上箭头
  bullish,

  /// 日周双跌（下跌）- 绿色向下箭头
  bearish,

  /// 日周分歧（方向相反）- 蓝色方块
  divergent,
}

/// 某一天的双增状态
class PowerSystemDayState {
  final PowerSystemDailyState state;
  final DateTime date;
  final int dailyState;
  final int weeklyState;

  const PowerSystemDayState({
    required this.state,
    required this.date,
    required this.dailyState,
    required this.weeklyState,
  });

  /// 从日周状态计算
  factory PowerSystemDayState.fromStates({
    required DateTime date,
    required int dailyState,
    required int weeklyState,
  }) {
    PowerSystemDailyState state;
    if (dailyState == 1 && weeklyState == 1) {
      state = PowerSystemDailyState.bullish;
    } else if (dailyState == -1 && weeklyState == -1) {
      state = PowerSystemDailyState.bearish;
    } else {
      state = PowerSystemDailyState.divergent;
    }

    return PowerSystemDayState(
      state: state,
      date: date,
      dailyState: dailyState,
      weeklyState: weeklyState,
    );
  }
}
