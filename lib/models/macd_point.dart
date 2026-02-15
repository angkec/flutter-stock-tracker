class MacdPoint {
  final DateTime datetime;
  final double dif;
  final double dea;
  final double hist;

  const MacdPoint({
    required this.datetime,
    required this.dif,
    required this.dea,
    required this.hist,
  });

  Map<String, dynamic> toJson() => {
    'datetime': datetime.toIso8601String(),
    'dif': dif,
    'dea': dea,
    'hist': hist,
  };

  factory MacdPoint.fromJson(Map<String, dynamic> json) {
    return MacdPoint(
      datetime: DateTime.parse(json['datetime'] as String),
      dif: (json['dif'] as num).toDouble(),
      dea: (json['dea'] as num).toDouble(),
      hist: (json['hist'] as num).toDouble(),
    );
  }
}

