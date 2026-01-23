/// 行业排名显示与区域检测配置
class IndustryRankConfig {
  /// 热门区域：排名前 N 名
  final int hotZoneTopN;

  /// 复苏区域：最大排名（排名 <= 此值才可能是复苏区）
  final int recoveryZoneMaxRank;

  /// 复苏区域：量比增长百分比阈值
  final double recoveryRatioGrowthPercent;

  /// 复苏区域：回看天数
  final int recoveryLookbackDays;

  /// 当前显示周期（天数）
  final int displayDays;

  const IndustryRankConfig({
    this.hotZoneTopN = 5,
    this.recoveryZoneMaxRank = 20,
    this.recoveryRatioGrowthPercent = 30.0,
    this.recoveryLookbackDays = 5,
    this.displayDays = 10,
  });

  IndustryRankConfig copyWith({
    int? hotZoneTopN,
    int? recoveryZoneMaxRank,
    double? recoveryRatioGrowthPercent,
    int? recoveryLookbackDays,
    int? displayDays,
  }) {
    return IndustryRankConfig(
      hotZoneTopN: hotZoneTopN ?? this.hotZoneTopN,
      recoveryZoneMaxRank: recoveryZoneMaxRank ?? this.recoveryZoneMaxRank,
      recoveryRatioGrowthPercent:
          recoveryRatioGrowthPercent ?? this.recoveryRatioGrowthPercent,
      recoveryLookbackDays: recoveryLookbackDays ?? this.recoveryLookbackDays,
      displayDays: displayDays ?? this.displayDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'hotZoneTopN': hotZoneTopN,
        'recoveryZoneMaxRank': recoveryZoneMaxRank,
        'recoveryRatioGrowthPercent': recoveryRatioGrowthPercent,
        'recoveryLookbackDays': recoveryLookbackDays,
        'displayDays': displayDays,
      };

  factory IndustryRankConfig.fromJson(Map<String, dynamic> json) =>
      IndustryRankConfig(
        hotZoneTopN: (json['hotZoneTopN'] as int?) ?? 5,
        recoveryZoneMaxRank: (json['recoveryZoneMaxRank'] as int?) ?? 20,
        recoveryRatioGrowthPercent:
            (json['recoveryRatioGrowthPercent'] as num?)?.toDouble() ?? 30.0,
        recoveryLookbackDays: (json['recoveryLookbackDays'] as int?) ?? 5,
        displayDays: (json['displayDays'] as int?) ?? 10,
      );
}

/// 单日行业排名记录
class IndustryRankRecord {
  /// 日期（YYYY-MM-DD）
  final String date;

  /// 聚合量比（涨量之和 / 跌量之和）
  final double ratio;

  /// 排名（1-based，1=最高）
  final int rank;

  const IndustryRankRecord({
    required this.date,
    required this.ratio,
    required this.rank,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'ratio': ratio,
        'rank': rank,
      };

  factory IndustryRankRecord.fromJson(Map<String, dynamic> json) =>
      IndustryRankRecord(
        date: json['date'] as String,
        ratio: (json['ratio'] as num).toDouble(),
        rank: json['rank'] as int,
      );
}

/// 行业排名历史
class IndustryRankHistory {
  /// 行业名称
  final String industryName;

  /// 排名记录列表（按日期升序排列）
  final List<IndustryRankRecord> records;

  const IndustryRankHistory({
    required this.industryName,
    required this.records,
  });

  /// 当前排名（最新一天的排名）
  int? get currentRank => records.isNotEmpty ? records.last.rank : null;

  /// 当前量比（最新一天的量比）
  double? get currentRatio => records.isNotEmpty ? records.last.ratio : null;

  /// 排名变化（正数=排名上升，相对于第一条记录）
  int? get rankChange {
    if (records.length < 2) return null;
    // 排名数值越小越好，所以 first.rank - last.rank 为正表示排名上升
    return records.first.rank - records.last.rank;
  }

  /// 排名序列（取反，用于 sparkline 展示：排名越高则值越大，视觉上向上）
  List<double> get rankSeries =>
      records.map((r) => -r.rank.toDouble()).toList();

  /// 是否处于热门区域
  bool isInHotZone(int topN) {
    final rank = currentRank;
    if (rank == null) return false;
    return rank <= topN;
  }

  /// 是否处于复苏区域
  /// 条件：不在热门区、排名 <= recoveryZoneMaxRank、量比增长 >= 阈值
  bool isInRecoveryZone(IndustryRankConfig config) {
    if (isInHotZone(config.hotZoneTopN)) return false;

    final rank = currentRank;
    if (rank == null || rank > config.recoveryZoneMaxRank) return false;

    if (records.length < 2) return false;

    // 确定回看起点
    final lookbackIndex = records.length - 1 - config.recoveryLookbackDays;
    final startIndex = lookbackIndex >= 0 ? lookbackIndex : 0;
    final startRatio = records[startIndex].ratio;

    if (startRatio <= 0) return false;

    final currentRatioValue = records.last.ratio;
    final growthPercent =
        ((currentRatioValue - startRatio) / startRatio) * 100.0;

    return growthPercent >= config.recoveryRatioGrowthPercent;
  }
}
