# Industry Statistics Tab Design

## Overview

Add a third tab "行业" (Industry) showing statistics for all Shenwan industries. Each row displays: industry name, up/down distribution mini progress bar, and volume ratio numbers. Sorted by ratio of (量比>1 count) / (量比<1 count) descending. Clicking an industry jumps to market tab and filters by that industry.

## Statistics per Industry

1. **涨跌分布** - Count of rising/falling stocks
2. **量比分布** - Count of stocks with ratio > 1 vs < 1

## UI Layout

Row height: ~48px

```
| 银行        [====|==] 涨12 跌8  >1:15 <1:5 |
| 房地产      [==|====] 涨5  跌18 >1:8  <1:15|
| 食品饮料    [===|===] 涨10 跌10 >1:12 <1:8 |
```

Components:
- **Industry name**: Left-aligned, fixed width
- **Progress bar**: Red/green dual-color bar, proportional to up/down counts
- **Up/down numbers**: 涨X 跌Y
- **Ratio numbers**: >1:X <1:Y

## Sorting

Default: `(>1 count) / (<1 count)` descending (industries with higher buying pressure first)

## Interaction

- Click industry row → Jump to market tab → Search box set to industry name

## Data Flow

1. Get full market data from shared state (same data as MarketScreen)
2. Group by industry
3. Calculate stats per industry
4. Sort by ratio distribution
5. Display

## Implementation

### New Files
- `lib/screens/industry_screen.dart` - Industry statistics screen
- `lib/models/industry_stats.dart` - Industry statistics data model

### Modified Files
- `lib/screens/main_screen.dart` - Add third tab

### Reuse
- `_goToMarketAndSearchIndustry` callback for navigation
