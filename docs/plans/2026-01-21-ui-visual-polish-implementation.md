# UI Visual Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Modernize the app's visual appearance with a Modern Fintech aesthetic, supporting both light and dark themes while preserving data density.

**Architecture:** Create a centralized theme system in `lib/theme/` with color constants and text styles. Update `main.dart` to support dual themes via system detection. Then progressively update widgets and screens to use the new theme tokens.

**Tech Stack:** Flutter, Material 3, Provider

---

## Task 1: Create Theme Color Constants

**Files:**
- Create: `lib/theme/app_colors.dart`

**Step 1: Create the color constants file**

```dart
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
}
```

**Step 2: Verify file compiles**

Run: `flutter analyze lib/theme/app_colors.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/theme/app_colors.dart
git commit -m "feat: add centralized color constants for dual theme support"
```

---

## Task 2: Create Theme Text Styles

**Files:**
- Create: `lib/theme/app_text_styles.dart`

**Step 1: Create the text styles file**

```dart
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

  static const TextStyle tableCell = TextStyle(
    fontSize: 13,
  );
}
```

**Step 2: Verify file compiles**

Run: `flutter analyze lib/theme/app_text_styles.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/theme/app_text_styles.dart
git commit -m "feat: add centralized text styles"
```

---

## Task 3: Create Theme Data Builders

**Files:**
- Create: `lib/theme/app_theme.dart`

**Step 1: Create the theme builder file**

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App theme configuration
class AppTheme {
  AppTheme._();

  /// Dark theme
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
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
          indicatorColor: AppColors.darkPrimary.withOpacity(0.2),
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
          indicatorColor: AppColors.lightPrimary.withOpacity(0.2),
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
```

**Step 2: Verify file compiles**

Run: `flutter analyze lib/theme/app_theme.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/theme/app_theme.dart
git commit -m "feat: add dark and light theme builders"
```

---

## Task 4: Create Theme Barrel Export

**Files:**
- Create: `lib/theme/theme.dart`

**Step 1: Create barrel export file**

```dart
export 'app_colors.dart';
export 'app_text_styles.dart';
export 'app_theme.dart';
```

**Step 2: Verify file compiles**

Run: `flutter analyze lib/theme/theme.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/theme/theme.dart
git commit -m "feat: add theme barrel export"
```

---

## Task 5: Update main.dart for Dual Theme Support

**Files:**
- Modify: `lib/main.dart`

**Step 1: Update imports and MaterialApp theme configuration**

Replace the current theme configuration in `main.dart`:

```dart
// Add import at top
import 'package:stock_rtwatcher/theme/theme.dart';

// In MaterialApp, replace theme property with:
      child: MaterialApp(
        title: '盯喵',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const MainScreen(),
      ),
```

**Step 2: Verify app compiles and runs**

Run: `flutter analyze lib/main.dart`
Expected: No issues found

Run: `flutter run` (manual visual check)
Expected: App runs with system theme detection working

**Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: enable dual theme support via system detection"
```

---

## Task 6: Update stock_table.dart Colors

**Files:**
- Modify: `lib/widgets/stock_table.dart`

**Step 1: Update imports and color constants**

Add import at top:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';
```

Replace the hardcoded color constants:
```dart
/// A股风格颜色 - 红涨绿跌
const Color upColor = AppColors.stockUp;
const Color downColor = AppColors.stockDown;
```

**Step 2: Update alternating row opacity**

In `_buildRow`, change the alternating row opacity from 0.3 to 0.15:
```dart
color: isHighlighted
    ? Colors.amber.withOpacity(0.15)
    : (index.isOdd
        ? Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.15)
        : null),
```

**Step 3: Add row divider**

Wrap row Container in a Column with divider:
```dart
return Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    GestureDetector(
      // ... existing GestureDetector content
    ),
    Divider(height: 0.5, thickness: 0.5, color: Theme.of(context).dividerColor),
  ],
);
```

Note: Adjust the `itemExtent` in ListView.builder to account for divider if needed, or use a Container with bottom border instead.

**Step 4: Verify compiles**

Run: `flutter analyze lib/widgets/stock_table.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/widgets/stock_table.dart
git commit -m "refactor: update stock_table to use theme colors and add row dividers"
```

---

## Task 7: Update market_stats_bar.dart

**Files:**
- Modify: `lib/widgets/market_stats_bar.dart`

**Step 1: Update imports**

Add import at top:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';
```

**Step 2: Update color references**

Replace hardcoded colors with AppColors:
```dart
// In _calculateChangeDistribution()
return [
  StatsInterval(label: '涨停', count: limitUp, color: AppColors.limitUp),
  StatsInterval(label: '>5%', count: up5, color: AppColors.up5),
  StatsInterval(label: '0~5%', count: up0to5, color: AppColors.up0to5),
  StatsInterval(label: '平', count: flat, color: AppColors.flat),
  StatsInterval(label: '-5~0', count: down0to5, color: AppColors.down0to5),
  StatsInterval(label: '<-5%', count: down5, color: AppColors.down5),
  StatsInterval(label: '跌停', count: limitDown, color: AppColors.limitDown),
];

// In _buildRatioRow(), replace hardcoded colors:
color: AppColors.stockUp,  // was Color(0xFFFF4444)
color: AppColors.stockDown,  // was Color(0xFF00AA00)
```

