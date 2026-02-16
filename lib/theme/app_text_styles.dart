import 'package:flutter/material.dart';

/// App text styles
class AppTextStyles {
  AppTextStyles._();

  // === Title Styles ===
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle section = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  // === Body Styles ===
  static const TextStyle body = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  // === Data Styles (monospace for numbers) ===
  static const TextStyle data = TextStyle(
    fontFamily: 'monospace',
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
  );

  static const TextStyle dataSmall = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.3,
  );

  // === Table Styles ===
  static const TextStyle tableHeader = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle tableCell = TextStyle(fontSize: 13);

  // === Audit Console Styles ===
  static const TextStyle auditRailCaption = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static const TextStyle auditRailVerdict = TextStyle(
    fontFamily: 'monospace',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  static const TextStyle auditOperation = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle auditTimestamp = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle auditChip = TextStyle(
    fontFamily: 'monospace',
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle auditMetrics = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
}
