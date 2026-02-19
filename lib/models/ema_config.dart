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

  bool get isValid {
    return shortPeriod > 0 && longPeriod > 0 && shortPeriod < longPeriod;
  }

  factory EmaConfig.fromJson(
    Map<String, dynamic> json, {
    EmaConfig defaults = dailyDefaults,
  }) {
    final config = EmaConfig(
      shortPeriod:
          (json['shortPeriod'] as num?)?.toInt() ?? defaults.shortPeriod,
      longPeriod: (json['longPeriod'] as num?)?.toInt() ?? defaults.longPeriod,
    );
    return config.isValid ? config : defaults;
  }

  @override
  bool operator ==(Object other) =>
      other is EmaConfig &&
      shortPeriod == other.shortPeriod &&
      longPeriod == other.longPeriod;

  @override
  int get hashCode => Object.hash(shortPeriod, longPeriod);
}
