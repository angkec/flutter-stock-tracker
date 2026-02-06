/// 跌幅参考点枚举
enum DropReferencePoint {
  /// 以突破日收盘价为参考
  breakoutClose,
  /// 以突破日最高价为参考
  breakoutHigh,
}

/// 突破参考点枚举（用于判断是否突破前N日高点）
enum BreakReferencePoint {
  /// 以突破日最高价为参考（默认）
  high,
  /// 以突破日收盘价为参考
  close,
}

/// 单项检测结果
class DetectionItem {
  final String name;
  final bool passed;
  final String? detail;

  const DetectionItem({
    required this.name,
    required this.passed,
    this.detail,
  });
}

/// 突破日检测结果
class BreakoutDetectionResult {
  /// 是否是上涨日
  final DetectionItem isUpDay;

  /// 放量检测
  final DetectionItem volumeCheck;

  /// 突破均线检测
  final DetectionItem? maBreakCheck;

  /// 突破前高检测
  final DetectionItem? highBreakCheck;

  /// 上引线检测
  final DetectionItem? upperShadowCheck;

  /// 分钟量比检测
  final DetectionItem? minuteRatioCheck;

  /// 回踩阶段检测结果（如果是突破日）
  final PullbackDetectionResult? pullbackResult;

  const BreakoutDetectionResult({
    required this.isUpDay,
    required this.volumeCheck,
    this.maBreakCheck,
    this.highBreakCheck,
    this.upperShadowCheck,
    this.minuteRatioCheck,
    this.pullbackResult,
  });

  /// 突破日条件是否全部通过
  bool get breakoutPassed =>
      isUpDay.passed &&
      volumeCheck.passed &&
      (maBreakCheck?.passed ?? true) &&
      (highBreakCheck?.passed ?? true) &&
      (upperShadowCheck?.passed ?? true) &&
      (minuteRatioCheck?.passed ?? true);

  /// 获取所有检测项
  List<DetectionItem> get allItems => [
        isUpDay,
        volumeCheck,
        if (maBreakCheck != null) maBreakCheck!,
        if (highBreakCheck != null) highBreakCheck!,
        if (upperShadowCheck != null) upperShadowCheck!,
        if (minuteRatioCheck != null) minuteRatioCheck!,
      ];
}

/// 回踩阶段检测结果
class PullbackDetectionResult {
  /// 回踩天数
  final int pullbackDays;

  /// 总跌幅检测
  final DetectionItem totalDropCheck;

  /// 单日跌幅检测
  final DetectionItem? singleDayDropCheck;

  /// 单日涨幅检测
  final DetectionItem? singleDayGainCheck;

  /// 总涨幅检测
  final DetectionItem? totalGainCheck;

  /// 平均量比检测
  final DetectionItem avgVolumeCheck;

  const PullbackDetectionResult({
    required this.pullbackDays,
    required this.totalDropCheck,
    this.singleDayDropCheck,
    this.singleDayGainCheck,
    this.totalGainCheck,
    required this.avgVolumeCheck,
  });

  /// 回踩条件是否全部通过
  bool get passed =>
      totalDropCheck.passed &&
      (singleDayDropCheck?.passed ?? true) &&
      (singleDayGainCheck?.passed ?? true) &&
      (totalGainCheck?.passed ?? true) &&
      avgVolumeCheck.passed;

  /// 获取所有检测项
  List<DetectionItem> get allItems => [
        totalDropCheck,
        if (singleDayDropCheck != null) singleDayDropCheck!,
        if (singleDayGainCheck != null) singleDayGainCheck!,
        if (totalGainCheck != null) totalGainCheck!,
        avgVolumeCheck,
      ];
}

/// 放量突破配置
class BreakoutConfig {
  // === 突破日条件 ===
  /// 突破日放量倍数（突破日成交量 > 前5日均量 × 此值）
  final double breakVolumeMultiplier;

  /// 突破N日均线（收盘价 > N日均线，0=不检测）
  final int maBreakDays;

  /// 突破前N日高点（0=不检测）
  final int highBreakDays;

  /// 突破参考点（判断是否突破前N日高点时使用）
  final BreakReferencePoint breakReferencePoint;

  /// 最大上引线比例（上引线长度 / 实体长度，0=不检测）
  final double maxUpperShadowRatio;

  /// 突破日最小分钟量比（0=不检测）
  final double minBreakoutMinuteRatio;

  // === 回踩阶段条件 ===
  /// 最小回踩天数
  final int minPullbackDays;

  /// 最大回踩天数
  final int maxPullbackDays;

  /// 最大总跌幅（回踩期间总跌幅）
  final double maxTotalDrop;

  /// 最大单日跌幅（回踩阶段单天相对于参考点的最大跌幅，0=不检测）
  final double maxSingleDayDrop;

  /// 最大单日涨幅（回踩阶段单天相对于参考点的最大涨幅，0=不检测）
  final double maxSingleDayGain;

