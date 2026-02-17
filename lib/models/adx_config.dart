class AdxConfig {
  final int period;
  final double threshold;

  const AdxConfig({required this.period, required this.threshold});

  static const AdxConfig defaults = AdxConfig(period: 14, threshold: 25);

  AdxConfig copyWith({int? period, double? threshold}) {
    return AdxConfig(
      period: period ?? this.period,
      threshold: threshold ?? this.threshold,
    );
  }

  bool get isValid {
    return period > 0 && threshold > 0 && threshold.isFinite;
  }

  Map<String, dynamic> toJson() => {
    'period': period,
    'threshold': threshold,
  };

  factory AdxConfig.fromJson(Map<String, dynamic> json) {
    final config = AdxConfig(
      period: json['period'] as int? ?? defaults.period,
      threshold: (json['threshold'] as num?)?.toDouble() ?? defaults.threshold,
    );
    return config.isValid ? config : defaults;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdxConfig &&
        other.period == period &&
        other.threshold == threshold;
  }

  @override
  int get hashCode => Object.hash(period, threshold);
}