**Step 3: Add top border**

In `build()`, update Container decoration:
```dart
decoration: BoxDecoration(
  color: Theme.of(context).colorScheme.surface,
  border: Border(
    top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
  ),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.1),
      blurRadius: 4,
      offset: const Offset(0, -2),
    ),
  ],
),
```

**Step 4: Add gaps between bar segments**

In `_buildChangeRow()`, update the progress bar:
```dart
ClipRRect(
  borderRadius: BorderRadius.circular(4),
  child: Row(
    children: stats.asMap().entries.map((entry) {
      final s = entry.value;
      final isLast = entry.key == stats.length - 1;
      if (s.count == 0) return const SizedBox.shrink();
      return Expanded(
        flex: s.count,
        child: Container(
          height: 8,
          margin: EdgeInsets.only(right: isLast ? 0 : 1),
          color: s.color,
        ),
      );
    }).toList(),
  ),
),
```

**Step 5: Verify compiles**

Run: `flutter analyze lib/widgets/market_stats_bar.dart`
Expected: No issues found

**Step 6: Commit**

```bash
git add lib/widgets/market_stats_bar.dart
git commit -m "refactor: update market_stats_bar to use theme colors and add segment gaps"
```

---

## Task 8: Update kline_chart.dart

**Files:**
- Modify: `lib/widgets/kline_chart.dart`

**Step 1: Update imports**

Add import at top:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';
```

**Step 2: Update candle colors**

Replace any hardcoded red/green colors with AppColors:
```dart
final upColor = AppColors.stockUp;
final downColor = AppColors.stockDown;
```

**Step 3: Reduce wick width**

Find the wick drawing code and update stroke width from 1.0 to 0.8:
```dart
final wickPaint = Paint()
  ..strokeWidth = 0.8
  ..style = PaintingStyle.stroke;
```

**Step 4: Add subtle horizontal grid lines**

In the CustomPainter, add grid drawing before candles:
```dart
// Draw horizontal grid lines (10% opacity)
final gridPaint = Paint()
  ..color = Colors.grey.withOpacity(0.1)
  ..strokeWidth = 0.5;

const gridLines = 4;
for (int i = 1; i < gridLines; i++) {
  final y = priceAreaHeight * i / gridLines;
  canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
}
```

**Step 5: Reduce volume bar opacity**

Update volume bar paint:
```dart
final volumePaint = Paint()
  ..color = volumeColor.withOpacity(0.8);
```

**Step 6: Verify compiles**

Run: `flutter analyze lib/widgets/kline_chart.dart`
Expected: No issues found

**Step 7: Commit**

```bash
git add lib/widgets/kline_chart.dart
git commit -m "refactor: update kline_chart with theme colors, grid lines, refined styling"
```

---

## Task 9: Update minute_chart.dart

**Files:**
- Modify: `lib/widgets/minute_chart.dart`

**Step 1: Update imports**

Add import at top:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';
```

**Step 2: Add gradient fill below price line**

After drawing the price line, add gradient fill:
```dart
// Create gradient path
final gradientPath = Path()..addPath(pricePath, Offset.zero);
gradientPath.lineTo(points.last.dx, priceAreaBottom);
gradientPath.lineTo(points.first.dx, priceAreaBottom);
gradientPath.close();

// Draw gradient fill
final gradientPaint = Paint()
  ..shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.white.withOpacity(0.1),
      Colors.white.withOpacity(0.0),
    ],
  ).createShader(Rect.fromLTWH(0, 0, size.width, priceAreaBottom));

canvas.drawPath(gradientPath, gradientPaint);
```

**Step 3: Reduce average line opacity**

Update average line paint:
```dart
final avgPaint = Paint()
  ..color = const Color(0xFFFFD700).withOpacity(0.8)
  ..strokeWidth = 1
  ..style = PaintingStyle.stroke;
```

**Step 4: Verify compiles**

Run: `flutter analyze lib/widgets/minute_chart.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/widgets/minute_chart.dart
git commit -m "refactor: update minute_chart with gradient fill and refined styling"
```

---

## Task 10: Update sparkline_chart.dart

**Files:**
- Modify: `lib/widgets/sparkline_chart.dart`

**Step 1: Update imports**

Add import at top:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';
```

**Step 2: Update colors to use AppColors**

Replace hardcoded colors:
```dart
final upPaint = Paint()
  ..color = AppColors.stockUp
  ..strokeWidth = strokeWidth
  ..style = PaintingStyle.stroke;

final downPaint = Paint()
  ..color = AppColors.stockDown
  ..strokeWidth = strokeWidth
  ..style = PaintingStyle.stroke;
