/// 每日量比占比数据点
class DailyRatioPoint {
  final DateTime date;
  final double ratioAbovePercent; // 量比>1股票占比 (0-100)
  final int totalStocks; // 行业总股票数
  final int ratioAboveCount; // 量比>1的股票数

  const DailyRatioPoint({
    required this.date,
    required this.ratioAbovePercent,
    required this.totalStocks,
    required this.ratioAboveCount,
  });

  DailyRatioPoint copyWith({
    DateTime? date,
    double? ratioAbovePercent,
    int? totalStocks,
    int? ratioAboveCount,
  }) {
    return DailyRatioPoint(
      date: date ?? this.date,
      ratioAbovePercent: ratioAbovePercent ?? this.ratioAbovePercent,
      totalStocks: totalStocks ?? this.totalStocks,
      ratioAboveCount: ratioAboveCount ?? this.ratioAboveCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'ratioAbovePercent': ratioAbovePercent,
    'totalStocks': totalStocks,
    'ratioAboveCount': ratioAboveCount,
  };

  factory DailyRatioPoint.fromJson(Map<String, dynamic> json) => DailyRatioPoint(
    date: DateTime.parse(json['date'] as String),
    ratioAbovePercent: (json['ratioAbovePercent'] as num).toDouble(),
    totalStocks: json['totalStocks'] as int,
    ratioAboveCount: json['ratioAboveCount'] as int,
  );
}

/// 行业趋势数据
class IndustryTrendData {
  final String industry; // 行业名称
  final List<DailyRatioPoint> points; // 每日数据点（按日期升序）

  const IndustryTrendData({
    required this.industry,
    required this.points,
  });

  IndustryTrendData copyWith({
    String? industry,
    List<DailyRatioPoint>? points,
  }) {
    return IndustryTrendData(
      industry: industry ?? this.industry,
      points: points ?? this.points,
    );
  }

  /// 返回按日期升序排列的副本
  IndustryTrendData sortedByDate() {
    final sortedPoints = List<DailyRatioPoint>.from(points)
      ..sort((a, b) => a.date.compareTo(b.date));
    return copyWith(points: sortedPoints);
  }

  Map<String, dynamic> toJson() => {
    'industry': industry,
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory IndustryTrendData.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List)
        .map((p) => DailyRatioPoint.fromJson(p as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date)); // 确保按日期升序
    return IndustryTrendData(
      industry: json['industry'] as String,
      points: points,
    );
  }
}
