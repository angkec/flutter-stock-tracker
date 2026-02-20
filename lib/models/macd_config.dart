class MacdConfig {
  final int fastPeriod;
  final int slowPeriod;
  final int signalPeriod;
  final int windowMonths;

  const MacdConfig({
    required this.fastPeriod,
    required this.slowPeriod,
    required this.signalPeriod,
    required this.windowMonths,
  });

  static const MacdConfig defaults = MacdConfig(
    fastPeriod: 12,
    slowPeriod: 26,
    signalPeriod: 9,
    windowMonths: 18,
  );

  MacdConfig copyWith({
    int? fastPeriod,
    int? slowPeriod,
    int? signalPeriod,
    int? windowMonths,
  }) {
    return MacdConfig(
      fastPeriod: fastPeriod ?? this.fastPeriod,
      slowPeriod: slowPeriod ?? this.slowPeriod,
      signalPeriod: signalPeriod ?? this.signalPeriod,
      windowMonths: windowMonths ?? this.windowMonths,
    );
  }

  bool get isValid {
    return fastPeriod > 0 &&
        slowPeriod > 0 &&
        signalPeriod > 0 &&
        windowMonths > 0 &&
        fastPeriod < slowPeriod;
  }

  Map<String, dynamic> toJson() => {
    'fastPeriod': fastPeriod,
    'slowPeriod': slowPeriod,
    'signalPeriod': signalPeriod,
    'windowMonths': windowMonths,
  };

  factory MacdConfig.fromJson(Map<String, dynamic> json) {
    final config = MacdConfig(
      fastPeriod: json['fastPeriod'] as int? ?? defaults.fastPeriod,
      slowPeriod: json['slowPeriod'] as int? ?? defaults.slowPeriod,
      signalPeriod: json['signalPeriod'] as int? ?? defaults.signalPeriod,
      windowMonths: json['windowMonths'] as int? ?? defaults.windowMonths,
    );
    return config.isValid ? config : defaults;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MacdConfig &&
        other.fastPeriod == fastPeriod &&
        other.slowPeriod == slowPeriod &&
        other.signalPeriod == signalPeriod &&
        other.windowMonths == windowMonths;
  }

  @override
  int get hashCode {
    return Object.hash(fastPeriod, slowPeriod, signalPeriod, windowMonths);
  }
}
