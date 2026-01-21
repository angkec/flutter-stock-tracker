/// 今日下跌条件模式
enum DropMode {
  /// 今日下跌（收盘 < 开盘）
  todayDown,
  /// 今日低于昨日最高点
  belowYesterdayHigh,
  /// 无条件
  none,
}

/// 高质量回踩配置
class PullbackConfig {
  /// 昨日高量倍数（昨日成交量 > 前5日均量 × 此值）
  final double volumeMultiplier;

  /// 昨日最小涨幅（昨日收盘 > 昨日开盘 × (1 + 此值)）
  final double minYesterdayGain;

  /// 最大跌幅比例（今日跌幅 < 昨日涨幅 × 此值）
  final double maxDropRatio;

  /// 最大日K量比（今日成交量 / 前5日均量）
  final double maxDailyRatio;

  /// 最小分钟涨跌量比（涨量/跌量）
  final double minMinuteRatio;

  /// 今日下跌条件模式
  final DropMode dropMode;

  const PullbackConfig({
    this.volumeMultiplier = 1.5,
    this.minYesterdayGain = 0.03,
    this.maxDropRatio = 0.5,
    this.maxDailyRatio = 0.85,
    this.minMinuteRatio = 0.8,
    this.dropMode = DropMode.todayDown,
  });

  /// 默认配置
  static const PullbackConfig defaults = PullbackConfig();

  PullbackConfig copyWith({
    double? volumeMultiplier,
    double? minYesterdayGain,
    double? maxDropRatio,
    double? maxDailyRatio,
    double? minMinuteRatio,
    DropMode? dropMode,
  }) {
    return PullbackConfig(
      volumeMultiplier: volumeMultiplier ?? this.volumeMultiplier,
      minYesterdayGain: minYesterdayGain ?? this.minYesterdayGain,
      maxDropRatio: maxDropRatio ?? this.maxDropRatio,
      maxDailyRatio: maxDailyRatio ?? this.maxDailyRatio,
      minMinuteRatio: minMinuteRatio ?? this.minMinuteRatio,
      dropMode: dropMode ?? this.dropMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'volumeMultiplier': volumeMultiplier,
    'minYesterdayGain': minYesterdayGain,
    'maxDropRatio': maxDropRatio,
    'maxDailyRatio': maxDailyRatio,
    'minMinuteRatio': minMinuteRatio,
    'dropMode': dropMode.index,
  };

  factory PullbackConfig.fromJson(Map<String, dynamic> json) => PullbackConfig(
    volumeMultiplier: (json['volumeMultiplier'] as num?)?.toDouble() ?? 1.5,
    minYesterdayGain: (json['minYesterdayGain'] as num?)?.toDouble() ?? 0.03,
    maxDropRatio: (json['maxDropRatio'] as num?)?.toDouble() ?? 0.5,
    maxDailyRatio: (json['maxDailyRatio'] as num?)?.toDouble() ?? 0.85,
    minMinuteRatio: (json['minMinuteRatio'] as num?)?.toDouble() ?? 0.8,
    dropMode: DropMode.values[(json['dropMode'] as int?) ?? 0],
  );
}
