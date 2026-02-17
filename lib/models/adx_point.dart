class AdxPoint {
  final DateTime datetime;
  final double adx;
  final double plusDi;
  final double minusDi;

  const AdxPoint({
    required this.datetime,
    required this.adx,
    required this.plusDi,
    required this.minusDi,
  });

  Map<String, dynamic> toJson() => {
    'datetime': datetime.toIso8601String(),
    'adx': adx,
    'plusDi': plusDi,
    'minusDi': minusDi,
  };

  factory AdxPoint.fromJson(Map<String, dynamic> json) {
    return AdxPoint(
      datetime: DateTime.parse(json['datetime'] as String),
      adx: (json['adx'] as num).toDouble(),
      plusDi: (json['plusDi'] as num).toDouble(),
      minusDi: (json['minusDi'] as num).toDouble(),
    );
  }
}
