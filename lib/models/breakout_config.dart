/// 跌幅参考点枚举
enum DropReferencePoint {
  /// 以突破日收盘价为参考
  breakoutClose,
  /// 以突破日最高价为参考
  breakoutHigh,
}

/// 放量突破配置
class BreakoutConfig {
  // === 突破日条件 ===
  /// 突破日放量倍数（突破日成交量 > 前5日均量 × 此值）
  final double breakVolumeMultiplier;

  /// 突破N日均线（收盘价 > N日均线，0=不检测）
  final int maBreakDays;

  /// 突破前N日高点（收盘价 > 前N日最高价，0=不检测）
  final int highBreakDays;

  /// 最大上引线比例（上引线长度 / 实体长度，0=不检测）
  final double maxUpperShadowRatio;

  // === 回踩阶段条件 ===
  /// 最小回踩天数
  final int minPullbackDays;

  /// 最大回踩天数
  final int maxPullbackDays;

  /// 最大总跌幅（回踩期间总跌幅）
  final double maxTotalDrop;

  /// 跌幅参考点
  final DropReferencePoint dropReferencePoint;

  /// 最大平均量比（回踩期间平均成交量 / 突破日成交量）
  final double maxAvgVolumeRatio;

  /// 最小分钟量比（今日分钟涨跌量比）
  final double minMinuteRatio;

  /// 是否过滤回踩后暴涨
  final bool filterSurgeAfterPullback;

  /// 暴涨阈值（今日涨幅超过此值视为暴涨）
  final double surgeThreshold;

  const BreakoutConfig({
    this.breakVolumeMultiplier = 1.5,
    this.maBreakDays = 20,
    this.highBreakDays = 5,
    this.maxUpperShadowRatio = 0,
    this.minPullbackDays = 1,
    this.maxPullbackDays = 5,
    this.maxTotalDrop = 0.10,
    this.dropReferencePoint = DropReferencePoint.breakoutClose,
    this.maxAvgVolumeRatio = 0.7,
    this.minMinuteRatio = 1.0,
    this.filterSurgeAfterPullback = false,
    this.surgeThreshold = 0.05,
  });

  /// 默认配置
  static const BreakoutConfig defaults = BreakoutConfig();

  BreakoutConfig copyWith({
    double? breakVolumeMultiplier,
    int? maBreakDays,
    int? highBreakDays,
    double? maxUpperShadowRatio,
    int? minPullbackDays,
    int? maxPullbackDays,
    double? maxTotalDrop,
    DropReferencePoint? dropReferencePoint,
    double? maxAvgVolumeRatio,
    double? minMinuteRatio,
    bool? filterSurgeAfterPullback,
    double? surgeThreshold,
  }) {
    return BreakoutConfig(
      breakVolumeMultiplier: breakVolumeMultiplier ?? this.breakVolumeMultiplier,
      maBreakDays: maBreakDays ?? this.maBreakDays,
      highBreakDays: highBreakDays ?? this.highBreakDays,
      maxUpperShadowRatio: maxUpperShadowRatio ?? this.maxUpperShadowRatio,
      minPullbackDays: minPullbackDays ?? this.minPullbackDays,
      maxPullbackDays: maxPullbackDays ?? this.maxPullbackDays,
      maxTotalDrop: maxTotalDrop ?? this.maxTotalDrop,
      dropReferencePoint: dropReferencePoint ?? this.dropReferencePoint,
      maxAvgVolumeRatio: maxAvgVolumeRatio ?? this.maxAvgVolumeRatio,
      minMinuteRatio: minMinuteRatio ?? this.minMinuteRatio,
      filterSurgeAfterPullback: filterSurgeAfterPullback ?? this.filterSurgeAfterPullback,
      surgeThreshold: surgeThreshold ?? this.surgeThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
    'breakVolumeMultiplier': breakVolumeMultiplier,
    'maBreakDays': maBreakDays,
    'highBreakDays': highBreakDays,
    'maxUpperShadowRatio': maxUpperShadowRatio,
    'minPullbackDays': minPullbackDays,
    'maxPullbackDays': maxPullbackDays,
    'maxTotalDrop': maxTotalDrop,
    'dropReferencePoint': dropReferencePoint.index,
    'maxAvgVolumeRatio': maxAvgVolumeRatio,
    'minMinuteRatio': minMinuteRatio,
    'filterSurgeAfterPullback': filterSurgeAfterPullback,
    'surgeThreshold': surgeThreshold,
  };

  factory BreakoutConfig.fromJson(Map<String, dynamic> json) => BreakoutConfig(
    breakVolumeMultiplier: (json['breakVolumeMultiplier'] as num?)?.toDouble() ?? 1.5,
    maBreakDays: (json['maBreakDays'] as int?) ?? 20,
    highBreakDays: (json['highBreakDays'] as int?) ?? 5,
    maxUpperShadowRatio: (json['maxUpperShadowRatio'] as num?)?.toDouble() ?? 0,
    minPullbackDays: (json['minPullbackDays'] as int?) ?? 1,
    maxPullbackDays: (json['maxPullbackDays'] as int?) ?? 5,
    maxTotalDrop: (json['maxTotalDrop'] as num?)?.toDouble() ??
        (json['maxAvgDailyDrop'] as num?)?.toDouble() ?? 0.10,
    dropReferencePoint: DropReferencePoint.values[
        (json['dropReferencePoint'] as int?) ?? 0],
    maxAvgVolumeRatio: (json['maxAvgVolumeRatio'] as num?)?.toDouble() ?? 0.7,
    minMinuteRatio: (json['minMinuteRatio'] as num?)?.toDouble() ?? 1.0,
    filterSurgeAfterPullback: (json['filterSurgeAfterPullback'] as bool?) ?? false,
    surgeThreshold: (json['surgeThreshold'] as num?)?.toDouble() ?? 0.05,
  );
}
