class IndustryScoreConfig {
  final double b0;
  final double b1;
  final double minGate;
  final double maxGate;
  final double alpha;

  const IndustryScoreConfig({
    this.b0 = 0.25,
    this.b1 = 0.50,
    this.minGate = 0.50,
    this.maxGate = 1.00,
    this.alpha = 0.30,
  });

  IndustryScoreConfig copyWith({
    double? b0,
    double? b1,
    double? minGate,
    double? maxGate,
    double? alpha,
  }) {
    return IndustryScoreConfig(
      b0: b0 ?? this.b0,
      b1: b1 ?? this.b1,
      minGate: minGate ?? this.minGate,
      maxGate: maxGate ?? this.maxGate,
      alpha: alpha ?? this.alpha,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'b0': b0,
      'b1': b1,
      'minGate': minGate,
      'maxGate': maxGate,
      'alpha': alpha,
    };
  }

  factory IndustryScoreConfig.fromJson(Map<String, dynamic> map) {
    return IndustryScoreConfig(
      b0: (map['b0'] as num?)?.toDouble() ?? 0.25,
      b1: (map['b1'] as num?)?.toDouble() ?? 0.50,
      minGate: (map['minGate'] as num?)?.toDouble() ?? 0.50,
      maxGate: (map['maxGate'] as num?)?.toDouble() ?? 1.00,
      alpha: (map['alpha'] as num?)?.toDouble() ?? 0.30,
    );
  }
}

class IndustryBuildupDailyRecord {
  final DateTime date;
  final String industry;
  final double zRel;
  final double zPos;
  final double breadth;
  final double breadthGate;
  final double q;
  final double rawScore;
  final double scoreEma;
  final double xI;
  final double xM;
  final int passedCount;
  final int memberCount;
  final int rank;
  final int rankChange;
  final String rankArrow;
  final DateTime updatedAt;

  const IndustryBuildupDailyRecord({
    required this.date,
    required this.industry,
    required this.zRel,
    this.zPos = 0.0,
    required this.breadth,
    this.breadthGate = 0.5,
    required this.q,
    this.rawScore = 0.0,
    this.scoreEma = 0.0,
    required this.xI,
    required this.xM,
    required this.passedCount,
    required this.memberCount,
    required this.rank,
    this.rankChange = 0,
    this.rankArrow = '→',
    required this.updatedAt,
  });

  DateTime get dateOnly => DateTime(date.year, date.month, date.day);

  Map<String, dynamic> toDbMap() {
    return {
      'date': dateOnly.millisecondsSinceEpoch,
      'industry': industry,
      'z_rel': zRel,
      'z_pos': zPos,
      'breadth': breadth,
      'breadth_gate': breadthGate,
      'q': q,
      'raw_score': rawScore,
      'score_ema': scoreEma,
      'x_i': xI,
      'x_m': xM,
      'passed_count': passedCount,
      'member_count': memberCount,
      'rank': rank,
      'rank_change': rankChange,
      'rank_arrow': rankArrow,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory IndustryBuildupDailyRecord.fromDbMap(Map<String, dynamic> map) {
    final zRel = (map['z_rel'] as num).toDouble();
    final rankChange = (map['rank_change'] as int?) ?? 0;
    return IndustryBuildupDailyRecord(
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      industry: map['industry'] as String,
      zRel: zRel,
      zPos: (map['z_pos'] as num?)?.toDouble() ?? (zRel > 0 ? zRel : 0.0),
      breadth: (map['breadth'] as num).toDouble(),
      breadthGate: (map['breadth_gate'] as num?)?.toDouble() ?? 0.5,
      q: (map['q'] as num).toDouble(),
      rawScore: (map['raw_score'] as num?)?.toDouble() ?? 0.0,
      scoreEma: (map['score_ema'] as num?)?.toDouble() ?? 0.0,
      xI: (map['x_i'] as num).toDouble(),
      xM: (map['x_m'] as num).toDouble(),
      passedCount: map['passed_count'] as int,
      memberCount: map['member_count'] as int,
      rank: map['rank'] as int,
      rankChange: rankChange,
      rankArrow:
          (map['rank_arrow'] as String?) ?? _rankArrowFromChange(rankChange),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  static String _rankArrowFromChange(int change) {
    if (change > 0) return '↑';
    if (change < 0) return '↓';
    return '→';
  }
}

class IndustryBuildupBoardItem {
  final IndustryBuildupDailyRecord record;
  final List<double> zRelTrend;
  final List<double> rawScoreTrend;
  final List<double> scoreEmaTrend;
  final List<double> rankTrend;

  const IndustryBuildupBoardItem({
    required this.record,
    this.zRelTrend = const [],
    this.rawScoreTrend = const [],
    this.scoreEmaTrend = const [],
    this.rankTrend = const [],
  });
}
