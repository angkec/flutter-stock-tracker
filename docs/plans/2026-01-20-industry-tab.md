# Industry Statistics Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a third tab showing per-industry statistics with up/down distribution, volume ratio counts, sorted by ratio distribution.

**Architecture:** Create IndustryScreen that fetches market data via existing services, groups by industry, calculates stats, and displays in a sorted list. Reuse existing navigation callback for jumping to market tab on industry click.

**Tech Stack:** Flutter, Dart, Provider

---

### Task 1: Create IndustryStats Data Model

**Files:**
- Create: `lib/models/industry_stats.dart`

**Step 1: Create the model file**

```dart
/// 行业统计数据
class IndustryStats {
  final String name;
  final int upCount;      // 上涨数量
  final int downCount;    // 下跌数量
  final int flatCount;    // 平盘数量
  final int ratioAbove;   // 量比>1 数量
  final int ratioBelow;   // 量比<1 数量

  const IndustryStats({
    required this.name,
    required this.upCount,
    required this.downCount,
    required this.flatCount,
    required this.ratioAbove,
    required this.ratioBelow,
  });

  /// 总股票数
  int get total => upCount + downCount + flatCount;

  /// 量比排序值 (>1数量 / <1数量)，<1数量为0时返回无穷大
  double get ratioSortValue {
    if (ratioBelow == 0) return double.infinity;
    return ratioAbove / ratioBelow;
  }
}
```

**Step 2: Run analyze to verify no errors**

Run: `flutter analyze lib/models/industry_stats.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/models/industry_stats.dart
git commit -m "feat: add IndustryStats data model"
```

---

### Task 2: Create IndustryScreen

**Files:**
- Create: `lib/screens/industry_screen.dart`

**Step 1: Create the screen file**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class IndustryScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const IndustryScreen({super.key, this.onIndustryTap});

  @override
  State<IndustryScreen> createState() => _IndustryScreenState();
}

class _IndustryScreenState extends State<IndustryScreen> {
  List<IndustryStats> _stats = [];
  String? _updateTime;
  int _progress = 0;
  int _total = 0;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  /// 计算行业统计
  Map<String, IndustryStats> _calculateStats(List<StockMonitorData> data) {
    final Map<String, List<StockMonitorData>> grouped = {};

    for (final stock in data) {
      final industry = stock.industry ?? '未知';
      grouped.putIfAbsent(industry, () => []).add(stock);
    }

    final result = <String, IndustryStats>{};
    for (final entry in grouped.entries) {
      int up = 0, down = 0, flat = 0, ratioAbove = 0, ratioBelow = 0;

      for (final stock in entry.value) {
        // 涨跌统计
        if (stock.changePercent > 0.001) {
          up++;
        } else if (stock.changePercent < -0.001) {
          down++;
        } else {
          flat++;
        }
        // 量比统计
        if (stock.ratio >= 1.0) {
          ratioAbove++;
        } else {
          ratioBelow++;
        }
      }

      result[entry.key] = IndustryStats(
        name: entry.key,
        upCount: up,
        downCount: down,
        flatCount: flat,
        ratioAbove: ratioAbove,
        ratioBelow: ratioBelow,
      );
    }

    return result;
  }

