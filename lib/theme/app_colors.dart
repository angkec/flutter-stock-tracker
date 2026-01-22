import 'package:flutter/material.dart';

/// App color palette for light and dark themes
class AppColors {
  AppColors._();

  // === Stock Colors (same in both themes) ===
  static const Color stockUp = Color(0xFFFF4444);
  static const Color stockDown = Color(0xFF00AA00);
  static const Color stockFlat = Color(0xFF888888);

  // === Dark Theme Colors ===
  static const Color darkBackground = Color(0xFF0D0D0D);
  static const Color darkSurface = Color(0xFF1A1A1A);
  static const Color darkSurfaceVariant = Color(0xFF242424);
  static const Color darkDivider = Color(0xFF2A2A2A);
  static const Color darkPrimary = Color(0xFF4A90D9);
  static const Color darkTextPrimary = Color(0xFFE8E8E8);
  static const Color darkTextSecondary = Color(0xFF888888);

  // === Light Theme Colors ===
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF0F1F3);
  static const Color lightDivider = Color(0xFFE5E5E5);
  static const Color lightPrimary = Color(0xFF2563EB);
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF6B7280);

  // === Change Distribution Colors (7-level) ===
  static const Color limitUp = Color(0xFFFF0000);
  static const Color up5 = Color(0xFFFF4444);
  static const Color up0to5 = Color(0xFFFF8888);
  static const Color flat = Color(0xFF888888);
  static const Color down0to5 = Color(0xFF88CC88);
  static const Color down5 = Color(0xFF44AA44);
  static const Color limitDown = Color(0xFF00AA00);

  // === Status Colors ===
  static const Color statusPreMarket = Colors.orange;
  static const Color statusTrading = Colors.green;
  static const Color statusLunchBreak = Colors.yellow;
  static const Color statusClosed = Colors.grey;

  // === Tab Theme Colors ===
  // 自选 - 金色/琥珀色
  static const Color tabWatchlist = Color(0xFFFF9800);
  static const Color tabWatchlistDark = Color(0xFFFFB74D);

  // 全市场 - 蓝色
  static const Color tabMarket = Color(0xFF2563EB);
  static const Color tabMarketDark = Color(0xFF4A90D9);

  // 行业 - 紫色
  static const Color tabIndustry = Color(0xFF7C3AED);
  static const Color tabIndustryDark = Color(0xFFA78BFA);

  // 回踩 - 青色/蓝绿色
  static const Color tabBreakout = Color(0xFF0D9488);
  static const Color tabBreakoutDark = Color(0xFF2DD4BF);
}
