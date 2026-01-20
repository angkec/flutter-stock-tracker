# Industry Search Enhancement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable searching stocks by industry tags, with clickable industry Chips that auto-fill the search box.

**Architecture:** Extend IndustryService to expose all industry names, update StockTable to render industry as clickable Chips with a callback, and modify MarketScreen to handle industry-based filtering separately from code/name search.

**Tech Stack:** Flutter, Dart

---

### Task 1: Extend IndustryService

**Files:**
- Modify: `lib/services/industry_service.dart`
- Test: `test/services/industry_service_test.dart`

**Step 1: Write the failing test**

Add to `test/services/industry_service_test.dart`:

```dart
  test('allIndustries returns unique industry names', () {
    final service = IndustryService();
    service.setTestData({
      '000001': '银行',
      '000002': '房地产',
      '600519': '食品饮料',
      '601398': '银行',
    });

    final industries = service.allIndustries;

    expect(industries, isA<Set<String>>());
    expect(industries.length, 3);
    expect(industries, contains('银行'));
    expect(industries, contains('房地产'));
    expect(industries, contains('食品饮料'));
  });
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/industry_service_test.dart`
Expected: FAIL with "The getter 'allIndustries' isn't defined"

**Step 3: Write minimal implementation**

Add to `lib/services/industry_service.dart` after line 16:

```dart
  /// 获取所有唯一行业名称
  Set<String> get allIndustries => _data.values.toSet();
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/industry_service_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/industry_service.dart test/services/industry_service_test.dart
git commit -m "feat: add allIndustries getter to IndustryService"
```

---

### Task 2: Add onIndustryTap callback to StockTable

**Files:**
- Modify: `lib/widgets/stock_table.dart`

**Step 1: Add callback parameter**

Add to the class fields after line 35:

```dart
  final void Function(String industry)? onIndustryTap;
```

**Step 2: Update constructor**

Change constructor (lines 37-44) to:

```dart
  const StockTable({
    super.key,
    required this.stocks,
    this.isLoading = false,
    this.highlightCodes = const {},
    this.onLongPress,
    this.onTap,
    this.onIndustryTap,
  });
```

**Step 3: Run analyze to verify no errors**

Run: `flutter analyze lib/widgets/stock_table.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/widgets/stock_table.dart
git commit -m "feat: add onIndustryTap callback to StockTable"
```

---

### Task 3: Replace industry text with clickable Chip

**Files:**
- Modify: `lib/widgets/stock_table.dart`

**Step 1: Replace industry column in _buildRow**

Replace lines 187-198 (the industry SizedBox) with:

```dart
          // 行业列
          SizedBox(
            width: _industryWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: data.industry != null
                  ? GestureDetector(
                      onTap: onIndustryTap != null
                          ? () => onIndustryTap!(data.industry!)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          data.industry!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  : const Text('-', style: TextStyle(fontSize: 13)),
            ),
          ),
```

**Step 2: Run analyze to verify no errors**

Run: `flutter analyze lib/widgets/stock_table.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/widgets/stock_table.dart
git commit -m "feat: render industry as clickable Chip in StockTable"
```

---

### Task 4: Update MarketScreen search logic

**Files:**
- Modify: `lib/screens/market_screen.dart`

**Step 1: Add _searchByIndustry method**

Add after `_formatCurrentTime()` method (around line 124):

```dart
  void _searchByIndustry(String industry) {
    _searchController.text = industry;
    setState(() => _searchQuery = industry);
  }
```

**Step 2: Update _filteredData getter**

Replace the `_filteredData` getter (lines 44-51) with:

```dart
  List<StockMonitorData> get _filteredData {
    if (_searchQuery.isEmpty) return _monitorData;

    final query = _searchQuery.trim();
    final industryService = context.read<IndustryService>();

    // 如果是完整行业名，只按行业筛选
    if (industryService.allIndustries.contains(query)) {
      return _monitorData.where((d) => d.industry == query).toList();
    }

    // 否则按代码/名称搜索
    final lowerQuery = query.toLowerCase();
    return _monitorData
        .where((d) =>
            d.stock.code.contains(lowerQuery) ||
            d.stock.name.toLowerCase().contains(lowerQuery))
        .toList();
  }
```

**Step 3: Run analyze to verify no errors**

Run: `flutter analyze lib/screens/market_screen.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/screens/market_screen.dart
git commit -m "feat: add industry search logic to MarketScreen"
```

---

### Task 5: Connect StockTable onIndustryTap

**Files:**
- Modify: `lib/screens/market_screen.dart`

**Step 1: Add onIndustryTap to StockTable**

Find the StockTable widget in build() (around line 206) and add the onIndustryTap parameter:

```dart
            Expanded(
              child: StockTable(
                stocks: filteredData,
                isLoading: _isLoading,
                highlightCodes: watchlistService.watchlist.toSet(),
                onTap: (data) => _addToWatchlist(data.stock.code, data.stock.name),
                onIndustryTap: _searchByIndustry,
              ),
            ),
```

**Step 2: Run full analysis**

Run: `flutter analyze lib/`
Expected: No issues found

**Step 3: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add lib/screens/market_screen.dart
git commit -m "feat: connect industry tap to search in MarketScreen"
```

---

### Task 6: Manual Integration Test

**Step 1: Run the app**

Run: `flutter run -d macos` (or your preferred device)

**Step 2: Verify functionality**

1. Click refresh to load market data
2. Verify industry Chips are displayed with rounded background
3. Click an industry Chip (e.g., "银行")
4. Verify search box shows "银行"
5. Verify only stocks with industry "银行" are displayed
6. Clear the search box
7. Verify all stocks are displayed again
8. Type "平安" in search box
9. Verify stocks with "平安" in name are displayed (not industry filter)

**Step 3: Final commit if all works**

```bash
git commit --allow-empty -m "test: verified industry search feature manually"
```

---

## Summary

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Add allIndustries getter | `feat: add allIndustries getter to IndustryService` |
| 2 | Add onIndustryTap callback | `feat: add onIndustryTap callback to StockTable` |
| 3 | Render industry as Chip | `feat: render industry as clickable Chip in StockTable` |
| 4 | Update search logic | `feat: add industry search logic to MarketScreen` |
| 5 | Connect tap to search | `feat: connect industry tap to search in MarketScreen` |
| 6 | Manual integration test | `test: verified industry search feature manually` |
