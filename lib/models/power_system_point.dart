class PowerSystemPoint {
  const PowerSystemPoint({required this.datetime, required this.state});

  final DateTime datetime;
  final int state;

  Map<String, dynamic> toJson() => {
    'datetime': datetime.toIso8601String(),
    'state': state,
  };

  factory PowerSystemPoint.fromJson(Map<String, dynamic> json) {
    return PowerSystemPoint(
      datetime: DateTime.parse(json['datetime'] as String),
      state: json['state'] as int,
    );
  }
}
