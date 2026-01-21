/// 高质量回踩配置
class PullbackConfig {
  /// 昨日高量倍数（昨日成交量 > 前5日均量 × 此值）
  final double volumeMultiplier;

  /// 昨日最小涨幅（昨日收盘 > 昨日开盘 × (1 + 此值)）
  final double minYesterdayGain;

  /// 最大跌幅比例（今日跌幅 < 昨日涨幅 × 此值）
  final double maxDropRatio;

  /// 最小日K量比
  final double minDailyRatio;

  const PullbackConfig({
    this.volumeMultiplier = 1.5,
    this.minYesterdayGain = 0.03,
    this.maxDropRatio = 0.5,
    this.minDailyRatio = 0.85,
  });

  /// 默认配置
  static const PullbackConfig defaults = PullbackConfig();

  PullbackConfig copyWith({
    double? volumeMultiplier,
    double? minYesterdayGain,
    double? maxDropRatio,
    double? minDailyRatio,
  }) {
    return PullbackConfig(
      volumeMultiplier: volumeMultiplier ?? this.volumeMultiplier,
      minYesterdayGain: minYesterdayGain ?? this.minYesterdayGain,
      maxDropRatio: maxDropRatio ?? this.maxDropRatio,
      minDailyRatio: minDailyRatio ?? this.minDailyRatio,
    );
  }

  Map<String, dynamic> toJson() => {
    'volumeMultiplier': volumeMultiplier,
    'minYesterdayGain': minYesterdayGain,
    'maxDropRatio': maxDropRatio,
    'minDailyRatio': minDailyRatio,
  };

  factory PullbackConfig.fromJson(Map<String, dynamic> json) => PullbackConfig(
    volumeMultiplier: (json['volumeMultiplier'] as num?)?.toDouble() ?? 1.5,
    minYesterdayGain: (json['minYesterdayGain'] as num?)?.toDouble() ?? 0.03,
    maxDropRatio: (json['maxDropRatio'] as num?)?.toDouble() ?? 0.5,
    minDailyRatio: (json['minDailyRatio'] as num?)?.toDouble() ?? 0.85,
  );
}
