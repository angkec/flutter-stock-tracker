/// 买入价基准枚举
enum BuyPriceReference {
  /// 突破日最高价（默认）
  breakoutHigh,

  /// 突破日收盘价
  breakoutClose,

  /// 回踩期间平均价
  pullbackAverage,

  /// 回踩期间最低价
  pullbackLow,
}

/// 回测配置
class BacktestConfig {
  /// 观察周期档位（天数列表）
  final List<int> observationDays;

  /// 目标涨幅（成功阈值）
  final double targetGain;

  /// 买入价基准
  final BuyPriceReference buyPriceReference;

  const BacktestConfig({
    this.observationDays = const [3, 5, 10],
    this.targetGain = 0.05,
    this.buyPriceReference = BuyPriceReference.breakoutHigh,
  });

  /// 默认配置
  static const BacktestConfig defaults = BacktestConfig();

  BacktestConfig copyWith({
    List<int>? observationDays,
    double? targetGain,
    BuyPriceReference? buyPriceReference,
  }) {
    return BacktestConfig(
      observationDays: observationDays ?? this.observationDays,
      targetGain: targetGain ?? this.targetGain,
      buyPriceReference: buyPriceReference ?? this.buyPriceReference,
    );
  }

  Map<String, dynamic> toJson() => {
        'observationDays': observationDays,
        'targetGain': targetGain,
        'buyPriceReference': buyPriceReference.index,
      };

  factory BacktestConfig.fromJson(Map<String, dynamic> json) => BacktestConfig(
        observationDays: (json['observationDays'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            const [3, 5, 10],
        targetGain: (json['targetGain'] as num?)?.toDouble() ?? 0.05,
        buyPriceReference: BuyPriceReference
            .values[(json['buyPriceReference'] as int?) ?? 0],
      );
}

/// 单周期统计结果
class PeriodStats {
  /// 观察天数
  final int days;

  /// 成功次数
  final int successCount;

  /// 成功率
  final double successRate;

  /// 平均最高涨幅
  final double avgMaxGain;

  /// 平均最大回撤
  final double avgMaxDrawdown;

  const PeriodStats({
    required this.days,
    required this.successCount,
    required this.successRate,
    required this.avgMaxGain,
    required this.avgMaxDrawdown,
  });
}

/// 单个信号详情
class SignalDetail {
  /// 股票代码
  final String stockCode;

  /// 股票名称
  final String stockName;

  /// 突破日
  final DateTime breakoutDate;

  /// 信号触发日（回踩结束日）
  final DateTime signalDate;

  /// 买入价
  final double buyPrice;

  /// 各周期最高涨幅 {天数: 最高涨幅}
  final Map<int, double> maxGainByPeriod;

  /// 各周期是否成功 {天数: 是否成功}
  final Map<int, bool> successByPeriod;

  const SignalDetail({
    required this.stockCode,
    required this.stockName,
    required this.breakoutDate,
    required this.signalDate,
    required this.buyPrice,
    required this.maxGainByPeriod,
    required this.successByPeriod,
  });
}

/// 回测结果
class BacktestResult {
  /// 总信号数
  final int totalSignals;

  /// 各周期统计
  final List<PeriodStats> periodStats;

  /// 信号详情列表
  final List<SignalDetail> signals;

  /// 所有最高涨幅（用于分布图）
  final List<double> allMaxGains;

  const BacktestResult({
    required this.totalSignals,
    required this.periodStats,
    required this.signals,
    required this.allMaxGains,
  });
}