  Future<void> _refresh() async {
    if (_isLoading) return;

    final pool = context.read<TdxPool>();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connected = await pool.ensureConnected();
      if (!mounted) return;

      if (!connected) {
        setState(() {
          _isLoading = false;
          _errorMessage = '无法连接到服务器';
        });
        return;
      }

      final stockService = context.read<StockService>();
      final industryService = context.read<IndustryService>();

      // 获取股票列表
      final stocks = await stockService.getAllStocks();
      if (!mounted) return;

      setState(() {
        _total = stocks.length;
      });

      // 获取监控数据
      final data = await stockService.batchGetMonitorData(
        stocks,
        industryService: industryService,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progress = current;
              _total = total;
            });
          }
        },
      );

      if (!mounted) return;

      // 计算行业统计
      final statsMap = _calculateStats(data);
      final statsList = statsMap.values.toList()
        ..sort((a, b) => b.ratioSortValue.compareTo(a.ratioSortValue));

      setState(() {
        _stats = statsList;
        _updateTime = _formatTime();
        _isLoading = false;
        _progress = 0;
        _total = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '获取数据失败: $e';
        _isLoading = false;
        _progress = 0;
        _total = 0;
      });
    }
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            StatusBar(
              updateTime: _updateTime,
              progress: _progress > 0 ? _progress : null,
              total: _total > 0 ? _total : null,
              isLoading: _isLoading,
              errorMessage: _errorMessage,
            ),
            Expanded(
              child: _stats.isEmpty && !_isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无数据',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击刷新按钮获取数据',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _stats.length,
                        itemExtent: 48,
                        itemBuilder: (context, index) =>
                            _buildRow(context, _stats[index], index),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _refresh,
        tooltip: '刷新数据',
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildRow(BuildContext context, IndustryStats stats, int index) {
    final upColor = const Color(0xFFFF4444);
    final downColor = const Color(0xFF00AA00);

    return GestureDetector(
      onTap: widget.onIndustryTap != null
          ? () => widget.onIndustryTap!(stats.name)
          : null,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: index.isOdd
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            // 行业名
            SizedBox(
              width: 80,
              child: Text(
                stats.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 涨跌进度条
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      if (stats.upCount > 0)
                        Expanded(
                          flex: stats.upCount,
                          child: Container(height: 8, color: upColor),
                        ),
                      if (stats.downCount > 0)
                        Expanded(
                          flex: stats.downCount,
                          child: Container(height: 8, color: downColor),
                        ),
                      if (stats.upCount == 0 && stats.downCount == 0)
                        Expanded(
                          child: Container(
                            height: 8,
                            color: Colors.grey.withValues(alpha: 0.3),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // 涨跌数字
            SizedBox(
              width: 70,
              child: Text(
                '涨${stats.upCount} 跌${stats.downCount}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
            // 量比数字
            SizedBox(
              width: 70,
              child: Text(
                '>1:${stats.ratioAbove} <1:${stats.ratioBelow}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Run analyze to verify no errors**

Run: `flutter analyze lib/screens/industry_screen.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/screens/industry_screen.dart
git commit -m "feat: add IndustryScreen for industry statistics"
```

---

### Task 3: Add Industry Tab to MainScreen

**Files:**
- Modify: `lib/screens/main_screen.dart`

**Step 1: Add import**

Add after other imports:

```dart
import 'package:stock_rtwatcher/screens/industry_screen.dart';
```

**Step 2: Add IndustryScreen to _screens list**

In `initState()`, change the `_screens` initialization to include IndustryScreen:

```dart
  @override
  void initState() {
    super.initState();
    _screens = [
      WatchlistScreen(onIndustryTap: _goToMarketAndSearchIndustry),
      MarketScreen(key: _marketScreenKey),
      IndustryScreen(onIndustryTap: _goToMarketAndSearchIndustry),
    ];
  }
```

**Step 3: Add third NavigationDestination**

In the `build()` method, add a third destination to NavigationBar:

```dart
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: '自选',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: '全市场',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: '行业',
          ),
        ],
```

**Step 4: Run analyze to verify no errors**

Run: `flutter analyze lib/screens/main_screen.dart`
Expected: No issues found

**Step 5: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/screens/main_screen.dart
git commit -m "feat: add industry tab to MainScreen"
```

---

### Task 4: Manual Integration Test

**Step 1: Run the app**

Run: `flutter run -d macos` (or your preferred device)

**Step 2: Verify functionality**

1. Verify three tabs are visible: 自选, 全市场, 行业
2. Navigate to 行业 tab
3. Click refresh to load data
4. Verify industries are listed with:
   - Industry name on the left
   - Red/green progress bar showing up/down distribution
   - 涨X 跌Y numbers
   - >1:X <1:Y numbers
5. Verify list is sorted by >1/<1 ratio (industries with more >1 stocks first)
6. Click on an industry (e.g., "银行")
7. Verify it jumps to 全市场 tab with "银行" in search box
8. Verify only stocks from that industry are shown

**Step 3: Final commit if all works**

```bash
git commit --allow-empty -m "test: verified industry tab feature manually"
```

---

## Summary

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Create IndustryStats model | `feat: add IndustryStats data model` |
| 2 | Create IndustryScreen | `feat: add IndustryScreen for industry statistics` |
| 3 | Add industry tab to MainScreen | `feat: add industry tab to MainScreen` |
| 4 | Manual integration test | `test: verified industry tab feature manually` |
