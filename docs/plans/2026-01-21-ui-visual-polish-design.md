# UI Visual Polish Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Modernize the app's visual appearance with a Modern Fintech aesthetic while preserving data density and efficiency.

**Style Reference:** Robinhood, Trading212 - clean lines, subtle refinements, professional feel

**Constraint:** Efficiency trumps aesthetics. No unnecessary padding or chrome that reduces information density.

---

## 1. Color System

### Dark Mode Palette

| Token | Hex | Usage |
|-------|-----|-------|
| Background | `#0D0D0D` | Main screen background |
| Surface | `#1A1A1A` | Elevated content, cards where needed |
| Surface Variant | `#242424` | Hover/press states |
| Divider | `#2A2A2A` | Subtle separation lines |
| Primary | `#4A90D9` | Accent blue, buttons, links |
| Text Primary | `#E8E8E8` | Main content text |
| Text Secondary | `#888888` | Labels, hints, supporting text |

### Light Mode Palette

| Token | Hex | Usage |
|-------|-----|-------|
| Background | `#FAFAFA` | Main screen background |
| Surface | `#FFFFFF` | Elevated content, cards |
| Surface Variant | `#F0F1F3` | Hover/press states |
| Divider | `#E5E5E5` | Subtle separation lines |
| Primary | `#2563EB` | Accent blue, buttons, links |
| Text Primary | `#1A1A1A` | Main content text |
| Text Secondary | `#6B7280` | Labels, hints, supporting text |

### Stock Colors (Both Modes - Unchanged)

| State | Hex | Usage |
|-------|-----|-------|
| Up | `#FF4444` | Price increase, ratio > 1 |
| Down | `#00AA00` | Price decrease, ratio < 1 |
| Flat | `#888888` | No change |

### Theme Detection

```dart
brightness: MediaQuery.platformBrightnessOf(context)
```

No in-app toggle - follow system setting.

---

## 2. Typography

### Text Scale

| Role | Size | Weight | Usage |
|------|------|--------|-------|
| Title | 18px | 600 | Screen titles in AppBar |
| Section | 14px | 600 | Section headers |
| Body | 13px | 400 | Primary content, names |
| Data | 13px | 500 | Numbers, percentages (monospace) |
| Caption | 11px | 400 | Secondary info, timestamps |

### Number Styling

```dart
const dataTextStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  fontWeight: FontWeight.w500,
  letterSpacing: -0.3,
);
```

### Consistency Rules

- All financial data uses monospace
- ST stocks: orange color on name
- Secondary text: always use Text Secondary color

---

## 3. Components

### Stock Table

| Change | Details |
|--------|---------|
| Row hover/press | Subtle background change to Surface Variant |
| Alternating rows | Reduce opacity from 30% to 15% |
| Dividers | Add 0.5px lines between rows |
| Header | Slightly bolder background, sticky on scroll |

### Interactive Elements

| Element | Specification |
|---------|--------------|
| Buttons | Filled for primary, outlined for secondary. 8px radius |
| Search input | 1px border, subtle focus ring, clear button visible when text exists |
| Chips/Tags | 6px radius, ensure 32px touch target via padding |

### Status Indicators

| Element | Specification |
|---------|--------------|
| Loading spinner | 20px inline, 36px full-screen |
| Empty state icon | 40px, lighter color |
| Snackbars | Theme surface color, ensure text contrast |

### Cards Usage

**Use cards for:**
- Configuration summary bars
- Score/status cards (pullback detection)
- Chart containers

**Avoid cards for:**
- Stock tables (keep flat)
- List items (use dividers)
- Stats bars (keep compact)

---

## 4. Charts & Data Visualization

### KLineChart

| Element | Change |
|---------|--------|
| Candle wicks | Reduce to 0.8px width |
| Touch selection | Add dashed crosshair lines (50% opacity) |
| Grid | Subtle horizontal lines only (10% opacity) |
| Volume bars | Reduce to 80% opacity |

### MinuteChart

| Element | Change |
|---------|--------|
| Price line | Add gradient fill below (white → transparent, 10% opacity) |
| Average line | Reduce to 80% opacity |
| Pre-close line | Keep dashed, ensure consistent pattern |

### SparklineChart

No major changes. Keep:
- 1.5px stroke width
- Split coloring at reference value
- Reduce dash gap slightly on reference line

### MarketStatsBar

| Element | Change |
|---------|--------|
| Bar segments | Add 1px gap between color segments |
| Labels | Consistent positioning, slight text shadow in dark mode |

---

## 5. Screen Layout & Transitions

### Screen Structure

| Element | Change |
|---------|--------|
| AppBar | Ensure vertical centering of title and actions |
| Bottom StatsBar | Add 1px top border (divider color) |
| Safe area | Consistent handling on all screens |

### Animations

| Interaction | Specification |
|-------------|--------------|
| Screen navigation | Default MaterialPageRoute slide |
| Tab switching | Instant (IndexedStack) |
| Stock detail swipe | 300ms easeInOut (existing) |
| Data loading | 200ms fade in for new data |
| Pull-to-refresh | Default RefreshIndicator |

---

## 6. Implementation Order

1. **Theme setup** - Create light/dark color schemes, wire up system detection
2. **Typography constants** - Define text styles, apply consistently
3. **Table refinements** - Row styling, dividers, hover states
4. **Component polish** - Buttons, inputs, chips, status indicators
5. **Chart updates** - KLine, Minute, Sparkline refinements
6. **Screen-level polish** - AppBar, StatsBar, transitions
7. **Testing** - Verify both themes on all screens

---

## 7. Files to Modify

| File | Changes |
|------|---------|
| `lib/main.dart` | Theme configuration, light/dark setup |
| `lib/theme/` (new) | Color constants, text styles |
| `lib/widgets/stock_table.dart` | Row styling, dividers |
| `lib/widgets/kline_chart.dart` | Grid, crosshairs, opacity |
| `lib/widgets/minute_chart.dart` | Gradient fill, opacity |
| `lib/widgets/sparkline_chart.dart` | Minor refinements |
| `lib/widgets/market_stats_bar.dart` | Segment gaps, border |
| All screens | Apply consistent text styles |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-21 | Initial design |
