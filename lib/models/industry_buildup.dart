class IndustryBuildupDailyRecord {
  final DateTime date;
  final String industry;
  final double zRel;
  final double breadth;
  final double q;
  final double xI;
  final double xM;
  final int passedCount;
  final int memberCount;
  final int rank;
  final DateTime updatedAt;

  const IndustryBuildupDailyRecord({
    required this.date,
    required this.industry,
    required this.zRel,
    required this.breadth,
    required this.q,
    required this.xI,
    required this.xM,
    required this.passedCount,
    required this.memberCount,
    required this.rank,
    required this.updatedAt,
  });

  DateTime get dateOnly => DateTime(date.year, date.month, date.day);

  Map<String, dynamic> toDbMap() {
    return {
      'date': dateOnly.millisecondsSinceEpoch,
      'industry': industry,
      'z_rel': zRel,
      'breadth': breadth,
      'q': q,
      'x_i': xI,
      'x_m': xM,
      'passed_count': passedCount,
      'member_count': memberCount,
      'rank': rank,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory IndustryBuildupDailyRecord.fromDbMap(Map<String, dynamic> map) {
    return IndustryBuildupDailyRecord(
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      industry: map['industry'] as String,
      zRel: (map['z_rel'] as num).toDouble(),
      breadth: (map['breadth'] as num).toDouble(),
      q: (map['q'] as num).toDouble(),
      xI: (map['x_i'] as num).toDouble(),
      xM: (map['x_m'] as num).toDouble(),
      passedCount: map['passed_count'] as int,
      memberCount: map['member_count'] as int,
      rank: map['rank'] as int,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}

class IndustryBuildupBoardItem {
  final IndustryBuildupDailyRecord record;
  final List<double> zRelTrend;

  const IndustryBuildupBoardItem({
    required this.record,
    required this.zRelTrend,
  });
}
