class LinkedLayoutConfig {
  const LinkedLayoutConfig({
    required this.mainMinHeight,
    required this.mainIdealHeight,
    required this.subMinHeight,
    required this.subIdealHeight,
    required this.infoBarHeight,
    required this.subchartSpacing,
    required this.paneGap,
    required this.topPaneWeight,
    required this.bottomPaneWeight,
    required this.containerMinHeight,
    required this.containerMaxHeight,
  });

  const LinkedLayoutConfig.balanced({
    this.mainMinHeight = 92,
    this.mainIdealHeight = 120,
    this.subMinHeight = 52,
    this.subIdealHeight = 78,
    this.infoBarHeight = 24,
    this.subchartSpacing = 10,
    this.paneGap = 10,
    this.topPaneWeight = 42,
    this.bottomPaneWeight = 58,
    this.containerMinHeight = 640,
    this.containerMaxHeight = 840,
  });

  final double mainMinHeight;
  final double mainIdealHeight;
  final double subMinHeight;
  final double subIdealHeight;
  final double infoBarHeight;
  final double subchartSpacing;
  final double paneGap;
  final int topPaneWeight;
  final int bottomPaneWeight;
  final double containerMinHeight;
  final double containerMaxHeight;

  LinkedLayoutConfig normalize() {
    double safeDouble(double value, double fallback) {
      if (value.isFinite && value > 0) {
        return value;
      }
      return fallback;
    }

    final normalizedTopWeight = topPaneWeight <= 0 ? 42 : topPaneWeight;
    final normalizedBottomWeight = bottomPaneWeight <= 0
        ? 58
        : bottomPaneWeight;

    return LinkedLayoutConfig(
      mainMinHeight: safeDouble(mainMinHeight, 92),
      mainIdealHeight: safeDouble(mainIdealHeight, 120),
      subMinHeight: safeDouble(subMinHeight, 52),
      subIdealHeight: safeDouble(subIdealHeight, 78),
      infoBarHeight: safeDouble(infoBarHeight, 24),
      subchartSpacing: safeDouble(subchartSpacing, 10),
      paneGap: safeDouble(paneGap, 10),
      topPaneWeight: normalizedTopWeight,
      bottomPaneWeight: normalizedBottomWeight,
      containerMinHeight: safeDouble(containerMinHeight, 640),
      containerMaxHeight: safeDouble(containerMaxHeight, 840),
    );
  }

  LinkedLayoutConfig copyWith({
    double? mainMinHeight,
    double? mainIdealHeight,
    double? subMinHeight,
    double? subIdealHeight,
    double? infoBarHeight,
    double? subchartSpacing,
    double? paneGap,
    int? topPaneWeight,
    int? bottomPaneWeight,
    double? containerMinHeight,
    double? containerMaxHeight,
  }) {
    return LinkedLayoutConfig(
      mainMinHeight: mainMinHeight ?? this.mainMinHeight,
      mainIdealHeight: mainIdealHeight ?? this.mainIdealHeight,
      subMinHeight: subMinHeight ?? this.subMinHeight,
      subIdealHeight: subIdealHeight ?? this.subIdealHeight,
      infoBarHeight: infoBarHeight ?? this.infoBarHeight,
      subchartSpacing: subchartSpacing ?? this.subchartSpacing,
      paneGap: paneGap ?? this.paneGap,
      topPaneWeight: topPaneWeight ?? this.topPaneWeight,
      bottomPaneWeight: bottomPaneWeight ?? this.bottomPaneWeight,
      containerMinHeight: containerMinHeight ?? this.containerMinHeight,
      containerMaxHeight: containerMaxHeight ?? this.containerMaxHeight,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mainMinHeight': mainMinHeight,
      'mainIdealHeight': mainIdealHeight,
      'subMinHeight': subMinHeight,
      'subIdealHeight': subIdealHeight,
      'infoBarHeight': infoBarHeight,
      'subchartSpacing': subchartSpacing,
      'paneGap': paneGap,
      'topPaneWeight': topPaneWeight,
      'bottomPaneWeight': bottomPaneWeight,
      'containerMinHeight': containerMinHeight,
      'containerMaxHeight': containerMaxHeight,
    };
  }

  factory LinkedLayoutConfig.fromJson(Map<String, dynamic> json) {
    return LinkedLayoutConfig(
      mainMinHeight: (json['mainMinHeight'] as num?)?.toDouble() ?? 92,
      mainIdealHeight: (json['mainIdealHeight'] as num?)?.toDouble() ?? 120,
      subMinHeight: (json['subMinHeight'] as num?)?.toDouble() ?? 52,
      subIdealHeight: (json['subIdealHeight'] as num?)?.toDouble() ?? 78,
      infoBarHeight: (json['infoBarHeight'] as num?)?.toDouble() ?? 24,
      subchartSpacing: (json['subchartSpacing'] as num?)?.toDouble() ?? 10,
      paneGap: (json['paneGap'] as num?)?.toDouble() ?? 10,
      topPaneWeight: (json['topPaneWeight'] as num?)?.toInt() ?? 42,
      bottomPaneWeight: (json['bottomPaneWeight'] as num?)?.toInt() ?? 58,
      containerMinHeight:
          (json['containerMinHeight'] as num?)?.toDouble() ?? 640,
      containerMaxHeight:
          (json['containerMaxHeight'] as num?)?.toDouble() ?? 840,
    );
  }
}
