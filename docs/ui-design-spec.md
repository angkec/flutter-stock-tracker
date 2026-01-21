# Stock RTWatcher UI Design Specification

> **Purpose:** This document defines the UI design system for the A-share stock monitoring application. Use this as the source of truth when updating or creating new UI components.

---

## Table of Contents

1. [Design Principles](#design-principles)
2. [Color System](#color-system)
3. [Typography](#typography)
4. [Spacing & Layout](#spacing--layout)
5. [Components](#components)
6. [Screen Specifications](#screen-specifications)
7. [Navigation](#navigation)
8. [State Management](#state-management)
9. [Accessibility](#accessibility)

---

## Design Principles

### Core Philosophy

1. **Data Density** - Financial apps require high information density; prioritize data visibility over whitespace
2. **A-Share Conventions** - Follow Chinese market traditions (red=up, green=down)
3. **Glanceable** - Key metrics should be readable at a glance
4. **Touch-Friendly** - Support both tap and swipe interactions
5. **Dark Mode First** - Reduce eye strain during market hours

### Material Design 3

- Use Material 3 components and color system
- Leverage dynamic color from seed color (Blue)
- Surface container hierarchy for depth

---

## Color System

### Stock Price Colors (A-Share Convention)

| State | Color | Hex | Usage |
|-------|-------|-----|-------|
| Up/Bullish | Bright Red | `#FF4444` | Price increase, volume ratio >1 |
| Down/Bearish | Forest Green | `#00AA00` | Price decrease, volume ratio <1 |
| Flat/Neutral | Grey | `#888888` | No change |

```dart
// Define in shared constants
const Color upColor = Color(0xFFFF4444);
const Color downColor = Color(0xFF00AA00);
const Color flatColor = Color(0xFF888888);
```

### Price Change Distribution (7-Level Gradient)

| Range | Color | Hex | Description |
|-------|-------|-----|-------------|
| >= +9.8% | Pure Red | `#FF0000` | Limit up |
| +5% to +9.8% | Bright Red | `#FF4444` | Strong up |
| 0% to +5% | Light Red | `#FF8888` | Mild up |
| ~0% | Grey | `#888888` | Flat |
| 0% to -5% | Light Green | `#88CC88` | Mild down |
| -5% to -9.8% | Medium Green | `#44AA44` | Strong down |
| <= -9.8% | Forest Green | `#00AA00` | Limit down |

```dart
Color getChangeColor(double percent) {
  if (percent >= 9.8) return const Color(0xFFFF0000);
  if (percent >= 5.0) return const Color(0xFFFF4444);
  if (percent > 0.0) return const Color(0xFFFF8888);
  if (percent == 0.0) return const Color(0xFF888888);
  if (percent > -5.0) return const Color(0xFF88CC88);
  if (percent > -9.8) return const Color(0xFF44AA44);
  return const Color(0xFF00AA00);
}
```

### Market Status Colors

| Status | Color | Usage |
|--------|-------|-------|
| Pre-market | Orange | 9:15 - 9:30 |
| Trading | Green | 9:30-11:30, 13:00-15:00 |
| Lunch Break | Yellow | 11:30 - 13:00 |
| Closed | Grey | Before 9:15, after 15:00 |

### Chart Colors

| Element | Color | Hex/Value |
|---------|-------|-----------|
| Price Line | White | `Colors.white` |
| Average Line | Gold | `#FFD700` |
| Reference Line | Grey 60% | `Colors.grey.withOpacity(0.6)` |
| Candlestick Up | Red | `#FF4444` |
| Candlestick Down | Green | `#00AA00` |

### Theme Configuration

```dart
ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
)
```

### Surface Hierarchy

| Level | Usage | Access |
|-------|-------|--------|
| Surface | Base background | `colorScheme.surface` |
| Surface Container | Cards, dialogs | `colorScheme.surfaceContainer` |
| Surface Container High | Elevated sections | `colorScheme.surfaceContainerHigh` |
| Surface Container Highest | Headers, prominent areas | `colorScheme.surfaceContainerHighest` |

---

## Typography

### Font Families

| Type | Family | Usage |
|------|--------|-------|
| Default | System (Roboto) | Body text, labels |
| Monospace | `'monospace'` | Stock codes, numbers, percentages |

### Font Scale

| Name | Size | Weight | Usage |
|------|------|--------|-------|
| Title Large | 22px | Bold | Screen titles |
| Title Medium | 16px | Bold | Section headers, AppBar |
| Title Small | 14px | Bold | Card headers |
| Body Medium | 14px | Normal | Body text |
| Body Small | 12-13px | Normal | Secondary text, labels |
| Label | 11px | Normal | Tags, badges |

### Number Formatting

```dart
// Stock code
TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  fontWeight: FontWeight.w500,
)

// Percentage change
TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  fontWeight: FontWeight.w500,
  color: changeColor,  // Based on value
)

// Volume ratio
TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  fontWeight: FontWeight.w500,
  color: ratioColor,  // Red if >1, green if <1
)
```

### Text Formatting Functions

```dart
/// Format change percent with sign
String formatChangePercent(double percent) {
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(2)}%';
}

/// Format volume ratio (cap at 999+)
String formatRatio(double ratio) {
  if (ratio >= 999) return '999+';
  return ratio.toStringAsFixed(2);
}
```

---

## Spacing & Layout

### Spacing Scale

| Size | Pixels | Usage |
|------|--------|-------|
| xs | 4px | Inline element gaps |
| sm | 8px | Standard spacing |
| md | 12px | Section padding |
| lg | 16px | Major padding |
| xl | 24px | Screen-level gaps |
| 2xl | 32px | Large separations |

### Common Padding Patterns

```dart
// Standard section padding
EdgeInsets.symmetric(horizontal: 12, vertical: 8)

// Card/container padding
EdgeInsets.symmetric(horizontal: 16, vertical: 12)

// General screen padding
EdgeInsets.all(16)

// List item horizontal padding
EdgeInsets.symmetric(horizontal: 8)

// Table cell padding
EdgeInsets.symmetric(horizontal: 8)
```

### Fixed Dimensions

| Element | Dimension | Value |
|---------|-----------|-------|
| Table row height | Height | 44px |
| Stats bar height | Height | 68px |
| Chart height | Height | 280px |
| Sparkline | Width x Height | 50x20px |
| Touch target minimum | Width x Height | 32x32px |

### Column Widths (Stock Table)

| Column | Width | Alignment |
|--------|-------|-----------|
| Code | 95px | Left |
| Name | 100px | Left |
| Change % | 75px | Right |
| Volume Ratio | 65px | Right |
| Industry | 135px | Left |

### Border Radius

| Usage | Radius |
|-------|--------|
| Buttons | 4px |
| Cards | 8px |
| Badges/Tags | 10px |
| Progress bars | 3px |
| Containers | 12px |

---

## Components

### StockTable

Horizontal scrollable data table for displaying stock information.

**Structure:**
```
┌────────┬────────┬────────┬────────┬─────────────────┐
│ Code   │ Name   │ Change │ Ratio  │ Industry + Trend│
├────────┼────────┼────────┼────────┼─────────────────┤
│ 600000 │ 浦发银行│ +2.35% │ 1.52   │ 银行 ~~~        │
│ 000001 │ 平安银行│ -0.82% │ 0.87   │ 银行 ~~~        │
└────────┴────────┴────────┴────────┴─────────────────┘
```

**Features:**
- Alternating row backgrounds (odd rows: surface with 30% opacity)
- Highlighted rows for watchlist items (amber 15% opacity)
- Copy icon next to code (tap to copy)
- ST stocks displayed in orange
- Pullback indicator (*) next to name
- Industry tag with sparkline trend

**Props:**
```dart
StockTable({
  required List<StockMonitorData> stocks,
  bool isLoading = false,
  Set<String> highlightCodes = const {},
  void Function(StockMonitorData)? onLongPress,
  void Function(String industry)? onIndustryTap,
  Map<String, IndustryTrendData>? industryTrendData,
  Map<String, DailyRatioPoint>? todayTrendData,
})
```

### SparklineChart

Mini trend visualization for industry data.

**Features:**
- Reference line at 50% (dashed, grey)
- Split coloring: red above reference, green below
- Stroke width: 1.5px
- Padding: 2px

**Props:**
```dart
SparklineChart({
  required List<double> data,
  double width = 60,
  double height = 24,
  double? referenceValue,  // e.g., 50.0 for 50% threshold
})
```

### MarketStatsBar

Fixed bottom bar showing market distribution statistics.

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ [========== Change Distribution ==========]         │
│ 涨停 15  涨 1234  平 567  跌 890  跌停 12           │
│ [=== Ratio Distribution ===]                        │
│ 放量 45%  缩量 55%                                   │
└─────────────────────────────────────────────────────┘
```

**Height:** 68px

### KLineChart

Candlestick chart for daily/weekly price action.

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│                    Price Area (75%)                  │
│    ┌─┐                                              │
│    │ │  ┌─┐      Touch selection shows:            │
│  ──┴─┴──┤ ├──    Date, OHLC, Volume                │
│         └─┘                                         │
├─────────────────────────────────────────────────────┤
│                   Volume Area (25%)                  │
│    ▄▄  ▄▄▄                                          │
└─────────────────────────────────────────────────────┘
```

**Height:** 280px (default)

### MinuteChart

Intraday price chart with volume.

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│                    Price Area (75%)                  │
│         ─────────────── Avg line (gold)             │
│    ╱╲  ╱────────────── Price line (white)          │
│   ╱  ╲╱               ─── Pre-close (dashed)       │
├─────────────────────────────────────────────────────┤
│    ▄▄▄▄▄▄▄▄▄         Volume bars                    │
└─────────────────────────────────────────────────────┘
```

### IndustryHeatBar

Sector heat visualization with change distribution.

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ 银行                                                 │
│ [======Hot======][====Cold====]  Hot: 25  Cold: 15 │
│ [=== Change Distribution Bar ===]                   │
└─────────────────────────────────────────────────────┘
```

### Configuration Dialogs

Standard dialog pattern for settings.

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ Title                                          [X]  │
├─────────────────────────────────────────────────────┤
│ Setting Label 1                                     │
│ [Input Field / Switch / Slider]                     │
│                                                     │
│ Setting Label 2                                     │
│ [Choice Chips]                                      │
├─────────────────────────────────────────────────────┤
│                              [Cancel] [Save/Apply]  │
└─────────────────────────────────────────────────────┘
```

---

## Screen Specifications

### MainScreen (Tab Container)

**Navigation Bar:**
- 5 tabs with icons and labels
- Icons: Star, ShowChart, Category, TrendingDown, TrendingUp
- Labels: 自选, 全市场, 行业, 单日回踩, 多日回踩

**Tab Preservation:**
- Use `IndexedStack` to maintain state between tabs
- Tab state persists during session

### WatchlistScreen (自选)

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ [StatusBar]                                         │
├─────────────────────────────────────────────────────┤
│ [Search Input]                   [+ Add] [Refresh]  │
├─────────────────────────────────────────────────────┤
│ [StockTable - watchlist stocks]                     │
│                                                     │
│                                                     │
├─────────────────────────────────────────────────────┤
│ [MarketStatsBar]                                    │
└─────────────────────────────────────────────────────┘
```

**Actions:**
- Search by code/name
- Add stock via input field
- Long press to remove from watchlist
- Pull to refresh

### MarketScreen (全市场)

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ [StatusBar]                                         │
├─────────────────────────────────────────────────────┤
│ [Search Input with clear button]                    │
├─────────────────────────────────────────────────────┤
│ [StockTable - all market stocks with industry]      │
│                                                     │
│                                                     │
├─────────────────────────────────────────────────────┤
│ [MarketStatsBar]                                    │
└─────────────────────────────────────────────────────┘
```

**Features:**
- Search filters by code, name, or industry
- Industry tap navigates to IndustryDetailScreen
- Long press adds to watchlist

### IndustryScreen (行业)

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ AppBar: 行业热度                      [Filter Chip] │
├─────────────────────────────────────────────────────┤
│ [Industry List - sorted by heat/consecutive days]   │
│ ┌─────────────────────────────────────────────────┐ │
│ │ 银行                              Hot: 25/40    │ │
│ │ [====Heat Bar====]  Consecutive: 3 days rising │ │
│ │ [Change Distribution]                          │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

### StockDetailScreen (个股详情)

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ AppBar: 股票名 (代码)              [<] 5/25 [>]     │
├─────────────────────────────────────────────────────┤
│ [分时] [日线*] [周线]  ← SegmentedButton           │
├─────────────────────────────────────────────────────┤
│ [KLineChart / MinuteChart]                          │
├─────────────────────────────────────────────────────┤
│ [IndustryHeatBar]                                   │
├─────────────────────────────────────────────────────┤
│ [RatioHistoryList - 20 day history]                 │
├─────────────────────────────────────────────────────┤
│ [PullbackScoreCard]                                 │
└─────────────────────────────────────────────────────┘
```

**Navigation:**
- Swipe left/right to navigate between stocks
- Circular navigation (last → first, first → last)
- Default chart mode: Daily (日线)

### IndustryDetailScreen (行业详情)

**Structure:**
```
┌─────────────────────────────────────────────────────┐
│ AppBar: 行业名                              [Back]  │
│         量比趋势                                     │
├─────────────────────────────────────────────────────┤
│ [IndustryTrendChart - 30 days + today]              │
├─────────────────────────────────────────────────────┤
│ 今日: 65%  (26/40 只放量)                           │
├─────────────────────────────────────────────────────┤
│ 成分股列表                                           │
│ [StockTable - industry stocks sorted by ratio]      │
├─────────────────────────────────────────────────────┤
│ [MarketStatsBar]                                    │
└─────────────────────────────────────────────────────┘
```

---

## Navigation

### Tab Navigation

```dart
NavigationBar(
  selectedIndex: _currentIndex,
  onDestinationSelected: (index) => setState(() => _currentIndex = index),
  destinations: [
    NavigationDestination(icon: Icon(Icons.star), label: '自选'),
    NavigationDestination(icon: Icon(Icons.show_chart), label: '全市场'),
    NavigationDestination(icon: Icon(Icons.category), label: '行业'),
    NavigationDestination(icon: Icon(Icons.trending_down), label: '单日回踩'),
    NavigationDestination(icon: Icon(Icons.trending_up), label: '多日回踩'),
  ],
)
```

### Screen Navigation

```dart
// Navigate to detail screen
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => StockDetailScreen(
      stock: stock,
      stockList: stockList,  // For swipe navigation
      initialIndex: index,
    ),
  ),
);

// Navigate to industry detail
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => IndustryDetailScreen(industry: industryName),
  ),
);
```

### Detail Screen Swipe

```dart
// Manual PageView control for swipe + inner scroll compatibility
GestureDetector(
  onHorizontalDragUpdate: (details) {
    _pageController?.position.moveTo(
      _pageController!.position.pixels - details.delta.dx,
    );
  },
  onHorizontalDragEnd: (details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 300) {
      _animateToStock(_currentIndex - 1);  // Circular
    } else if (velocity < -300) {
      _animateToStock(_currentIndex + 1);  // Circular
    } else {
      // Snap back to current
    }
  },
  child: PageView.builder(
    physics: const NeverScrollableScrollPhysics(),
    // ...
  ),
)
```

---

## State Management

### Provider Setup

```dart
MultiProvider(
  providers: [
    // Level 1: Basic services
    Provider(create: (_) => IndustryService()),
    Provider(create: (_) => TdxPool(poolSize: 5)),

    // Level 2: Dependent services
    ProxyProvider<TdxPool, StockService>(
      update: (_, pool, __) => StockService(pool),
    ),

    // Level 3: Observable state
    ChangeNotifierProvider(create: (_) => WatchlistService()),
    ChangeNotifierProvider(create: (_) => PullbackService()),
    ChangeNotifierProvider(create: (_) => BreakoutService()),
    ChangeNotifierProvider(create: (_) => IndustryTrendService()),

    // Level 4: Complex dependencies
    ChangeNotifierProxyProvider5<...>(
      create: (_) => MarketDataProvider(),
      update: (_, t, s, i, p, b, provider) => provider!..updateDependencies(...),
    ),
  ],
  child: App(),
)
```

### Watching Data

```dart
// Rebuild on change
final provider = context.watch<MarketDataProvider>();
final watchlist = context.watch<WatchlistService>();

// Single read, no rebuild
final service = context.read<StockService>();
```

---

## Accessibility

### Touch Targets

- Minimum size: 32x32px
- Recommended: 44x44px for primary actions

### Tooltips

All icon buttons should have tooltips:
```dart
IconButton(
  icon: Icon(Icons.refresh),
  tooltip: '刷新数据',
  onPressed: _refresh,
)
```

### Feedback

- SnackBar for action confirmations
- Loading indicators for async operations
- Error states with retry options

### Empty States

Show helpful messages when no data:
```dart
Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.show_chart, size: 64, color: Colors.grey),
      SizedBox(height: 16),
      Text('暂无数据', style: TextStyle(fontSize: 16)),
      Text('点击刷新按钮获取数据', style: TextStyle(color: Colors.grey)),
    ],
  ),
)
```

---

## Implementation Checklist

When creating new UI:

- [ ] Use defined color constants (upColor, downColor)
- [ ] Apply correct typography (monospace for numbers)
- [ ] Follow spacing scale (4/8/12/16/24px)
- [ ] Ensure minimum touch targets (32px)
- [ ] Add tooltips to icon buttons
- [ ] Handle loading, error, and empty states
- [ ] Support pull-to-refresh where applicable
- [ ] Use Provider for state management
- [ ] Follow A-share conventions (red=up, green=down)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-21 | Initial design specification |