  /// 最大总涨幅（回踩期间最大总涨幅，0=不检测）
  final double maxTotalGain;

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
    this.maBreakDays = 0,
    this.highBreakDays = 10,
    this.breakReferencePoint = BreakReferencePoint.high,
    this.maxUpperShadowRatio = 0.2,
    this.minBreakoutMinuteRatio = 0,
    this.minPullbackDays = 1,
    this.maxPullbackDays = 5,
    this.maxTotalDrop = 0.01,
    this.maxSingleDayDrop = 0.02,
    this.maxSingleDayGain = 0.01,
    this.maxTotalGain = 0.01,
    this.dropReferencePoint = DropReferencePoint.breakoutHigh,
    this.maxAvgVolumeRatio = 0.6,
    this.minMinuteRatio = 1.0,
    this.filterSurgeAfterPullback = true,
    this.surgeThreshold = 0.05,
  });

  /// 默认配置
  static const BreakoutConfig defaults = BreakoutConfig();

  BreakoutConfig copyWith({
    double? breakVolumeMultiplier,
    int? maBreakDays,
    int? highBreakDays,
    BreakReferencePoint? breakReferencePoint,
    double? maxUpperShadowRatio,
    double? minBreakoutMinuteRatio,
    int? minPullbackDays,
    int? maxPullbackDays,
    double? maxTotalDrop,
    double? maxSingleDayDrop,
    double? maxSingleDayGain,
    double? maxTotalGain,
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
      breakReferencePoint: breakReferencePoint ?? this.breakReferencePoint,
      maxUpperShadowRatio: maxUpperShadowRatio ?? this.maxUpperShadowRatio,
      minBreakoutMinuteRatio: minBreakoutMinuteRatio ?? this.minBreakoutMinuteRatio,
      minPullbackDays: minPullbackDays ?? this.minPullbackDays,
      maxPullbackDays: maxPullbackDays ?? this.maxPullbackDays,
      maxTotalDrop: maxTotalDrop ?? this.maxTotalDrop,
      maxSingleDayDrop: maxSingleDayDrop ?? this.maxSingleDayDrop,
      maxSingleDayGain: maxSingleDayGain ?? this.maxSingleDayGain,
      maxTotalGain: maxTotalGain ?? this.maxTotalGain,
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
    'breakReferencePoint': breakReferencePoint.index,
    'maxUpperShadowRatio': maxUpperShadowRatio,
    'minBreakoutMinuteRatio': minBreakoutMinuteRatio,
    'minPullbackDays': minPullbackDays,
    'maxPullbackDays': maxPullbackDays,
    'maxTotalDrop': maxTotalDrop,
    'maxSingleDayDrop': maxSingleDayDrop,
    'maxSingleDayGain': maxSingleDayGain,
    'maxTotalGain': maxTotalGain,
    'dropReferencePoint': dropReferencePoint.index,
    'maxAvgVolumeRatio': maxAvgVolumeRatio,
    'minMinuteRatio': minMinuteRatio,
    'filterSurgeAfterPullback': filterSurgeAfterPullback,
    'surgeThreshold': surgeThreshold,
  };

  factory BreakoutConfig.fromJson(Map<String, dynamic> json) => BreakoutConfig(
    breakVolumeMultiplier: (json['breakVolumeMultiplier'] as num?)?.toDouble() ?? 1.5,
    maBreakDays: (json['maBreakDays'] as int?) ?? 0,
    highBreakDays: (json['highBreakDays'] as int?) ?? 10,
    breakReferencePoint: BreakReferencePoint.values[
        (json['breakReferencePoint'] as int?) ?? 0],
    maxUpperShadowRatio: (json['maxUpperShadowRatio'] as num?)?.toDouble() ?? 0.2,
    minBreakoutMinuteRatio: (json['minBreakoutMinuteRatio'] as num?)?.toDouble() ?? 0,
    minPullbackDays: (json['minPullbackDays'] as int?) ?? 1,
    maxPullbackDays: (json['maxPullbackDays'] as int?) ?? 5,
    maxTotalDrop: (json['maxTotalDrop'] as num?)?.toDouble() ??
        (json['maxAvgDailyDrop'] as num?)?.toDouble() ?? 0.01,
    maxSingleDayDrop: (json['maxSingleDayDrop'] as num?)?.toDouble() ?? 0.02,
    maxSingleDayGain: (json['maxSingleDayGain'] as num?)?.toDouble() ?? 0.01,
    maxTotalGain: (json['maxTotalGain'] as num?)?.toDouble() ?? 0.01,
    dropReferencePoint: DropReferencePoint.values[
        (json['dropReferencePoint'] as int?) ?? 1],
    maxAvgVolumeRatio: (json['maxAvgVolumeRatio'] as num?)?.toDouble() ?? 0.6,
    minMinuteRatio: (json['minMinuteRatio'] as num?)?.toDouble() ?? 1.0,
    filterSurgeAfterPullback: (json['filterSurgeAfterPullback'] as bool?) ?? true,
    surgeThreshold: (json['surgeThreshold'] as num?)?.toDouble() ?? 0.05,
  );
}
