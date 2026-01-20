# Market Stats Bar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a bottom floating statistics bar to the market tab showing change percent distribution and volume ratio distribution.

**Architecture:** Create a stateless `MarketStatsBar` widget that receives filtered stock data, calculates interval counts internally, and renders two rows of colored progress bars. Integrate into `MarketScreen` by wrapping the existing content in a `Stack` with the stats bar positioned at the bottom.

**Tech Stack:** Flutter, Dart

---

### Task 1: Create MarketStatsBar Widget with Change Percent Stats

**Files:**
- Create: `lib/widgets/market_stats_bar.dart`

**Step 1: Create the widget file with stats calculation**

```dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// 统计区间数据
class StatsInterval {
  final String label;
  final int count;
  final Color color;

  const StatsInterval({
    required this.label,
    required this.count,
    required this.color,
  });
}

/// 市场统计条
class MarketStatsBar extends StatelessWidget {
  final List<StockMonitorData> stocks;

  const MarketStatsBar({super.key, required this.stocks});

  /// 计算涨跌分布
  List<StatsInterval> _calculateChangeDistribution() {
    int limitUp = 0;    // >= 9.8%
    int up5 = 0;        // 5% ~ 9.8%
    int up0to5 = 0;     // 0 < x < 5%
    int flat = 0;       // == 0
    int down0to5 = 0;   // -5% < x < 0
    int down5 = 0;      // -9.8% < x <= -5%
    int limitDown = 0;  // <= -9.8%

    for (final stock in stocks) {
      final cp = stock.changePercent;
      if (cp >= 9.8) {
        limitUp++;
      } else if (cp >= 5) {
        up5++;
      } else if (cp > 0) {
        up0to5++;
      } else if (cp == 0) {
        flat++;
      } else if (cp > -5) {
        down0to5++;
      } else if (cp > -9.8) {
        down5++;
      } else {
        limitDown++;
      }
    }

    return [
      StatsInterval(label: '涨停', count: limitUp, color: const Color(0xFFFF0000)),
      StatsInterval(label: '>5%', count: up5, color: const Color(0xFFFF4444)),
      StatsInterval(label: '0~5%', count: up0to5, color: const Color(0xFFFF8888)),
      StatsInterval(label: '平', count: flat, color: const Color(0xFF888888)),
      StatsInterval(label: '-5~0', count: down0to5, color: const Color(0xFF88CC88)),
      StatsInterval(label: '<-5%', count: down5, color: const Color(0xFF44AA44)),
      StatsInterval(label: '跌停', count: limitDown, color: const Color(0xFF00AA00)),
    ];
  }

  /// 计算量比分布
  (int above, int below) _calculateRatioDistribution() {
    int above = 0;
    int below = 0;
    for (final stock in stocks) {
      if (stock.ratio >= 1.0) {
        above++;
      } else {
        below++;
      }
    }
    return (above, below);
  }

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty) return const SizedBox.shrink();

    final changeStats = _calculateChangeDistribution();
    final (ratioAbove, ratioBelow) = _calculateRatioDistribution();
    final total = stocks.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 涨跌分布
          _buildChangeRow(context, changeStats, total),
          const SizedBox(height: 8),
          // 量比分布
          _buildRatioRow(context, ratioAbove, ratioBelow, total),
        ],
      ),
    );
  }

  Widget _buildChangeRow(BuildContext context, List<StatsInterval> stats, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签和数字行
        Row(
          children: stats.map((s) => Expanded(
            flex: s.count > 0 ? s.count : 1,
            child: Text(
              '${s.label}\n${s.count}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 4),
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: stats.map((s) {
              final flex = s.count > 0 ? s.count : 0;
              if (flex == 0) return const SizedBox.shrink();
              return Expanded(
                flex: flex,
                child: Container(
                  height: 8,
                  color: s.color,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRatioRow(BuildContext context, int above, int below, int total) {
    final abovePercent = total > 0 ? (above / total * 100).toStringAsFixed(0) : '0';
    final belowPercent = total > 0 ? (below / total * 100).toStringAsFixed(0) : '0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: above > 0 ? above : 1,
              child: Text(
                '量比>1: $above ($abovePercent%)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Expanded(
              flex: below > 0 ? below : 1,
              child: Text(
                '量比<1: $below ($belowPercent%)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              if (above > 0)
                Expanded(
                  flex: above,
                  child: Container(
                    height: 8,
                    color: const Color(0xFFFF4444),
                  ),
                ),
              if (below > 0)
                Expanded(
                  flex: below,
                  child: Container(
                    height: 8,
                    color: const Color(0xFF00AA00),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
```

**Step 2: Run analyze to verify no errors**

Run: `flutter analyze lib/widgets/market_stats_bar.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/widgets/market_stats_bar.dart
git commit -m "feat: add MarketStatsBar widget"
```

---

### Task 2: Integrate MarketStatsBar into MarketScreen

**Files:**
- Modify: `lib/screens/market_screen.dart`

**Step 1: Add import**

Add at the top of the file after other imports:

```dart
import 'package:stock_rtwatcher/widgets/market_stats_bar.dart';
```

**Step 2: Wrap body content with Stack and add stats bar**

Replace the `Scaffold` body in the `build` method. Change from:

```dart
      body: SafeArea(
        child: Column(
          children: [
            StatusBar(...),
            // 搜索框
            if (_monitorData.isNotEmpty)
              Padding(...),
            Expanded(
              child: StockTable(...),
            ),
          ],
        ),
      ),
```

To:

```dart
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                StatusBar(
                  updateTime: _updateTime,
                  progress: _progress > 0 ? _progress : null,
                  total: _total > 0 ? _total : null,
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                ),
                // 搜索框
                if (_monitorData.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索代码或名称',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 68),
                    child: StockTable(
                      stocks: filteredData,
                      isLoading: _isLoading,
                      highlightCodes: watchlistService.watchlist.toSet(),
                      onTap: (data) => _addToWatchlist(data.stock.code, data.stock.name),
                      onIndustryTap: searchByIndustry,
                    ),
                  ),
                ),
              ],
            ),
            // 底部统计条
            if (filteredData.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MarketStatsBar(stocks: filteredData),
              ),
          ],
        ),
      ),
```

**Step 3: Run analyze to verify no errors**

Run: `flutter analyze lib/screens/market_screen.dart`
Expected: No issues found

**Step 4: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/screens/market_screen.dart
git commit -m "feat: integrate MarketStatsBar into MarketScreen"
```

---

### Task 3: Manual Integration Test

**Step 1: Run the app**

Run: `flutter run -d macos` (or your preferred device)

**Step 2: Verify functionality**

1. Navigate to the market tab
2. Click refresh to load data
3. Verify the bottom stats bar appears with:
   - First row: 7 change percent intervals with numbers and colored progress bar
   - Second row: Volume ratio distribution with percentages
4. Type an industry name (e.g., "银行") in search
5. Verify stats bar updates to show only that industry's statistics
6. Clear search
7. Verify stats bar shows full market statistics again

**Step 3: Final commit if all works**

```bash
git commit --allow-empty -m "test: verified market stats bar feature manually"
```

---

## Summary

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Create MarketStatsBar widget | `feat: add MarketStatsBar widget` |
| 2 | Integrate into MarketScreen | `feat: integrate MarketStatsBar into MarketScreen` |
| 3 | Manual integration test | `test: verified market stats bar feature manually` |
