class EmaConfig {
  const EmaConfig({required this.shortPeriod, required this.longPeriod});

  final int shortPeriod;
  final int longPeriod;

  static const EmaConfig dailyDefaults = EmaConfig(shortPeriod: 11, longPeriod: 22);
  static const EmaConfig weeklyDefaults = EmaConfig(shortPeriod: 13, longPeriod: 26);

  EmaConfig copyWith({int? shortPeriod, int? longPeriod}) =>
      EmaConfig(
        shortPeriod: shortPeriod ?? this.shortPeriod,
        longPeriod: longPeriod ?? this.longPeriod,
      );

  Map<String, dynamic> toJson() => {
        'shortPeriod': shortPeriod,
        'longPeriod': longPeriod,
      };

  factory EmaConfig.fromJson(Map<String, dynamic> json) => EmaConfig(
        shortPeriod: (json['shortPeriod'] as num?)?.toInt() ?? dailyDefaults.shortPeriod,
        longPeriod: (json['longPeriod'] as num?)?.toInt() ?? dailyDefaults.longPeriod,
      );

  @override
  bool operator ==(Object other) =>
      other is EmaConfig &&
      shortPeriod == other.shortPeriod &&
      longPeriod == other.longPeriod;

  @override
  int get hashCode => Object.hash(shortPeriod, longPeriod);
}
