class IndustryEmaBreadthPoint {
  const IndustryEmaBreadthPoint({
    required this.date,
    this.percent,
    required this.aboveCount,
    required this.validCount,
    required this.missingCount,
  });

  final DateTime date;
  final double? percent;
  final int aboveCount;
  final int validCount;
  final int missingCount;

  IndustryEmaBreadthPoint copyWith({
    DateTime? date,
    double? percent,
    bool clearPercent = false,
    int? aboveCount,
    int? validCount,
    int? missingCount,
  }) {
    return IndustryEmaBreadthPoint(
      date: date ?? this.date,
      percent: clearPercent ? null : (percent ?? this.percent),
      aboveCount: aboveCount ?? this.aboveCount,
      validCount: validCount ?? this.validCount,
      missingCount: missingCount ?? this.missingCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'percent': percent,
    'aboveCount': aboveCount,
    'validCount': validCount,
    'missingCount': missingCount,
  };

  factory IndustryEmaBreadthPoint.fromJson(Map<String, dynamic> json) =>
      IndustryEmaBreadthPoint(
        date: DateTime.parse(json['date'] as String),
        percent: (json['percent'] as num?)?.toDouble(),
        aboveCount: (json['aboveCount'] as num).toInt(),
        validCount: (json['validCount'] as num).toInt(),
        missingCount: (json['missingCount'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is IndustryEmaBreadthPoint &&
      date == other.date &&
      percent == other.percent &&
      aboveCount == other.aboveCount &&
      validCount == other.validCount &&
      missingCount == other.missingCount;

  @override
  int get hashCode =>
      Object.hash(date, percent, aboveCount, validCount, missingCount);
}

class IndustryEmaBreadthSeries {
  IndustryEmaBreadthSeries({
    required this.industry,
    required List<IndustryEmaBreadthPoint> points,
  }) : points = List<IndustryEmaBreadthPoint>.unmodifiable(points);

  final String industry;
  final List<IndustryEmaBreadthPoint> points;

  IndustryEmaBreadthSeries copyWith({
    String? industry,
    List<IndustryEmaBreadthPoint>? points,
  }) {
    return IndustryEmaBreadthSeries(
      industry: industry ?? this.industry,
      points: points ?? this.points,
    );
  }

  IndustryEmaBreadthSeries sortedByDate() {
    final sortedPoints = List<IndustryEmaBreadthPoint>.from(points)
      ..sort((a, b) => a.date.compareTo(b.date));
    return copyWith(points: sortedPoints);
  }

  Map<String, dynamic> toJson() => {
    'industry': industry,
    'points': points.map((p) => p.toJson()).toList(),
  };

  factory IndustryEmaBreadthSeries.fromJson(Map<String, dynamic> json) {
    final pointsList = List<IndustryEmaBreadthPoint>.unmodifiable(
      (json['points'] as List)
          .map(
            (p) => IndustryEmaBreadthPoint.fromJson(p as Map<String, dynamic>),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
    );
    return IndustryEmaBreadthSeries(
      industry: json['industry'] as String,
      points: pointsList,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IndustryEmaBreadthSeries &&
      industry == other.industry &&
      _listEquals(points, other.points);

  @override
  int get hashCode => Object.hash(industry, Object.hashAll(points));

  static bool _listEquals(
    List<IndustryEmaBreadthPoint> a,
    List<IndustryEmaBreadthPoint> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
