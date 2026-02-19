class EmaPoint {
  final DateTime datetime;
  final double emaShort;
  final double emaLong;

  const EmaPoint({
    required this.datetime,
    required this.emaShort,
    required this.emaLong,
  });

  Map<String, dynamic> toJson() => {
    'datetime': datetime.toIso8601String(),
    'emaShort': emaShort,
    'emaLong': emaLong,
  };

  factory EmaPoint.fromJson(Map<String, dynamic> json) => EmaPoint(
    datetime: DateTime.parse(json['datetime'] as String),
    emaShort: (json['emaShort'] as num).toDouble(),
    emaLong: (json['emaLong'] as num).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is EmaPoint &&
      datetime == other.datetime &&
      emaShort == other.emaShort &&
      emaLong == other.emaLong;

  @override
  int get hashCode => Object.hash(datetime, emaShort, emaLong);
}
