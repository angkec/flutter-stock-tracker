class IndustryBuildupTagConfig {
  final double emotionMinZ;
  final double emotionMinBreadth;

  final double allocationMinZ;
  final double allocationMinBreadth;
  final double allocationMaxBreadth;
  final double allocationMinQ;

  final double earlyMinZ;
  final double earlyMaxZ;
  final double earlyMinBreadth;
  final double earlyMaxBreadth;
  final double earlyMinQ;

  final double noiseMinZ;
  final double noiseMaxBreadth;
  final double noiseMaxQ;

  final double neutralMinZ;
  final double neutralMaxZ;

  const IndustryBuildupTagConfig({
    this.emotionMinZ = 2.0,
    this.emotionMinBreadth = 0.55,
    this.allocationMinZ = 1.5,
    this.allocationMinBreadth = 0.40,
    this.allocationMaxBreadth = 0.55,
    this.allocationMinQ = 0.65,
    this.earlyMinZ = 1.2,
    this.earlyMaxZ = 1.8,
    this.earlyMinBreadth = 0.25,
    this.earlyMaxBreadth = 0.40,
    this.earlyMinQ = 0.60,
    this.noiseMinZ = 1.0,
    this.noiseMaxBreadth = 0.25,
    this.noiseMaxQ = 0.50,
    this.neutralMinZ = -0.5,
    this.neutralMaxZ = 0.5,
  });

  static const IndustryBuildupTagConfig defaults = IndustryBuildupTagConfig();

  IndustryBuildupTagConfig copyWith({
    double? emotionMinZ,
    double? emotionMinBreadth,
    double? allocationMinZ,
    double? allocationMinBreadth,
    double? allocationMaxBreadth,
    double? allocationMinQ,
    double? earlyMinZ,
    double? earlyMaxZ,
    double? earlyMinBreadth,
    double? earlyMaxBreadth,
    double? earlyMinQ,
    double? noiseMinZ,
    double? noiseMaxBreadth,
    double? noiseMaxQ,
    double? neutralMinZ,
    double? neutralMaxZ,
  }) {
    return IndustryBuildupTagConfig(
      emotionMinZ: emotionMinZ ?? this.emotionMinZ,
      emotionMinBreadth: emotionMinBreadth ?? this.emotionMinBreadth,
      allocationMinZ: allocationMinZ ?? this.allocationMinZ,
      allocationMinBreadth: allocationMinBreadth ?? this.allocationMinBreadth,
      allocationMaxBreadth: allocationMaxBreadth ?? this.allocationMaxBreadth,
      allocationMinQ: allocationMinQ ?? this.allocationMinQ,
      earlyMinZ: earlyMinZ ?? this.earlyMinZ,
      earlyMaxZ: earlyMaxZ ?? this.earlyMaxZ,
      earlyMinBreadth: earlyMinBreadth ?? this.earlyMinBreadth,
      earlyMaxBreadth: earlyMaxBreadth ?? this.earlyMaxBreadth,
      earlyMinQ: earlyMinQ ?? this.earlyMinQ,
      noiseMinZ: noiseMinZ ?? this.noiseMinZ,
      noiseMaxBreadth: noiseMaxBreadth ?? this.noiseMaxBreadth,
      noiseMaxQ: noiseMaxQ ?? this.noiseMaxQ,
      neutralMinZ: neutralMinZ ?? this.neutralMinZ,
      neutralMaxZ: neutralMaxZ ?? this.neutralMaxZ,
    );
  }

  Map<String, dynamic> toJson() => {
    'emotionMinZ': emotionMinZ,
    'emotionMinBreadth': emotionMinBreadth,
    'allocationMinZ': allocationMinZ,
    'allocationMinBreadth': allocationMinBreadth,
    'allocationMaxBreadth': allocationMaxBreadth,
    'allocationMinQ': allocationMinQ,
    'earlyMinZ': earlyMinZ,
    'earlyMaxZ': earlyMaxZ,
    'earlyMinBreadth': earlyMinBreadth,
    'earlyMaxBreadth': earlyMaxBreadth,
    'earlyMinQ': earlyMinQ,
    'noiseMinZ': noiseMinZ,
    'noiseMaxBreadth': noiseMaxBreadth,
    'noiseMaxQ': noiseMaxQ,
    'neutralMinZ': neutralMinZ,
    'neutralMaxZ': neutralMaxZ,
  };

  factory IndustryBuildupTagConfig.fromJson(Map<String, dynamic> json) {
    return IndustryBuildupTagConfig(
      emotionMinZ: (json['emotionMinZ'] as num?)?.toDouble() ?? 2.0,
      emotionMinBreadth:
          (json['emotionMinBreadth'] as num?)?.toDouble() ?? 0.55,
      allocationMinZ: (json['allocationMinZ'] as num?)?.toDouble() ?? 1.5,
      allocationMinBreadth:
          (json['allocationMinBreadth'] as num?)?.toDouble() ?? 0.40,
      allocationMaxBreadth:
          (json['allocationMaxBreadth'] as num?)?.toDouble() ?? 0.55,
      allocationMinQ: (json['allocationMinQ'] as num?)?.toDouble() ?? 0.65,
      earlyMinZ: (json['earlyMinZ'] as num?)?.toDouble() ?? 1.2,
      earlyMaxZ: (json['earlyMaxZ'] as num?)?.toDouble() ?? 1.8,
      earlyMinBreadth: (json['earlyMinBreadth'] as num?)?.toDouble() ?? 0.25,
      earlyMaxBreadth: (json['earlyMaxBreadth'] as num?)?.toDouble() ?? 0.40,
      earlyMinQ: (json['earlyMinQ'] as num?)?.toDouble() ?? 0.60,
      noiseMinZ: (json['noiseMinZ'] as num?)?.toDouble() ?? 1.0,
      noiseMaxBreadth: (json['noiseMaxBreadth'] as num?)?.toDouble() ?? 0.25,
      noiseMaxQ: (json['noiseMaxQ'] as num?)?.toDouble() ?? 0.50,
      neutralMinZ: (json['neutralMinZ'] as num?)?.toDouble() ?? -0.5,
      neutralMaxZ: (json['neutralMaxZ'] as num?)?.toDouble() ?? 0.5,
    );
  }
}
