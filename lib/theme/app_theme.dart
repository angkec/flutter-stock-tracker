import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'chart_overlay_theme.dart';

/// Tab 类型枚举
enum AppTab { watchlist, market, industry, breakout }

/// App theme configuration
class AppTheme {
  AppTheme._();

  /// 获取 Tab 对应的主题色
  static Color getTabColor(AppTab tab, {bool isDark = false}) {
    switch (tab) {
      case AppTab.watchlist:
        return isDark ? AppColors.tabWatchlistDark : AppColors.tabWatchlist;
      case AppTab.market:
        return isDark ? AppColors.tabMarketDark : AppColors.tabMarket;
      case AppTab.industry:
        return isDark ? AppColors.tabIndustryDark : AppColors.tabIndustry;
      case AppTab.breakout:
        return isDark ? AppColors.tabBreakoutDark : AppColors.tabBreakout;
    }
  }

  /// 创建带有特定主题色的深色主题
  static ThemeData darkWithColor(Color primaryColor) {
    return dark.copyWith(
      colorScheme: dark.colorScheme.copyWith(primary: primaryColor),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor.withValues(alpha: 0.15),
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: primaryColor.withValues(alpha: 0.2),
      ),
    );
  }

  /// 创建带有特定主题色的浅色主题
  static ThemeData lightWithColor(Color primaryColor) {
    return light.copyWith(
      colorScheme: light.colorScheme.copyWith(primary: primaryColor),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor.withValues(alpha: 0.1),
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        indicatorColor: primaryColor.withValues(alpha: 0.2),
      ),
    );
  }

  /// 根据 Tab 和亮度获取主题
  static ThemeData forTab(AppTab tab, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final color = getTabColor(tab, isDark: isDark);
    return isDark ? darkWithColor(color) : lightWithColor(color);
  }

  /// Dark theme
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    extensions: const <ThemeExtension<dynamic>>[ChartOverlayTheme.dark],
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.darkPrimary,
      surface: AppColors.darkSurface,
      surfaceContainerHighest: AppColors.darkSurfaceVariant,
      onSurface: AppColors.darkTextPrimary,
      onSurfaceVariant: AppColors.darkTextSecondary,
      outline: AppColors.darkDivider,
    ),
    dividerColor: AppColors.darkDivider,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      indicatorColor: AppColors.darkPrimary.withValues(alpha: 0.2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkDivider, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkDivider, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.darkSurface,
      contentTextStyle: TextStyle(color: AppColors.darkTextPrimary),
    ),
  );

  /// Light theme
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    extensions: const <ThemeExtension<dynamic>>[ChartOverlayTheme.light],
    scaffoldBackgroundColor: AppColors.lightBackground,
    colorScheme: const ColorScheme.light(
      primary: AppColors.lightPrimary,
      surface: AppColors.lightSurface,
      surfaceContainerHighest: AppColors.lightSurfaceVariant,
      onSurface: AppColors.lightTextPrimary,
      onSurfaceVariant: AppColors.lightTextSecondary,
      outline: AppColors.lightDivider,
    ),
    dividerColor: AppColors.lightDivider,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightSurface,
      foregroundColor: AppColors.lightTextPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.lightSurface,
      indicatorColor: AppColors.lightPrimary.withValues(alpha: 0.2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.lightDivider, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.lightDivider, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.lightPrimary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.lightSurface,
      contentTextStyle: TextStyle(color: AppColors.lightTextPrimary),
    ),
  );
}