```

**Step 3: Tighten reference line dash pattern**

Update the dash pattern to be tighter:
```dart
// Change from [4, 4] or similar to [3, 2]
final dashWidth = 3.0;
final dashGap = 2.0;
```

**Step 4: Verify compiles**

Run: `flutter analyze lib/widgets/sparkline_chart.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/widgets/sparkline_chart.dart
git commit -m "refactor: update sparkline_chart to use theme colors"
```

---

## Task 11: Update status_bar.dart

**Files:**
- Modify: `lib/widgets/status_bar.dart`

**Step 1: Update imports**

Add import at top:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';
```

**Step 2: Update status colors**

Replace hardcoded status colors with AppColors:
```dart
Color _getStatusColor(MarketStatus status) {
  switch (status) {
    case MarketStatus.preMarket:
      return AppColors.statusPreMarket;
    case MarketStatus.trading:
      return AppColors.statusTrading;
    case MarketStatus.lunchBreak:
      return AppColors.statusLunchBreak;
    case MarketStatus.closed:
      return AppColors.statusClosed;
  }
}
```

**Step 3: Verify compiles**

Run: `flutter analyze lib/widgets/status_bar.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/widgets/status_bar.dart
git commit -m "refactor: update status_bar to use theme colors"
```

---

## Task 12: Update Remaining Widgets

**Files:**
- Modify: `lib/widgets/industry_heat_bar.dart`
- Modify: `lib/widgets/industry_trend_chart.dart`
- Modify: `lib/widgets/ratio_history_list.dart`

**Step 1: Update industry_heat_bar.dart**

Add import and replace hardcoded colors:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';

// Replace Color(0xFFFF4444) with AppColors.stockUp
// Replace Color(0xFF00AA00) with AppColors.stockDown
```

**Step 2: Update industry_trend_chart.dart**

Add import and update colors to use theme-aware colors where appropriate.

**Step 3: Update ratio_history_list.dart**

Add import and replace hardcoded colors:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';

// Replace ratio colors with AppColors.stockUp / AppColors.stockDown
```

**Step 4: Verify all compile**

Run: `flutter analyze lib/widgets/`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/widgets/industry_heat_bar.dart lib/widgets/industry_trend_chart.dart lib/widgets/ratio_history_list.dart
git commit -m "refactor: update remaining widgets to use theme colors"
```

---

## Task 13: Update Config Dialogs

**Files:**
- Modify: `lib/widgets/pullback_config_dialog.dart`
- Modify: `lib/widgets/breakout_config_dialog.dart`

**Step 1: Update imports in both files**

Add import at top of each:
```dart
import 'package:stock_rtwatcher/theme/theme.dart';
```

**Step 2: Ensure dialogs use theme colors**

Review and update any hardcoded colors to use Theme.of(context) or AppColors.

**Step 3: Verify compiles**

Run: `flutter analyze lib/widgets/pullback_config_dialog.dart lib/widgets/breakout_config_dialog.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/widgets/pullback_config_dialog.dart lib/widgets/breakout_config_dialog.dart
git commit -m "refactor: update config dialogs to use theme colors"
```

---

## Task 14: Final Visual Verification

**Step 1: Run app in dark mode**

Run: `flutter run`

Manually verify:
- [ ] Colors are correct (backgrounds, text, stock colors)
- [ ] Stock table has row dividers and correct alternating colors
- [ ] Stats bar has top border and segment gaps
- [ ] Charts render correctly
- [ ] All screens look consistent

**Step 2: Run app in light mode**

Change system to light mode and verify:
- [ ] Light theme applies correctly
- [ ] Text is readable
- [ ] Stock colors remain red/green
- [ ] No visual regressions

**Step 3: Commit any final fixes**

```bash
git add -A
git commit -m "fix: address visual polish issues from testing"
```

---

## Task 15: Merge to Main (Optional)

**Step 1: Verify all changes**

Run: `flutter analyze`
Expected: No issues found

Run: `flutter test` (if tests exist)
Expected: All tests pass

**Step 2: Create PR or merge**

```bash
git checkout main
git merge feature/ui-visual-polish
git push
```

Or create PR for review.

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Color constants | `lib/theme/app_colors.dart` |
| 2 | Text styles | `lib/theme/app_text_styles.dart` |
| 3 | Theme builders | `lib/theme/app_theme.dart` |
| 4 | Barrel export | `lib/theme/theme.dart` |
| 5 | Dual theme in main.dart | `lib/main.dart` |
| 6 | Stock table polish | `lib/widgets/stock_table.dart` |
| 7 | Stats bar polish | `lib/widgets/market_stats_bar.dart` |
| 8 | KLine chart polish | `lib/widgets/kline_chart.dart` |
| 9 | Minute chart polish | `lib/widgets/minute_chart.dart` |
| 10 | Sparkline polish | `lib/widgets/sparkline_chart.dart` |
| 11 | Status bar polish | `lib/widgets/status_bar.dart` |
| 12 | Remaining widgets | `lib/widgets/*.dart` |
| 13 | Config dialogs | `lib/widgets/*_config_dialog.dart` |
| 14 | Visual verification | Manual testing |
| 15 | Merge | Git operations |
