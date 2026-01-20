# Market Stats Bar Design

## Overview

Add a floating statistics bar at the bottom of the market tab, displaying change percent distribution and volume ratio distribution. The stats apply to both full market view and industry-filtered view.

## Statistics

### Change Percent Distribution (7 intervals)

| Interval | Condition |
|----------|-----------|
| 涨停 (Limit Up) | changePercent >= 9.8% |
| >5% | 5% <= changePercent < 9.8% |
| 0~5% | 0 < changePercent < 5% |
| 平 (Flat) | changePercent == 0 |
| -5~0 | -5% < changePercent < 0 |
| <-5% | -9.8% < changePercent <= -5% |
| 跌停 (Limit Down) | changePercent <= -9.8% |

### Volume Ratio Distribution (2 intervals)

| Interval | Condition |
|----------|-----------|
| 量比>1 | ratio >= 1.0 |
| 量比<1 | ratio < 1.0 |

## UI Layout

Stats bar height: ~60px, two rows

### Row 1: Change Percent Distribution
```
涨停 | >5% | 0~5% | 平 | -5~0 | <-5% | 跌停
 12    45    320   28   280    38     8
[========================================]
 红                灰              绿
```

### Row 2: Volume Ratio Distribution
```
量比>1: 412 (56%)  |  量比<1: 319 (44%)
[===================|================]
      红                  绿
```

## Visual Design

- Progress bar width proportional to count in each interval
- Color gradient: Red (limit up) -> Light red -> Gray (flat) -> Light green -> Green (limit down)
- Numbers displayed above or inside color blocks

## Data Source

- Uses `_filteredData` list (respects search/industry filter)
- Real-time updates: recalculates when data changes

## Implementation

### New File
- `lib/widgets/market_stats_bar.dart` - Stats bar widget

### Modified File
- `lib/screens/market_screen.dart` - Add stats bar at bottom

### Component API
```dart
MarketStatsBar(
  stocks: filteredData,  // Current displayed stock list
)
```

Stats bar internally calculates interval counts and renders progress bars. Auto-recalculates when `stocks` changes.
