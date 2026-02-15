import 'package:flutter/material.dart';
import 'dart:ui' show lerpDouble;

@immutable
class ChartOverlayTheme extends ThemeExtension<ChartOverlayTheme> {
  const ChartOverlayTheme({
    required this.crosshairColor,
    required this.macdSelectionLineColor,
    required this.macdSelectionLineWidth,
    required this.macdSelectionDashLength,
    required this.macdSelectionGapLength,
  });

  final Color crosshairColor;
  final Color macdSelectionLineColor;
  final double macdSelectionLineWidth;
  final double macdSelectionDashLength;
  final double macdSelectionGapLength;

  static const ChartOverlayTheme light = ChartOverlayTheme(
    crosshairColor: Colors.black,
    macdSelectionLineColor: Color(0xB3000000),
    macdSelectionLineWidth: 1.0,
    macdSelectionDashLength: 4.0,
    macdSelectionGapLength: 3.0,
  );

  static const ChartOverlayTheme dark = ChartOverlayTheme(
    crosshairColor: Colors.white,
    macdSelectionLineColor: Color(0xB3FFFFFF),
    macdSelectionLineWidth: 1.0,
    macdSelectionDashLength: 4.0,
    macdSelectionGapLength: 3.0,
  );

  @override
  ChartOverlayTheme copyWith({
    Color? crosshairColor,
    Color? macdSelectionLineColor,
    double? macdSelectionLineWidth,
    double? macdSelectionDashLength,
    double? macdSelectionGapLength,
  }) {
    return ChartOverlayTheme(
      crosshairColor: crosshairColor ?? this.crosshairColor,
      macdSelectionLineColor:
          macdSelectionLineColor ?? this.macdSelectionLineColor,
      macdSelectionLineWidth:
          macdSelectionLineWidth ?? this.macdSelectionLineWidth,
      macdSelectionDashLength:
          macdSelectionDashLength ?? this.macdSelectionDashLength,
      macdSelectionGapLength:
          macdSelectionGapLength ?? this.macdSelectionGapLength,
    );
  }

  @override
  ChartOverlayTheme lerp(
    covariant ThemeExtension<ChartOverlayTheme>? other,
    double t,
  ) {
    if (other is! ChartOverlayTheme) {
      return this;
    }
    return ChartOverlayTheme(
      crosshairColor: Color.lerp(crosshairColor, other.crosshairColor, t)!,
      macdSelectionLineColor: Color.lerp(
        macdSelectionLineColor,
        other.macdSelectionLineColor,
        t,
      )!,
      macdSelectionLineWidth: lerpDouble(
        macdSelectionLineWidth,
        other.macdSelectionLineWidth,
        t,
      )!,
      macdSelectionDashLength: lerpDouble(
        macdSelectionDashLength,
        other.macdSelectionDashLength,
        t,
      )!,
      macdSelectionGapLength: lerpDouble(
        macdSelectionGapLength,
        other.macdSelectionGapLength,
        t,
      )!,
    );
  }
}
