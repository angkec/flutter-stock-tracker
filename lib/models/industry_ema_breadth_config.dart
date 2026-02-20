class IndustryEmaBreadthConfig {
  const IndustryEmaBreadthConfig({
    required this.upperThreshold,
    required this.lowerThreshold,
  });

  final double upperThreshold;
  final double lowerThreshold;

  static const IndustryEmaBreadthConfig defaultConfig =
      IndustryEmaBreadthConfig(upperThreshold: 75.0, lowerThreshold: 25.0);

  factory IndustryEmaBreadthConfig.defaults() => defaultConfig;

  bool get isValid =>
      lowerThreshold >= 0 &&
      upperThreshold <= 100 &&
      lowerThreshold < upperThreshold;

  IndustryEmaBreadthConfig copyWith({
    double? upperThreshold,
    double? lowerThreshold,
  }) {
    return IndustryEmaBreadthConfig(
      upperThreshold: upperThreshold ?? this.upperThreshold,
      lowerThreshold: lowerThreshold ?? this.lowerThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
    'upperThreshold': upperThreshold,
    'lowerThreshold': lowerThreshold,
  };

  factory IndustryEmaBreadthConfig.fromJson(
    Map<String, dynamic> json, {
    IndustryEmaBreadthConfig? defaults,
  }) {
    final defaultVals = defaults ?? defaultConfig;
    final config = IndustryEmaBreadthConfig(
      upperThreshold:
          (json['upperThreshold'] as num?)?.toDouble() ??
          defaultVals.upperThreshold,
      lowerThreshold:
          (json['lowerThreshold'] as num?)?.toDouble() ??
          defaultVals.lowerThreshold,
    );
    return config.isValid ? config : defaultVals;
  }

  @override
  bool operator ==(Object other) =>
      other is IndustryEmaBreadthConfig &&
      upperThreshold == other.upperThreshold &&
      lowerThreshold == other.lowerThreshold;

  @override
  int get hashCode => Object.hash(upperThreshold, lowerThreshold);
}
