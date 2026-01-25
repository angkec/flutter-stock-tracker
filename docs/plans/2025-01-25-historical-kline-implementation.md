# Historical Kline Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate minute K-line data fetching into a single `HistoricalKlineService` with incremental fetching, eliminating duplicate API calls between `IndustryTrendService` and `IndustryRankService`.

**Architecture:** Create a new `HistoricalKlineService` that stores raw minute K-lines, supports incremental fetching by detecting missing dates, and provides daily volume summaries. Existing services will read from this shared cache instead of fetching their own data.

**Tech Stack:** Flutter/Dart, Provider for state management, SharedPreferences for persistence, TdxPool for data fetching.

---

## Task 1: Create HistoricalKlineService - Data Structure and Basic Methods

**Files:**
- Create: `lib/services/historical_kline_service.dart`
- Test: `test/services/historical_kline_service_test.dart`

**Step 1: Write the failing test for date utilities**

```dart
// test/services/historical_kline_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';

void main() {
  group('HistoricalKlineService', () {
    group('date utilities', () {
      test('formatDate returns YYYY-MM-DD format', () {
        final date = DateTime(2025, 1, 25);
        expect(HistoricalKlineService.formatDate(date), '2025-01-25');
      });

      test('formatDate pads single digit month and day', () {
        final date = DateTime(2025, 3, 5);
        expect(HistoricalKlineService.formatDate(date), '2025-03-05');
      });

      test('parseDate parses YYYY-MM-DD format', () {
        final date = HistoricalKlineService.parseDate('2025-01-25');
        expect(date.year, 2025);
        expect(date.month, 1);
        expect(date.day, 25);
      });
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: FAIL with "Target of URI hasn't been generated"

**Step 3: Write minimal implementation**

```dart
// lib/services/historical_kline_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

/// 历史分钟K线数据服务
/// 统一管理原始分钟K线，支持增量拉取
class HistoricalKlineService extends ChangeNotifier {
  static const String _storageKey = 'historical_kline_cache_v1';
  static const int _maxCacheDays = 30;

  /// 存储：按股票代码索引
  /// stockCode -> List<KLine> (按时间升序排列)
  Map<String, List<KLine>> _stockBars = {};

  /// 已完整拉取的日期集合
  Set<String> _completeDates = {};

  /// 最后拉取时间
  DateTime? _lastFetchTime;

  /// 是否正在加载
  bool _isLoading = false;

  // Getters
  bool get isLoading => _isLoading;
  DateTime? get lastFetchTime => _lastFetchTime;
  Set<String> get completeDates => Set.unmodifiable(_completeDates);
  int get stockCount => _stockBars.length;

  /// 格式化日期为 "YYYY-MM-DD" 字符串
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 解析 "YYYY-MM-DD" 字符串为 DateTime
  static DateTime parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "feat: add HistoricalKlineService with date utilities"
```

---

## Task 2: Add Daily Volume Calculation

**Files:**
- Modify: `lib/services/historical_kline_service.dart`
- Modify: `test/services/historical_kline_service_test.dart`

**Step 1: Write the failing test for daily volume calculation**

```dart
// Add to test/services/historical_kline_service_test.dart
import 'package:stock_rtwatcher/models/kline.dart';

// Add helper function at top level
List<KLine> _generateBars(DateTime date, int upCount, int downCount, {double upVol = 100, double downVol = 100}) {
  final bars = <KLine>[];
  for (var i = 0; i < upCount; i++) {
    bars.add(KLine(
      datetime: date.add(Duration(minutes: i)),
      open: 10, close: 11, high: 11, low: 10,
      volume: upVol, amount: 0,
    ));
  }
  for (var i = 0; i < downCount; i++) {
    bars.add(KLine(
      datetime: date.add(Duration(minutes: upCount + i)),
      open: 11, close: 10, high: 11, low: 10,
      volume: downVol, amount: 0,
    ));
  }
  return bars;
}

// Add in main() group
group('getDailyVolumes', () {
  late HistoricalKlineService service;

  setUp(() {
    service = HistoricalKlineService();
  });

  test('returns empty map for unknown stock', () {
    final volumes = service.getDailyVolumes('999999');
    expect(volumes, isEmpty);
  });

  test('calculates daily up/down volumes correctly', () {
    final date1 = DateTime(2025, 1, 24, 9, 30);
    final date2 = DateTime(2025, 1, 25, 9, 30);

    final bars = [
      ..._generateBars(date1, 5, 3, upVol: 100, downVol: 50),
      ..._generateBars(date2, 4, 6, upVol: 200, downVol: 100),
    ];

    service.setStockBars('000001', bars);

    final volumes = service.getDailyVolumes('000001');

    expect(volumes.length, 2);
    expect(volumes['2025-01-24']?.up, 500); // 5 * 100
    expect(volumes['2025-01-24']?.down, 150); // 3 * 50
    expect(volumes['2025-01-25']?.up, 800); // 4 * 200
    expect(volumes['2025-01-25']?.down, 600); // 6 * 100
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: FAIL with "setStockBars" and "getDailyVolumes" not defined

**Step 3: Write minimal implementation**

```dart
// Add to lib/services/historical_kline_service.dart class

  /// 设置某只股票的K线数据（用于测试）
  @visibleForTesting
  void setStockBars(String stockCode, List<KLine> bars) {
    _stockBars[stockCode] = bars..sort((a, b) => a.datetime.compareTo(b.datetime));
  }

  /// 获取某只股票所有日期的涨跌量汇总
  /// 返回 { dateKey: (up: upVolume, down: downVolume) }
  Map<String, ({double up, double down})> getDailyVolumes(String stockCode) {
    final bars = _stockBars[stockCode];
    if (bars == null || bars.isEmpty) return {};

    final result = <String, ({double up, double down})>{};

    for (final bar in bars) {
      final dateKey = formatDate(bar.datetime);
      final current = result[dateKey];

      double upAdd = 0;
      double downAdd = 0;
      if (bar.isUp) {
        upAdd = bar.volume;
      } else if (bar.isDown) {
        downAdd = bar.volume;
      }

      result[dateKey] = (
        up: (current?.up ?? 0) + upAdd,
        down: (current?.down ?? 0) + downAdd,
      );
    }

    return result;
  }
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "feat: add getDailyVolumes to HistoricalKlineService"
```

---

## Task 3: Add Missing Days Calculation

**Files:**
- Modify: `lib/services/historical_kline_service.dart`
- Modify: `test/services/historical_kline_service_test.dart`

**Step 1: Write the failing test**

```dart
// Add to test file
group('getMissingDays', () {
  late HistoricalKlineService service;

  setUp(() {
    service = HistoricalKlineService();
  });

  test('returns expected trading days when no data', () {
    // With no complete dates, all estimated trading days are missing
    final missing = service.getMissingDays();
    expect(missing, greaterThan(0));
  });

  test('returns 0 when all recent dates are complete', () {
    // Simulate having all recent trading days
    final today = DateTime.now();
    for (var i = 1; i <= 30; i++) {
      final date = today.subtract(Duration(days: i));
      if (date.weekday != DateTime.saturday && date.weekday != DateTime.sunday) {
        service.addCompleteDate(HistoricalKlineService.formatDate(date));
      }
    }
    final missing = service.getMissingDays();
    expect(missing, 0);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
// Add to lib/services/historical_kline_service.dart

  /// 添加已完成日期（用于测试）
  @visibleForTesting
  void addCompleteDate(String dateKey) {
    _completeDates.add(dateKey);
  }

  /// 估算最近N个交易日（排除周末）
  List<DateTime> _estimateTradingDays(DateTime from, int count) {
    final days = <DateTime>[];
    var current = from;
    var checked = 0;

    while (days.length < count && checked < count * 2) {
      current = current.subtract(const Duration(days: 1));
      checked++;
      if (current.weekday == DateTime.saturday || current.weekday == DateTime.sunday) {
        continue;
      }
      days.add(DateTime(current.year, current.month, current.day));
    }

    return days;
  }

  /// 获取缺失天数
  int getMissingDays() {
    final today = DateTime.now();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);

    int missing = 0;
    for (final day in tradingDays) {
      final key = formatDate(day);
      if (!_completeDates.contains(key)) {
        missing++;
      }
    }
    return missing;
  }

  /// 获取缺失的日期列表
  List<String> getMissingDateKeys() {
    final today = DateTime.now();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);

    final missing = <String>[];
    for (final day in tradingDays) {
      final key = formatDate(day);
      if (!_completeDates.contains(key)) {
        missing.add(key);
      }
    }
    return missing;
  }
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "feat: add getMissingDays to HistoricalKlineService"
```

---

## Task 4: Add Persistence (Load/Save)

**Files:**
- Modify: `lib/services/historical_kline_service.dart`
- Modify: `test/services/historical_kline_service_test.dart`

**Step 1: Write the failing test**

```dart
// Add to test file
group('persistence', () {
  test('serializes and deserializes correctly', () {
    final service = HistoricalKlineService();
    final date = DateTime(2025, 1, 24, 9, 30);
    final bars = _generateBars(date, 5, 3);

    service.setStockBars('000001', bars);
    service.addCompleteDate('2025-01-24');

    final json = service.serializeCache();

    expect(json['version'], 1);
    expect(json['completeDates'], contains('2025-01-24'));
    expect(json['stocks']['000001'], isNotEmpty);

    // Create new service and deserialize
    final service2 = HistoricalKlineService();
    service2.deserializeCache(json);

    expect(service2.completeDates, contains('2025-01-24'));
    expect(service2.getDailyVolumes('000001'), isNotEmpty);
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
// Add to lib/services/historical_kline_service.dart

  /// 序列化缓存数据
  Map<String, dynamic> serializeCache() {
    final stocks = <String, dynamic>{};
    for (final entry in _stockBars.entries) {
      stocks[entry.key] = entry.value.map((bar) => bar.toJson()).toList();
    }

    return {
      'version': 1,
      'lastFetchTime': _lastFetchTime?.toIso8601String(),
      'completeDates': _completeDates.toList(),
      'stocks': stocks,
    };
  }

  /// 反序列化缓存数据
  void deserializeCache(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    if (version != 1) return;

    final lastFetchStr = json['lastFetchTime'] as String?;
    _lastFetchTime = lastFetchStr != null ? DateTime.parse(lastFetchStr) : null;

    final dates = json['completeDates'] as List<dynamic>?;
    _completeDates = dates?.map((e) => e as String).toSet() ?? {};

    final stocks = json['stocks'] as Map<String, dynamic>?;
    if (stocks != null) {
      _stockBars = {};
      for (final entry in stocks.entries) {
        final barsList = entry.value as List<dynamic>;
        _stockBars[entry.key] = barsList
            .map((e) => KLine.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.datetime.compareTo(b.datetime));
      }
    }

    _cleanupOldData();
  }

  /// 清理超过30天的旧数据
  void _cleanupOldData() {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxCacheDays));
    final cutoffKey = formatDate(cutoff);

    // 清理过期日期
    _completeDates.removeWhere((key) => key.compareTo(cutoffKey) < 0);

    // 清理过期K线
    for (final entry in _stockBars.entries) {
      entry.value.removeWhere((bar) => formatDate(bar.datetime).compareTo(cutoffKey) < 0);
    }
    _stockBars.removeWhere((_, bars) => bars.isEmpty);
  }

  /// 从本地缓存加载
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        deserializeCache(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load historical kline cache: $e');
    }
  }

  /// 保存到本地缓存
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(serializeCache()));
    } catch (e) {
      debugPrint('Failed to save historical kline cache: $e');
    }
  }

  /// 清空缓存
  Future<void> clear() async {
    _stockBars = {};
    _completeDates = {};
    _lastFetchTime = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('Failed to clear historical kline cache: $e');
    }
  }
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "feat: add persistence to HistoricalKlineService"
```

---

## Task 5: Add Data Fetching Logic

**Files:**
- Modify: `lib/services/historical_kline_service.dart`

**Step 1: Add import and implement fetchMissingDays**

```dart
// Add to lib/services/historical_kline_service.dart
import 'package:stock_rtwatcher/services/tdx_client.dart';

  /// 增量拉取缺失的日期
  /// 返回本次拉取的天数
  Future<int> fetchMissingDays(
    TdxPool pool,
    List<Stock> stocks,
    void Function(int current, int total)? onProgress,
  ) async {
    if (stocks.isEmpty || _isLoading) return 0;

    final missingDates = getMissingDateKeys();
    if (missingDates.isEmpty) return 0;

    _isLoading = true;
    notifyListeners();

    try {
      final connected = await pool.ensureConnected();
      if (!connected) throw Exception('无法连接到服务器');

      // 计算需要拉取的页数
      // 每页800条，每天约240条，每页约3.3天
      // 为安全起见，每缺3天拉1页
      final pagesToFetch = (missingDates.length / 3).ceil().clamp(1, 6);
      const int barsPerPage = 800;

      final stockList = stocks;
      final fetchTotal = stockList.length * pagesToFetch;
      final grandTotal = fetchTotal + stockList.length; // 拉取 + 处理

      // 收集所有K线数据
      final allBars = List<List<KLine>>.generate(stockList.length, (_) => []);

      for (var page = 0; page < pagesToFetch; page++) {
        final start = page * barsPerPage;
        final pageBars = await pool.batchGetSecurityBars(
          stocks: stockList,
          category: klineType1Min,
          start: start,
          count: barsPerPage,
          onProgress: (current, total) {
            final completed = page * stockList.length + current;
            onProgress?.call(completed, grandTotal);
          },
        );

        for (var i = 0; i < pageBars.length; i++) {
          if (pageBars[i].isNotEmpty) {
            allBars[i].addAll(pageBars[i]);
          }
        }
      }

      // 合并到现有数据
      final today = DateTime.now();
      final todayKey = formatDate(today);
      final newDates = <String>{};

      for (var i = 0; i < stockList.length; i++) {
        final stockCode = stockList[i].code;
        final bars = allBars[i];
        if (bars.isEmpty) continue;

        // 合并K线（去重）
        final existing = _stockBars[stockCode] ?? [];
        final existingTimes = existing.map((b) => b.datetime.millisecondsSinceEpoch).toSet();

        final newBars = bars.where((b) {
          // 跳过今天的数据
          if (formatDate(b.datetime) == todayKey) return false;
          return !existingTimes.contains(b.datetime.millisecondsSinceEpoch);
        }).toList();

        if (newBars.isNotEmpty) {
          existing.addAll(newBars);
          existing.sort((a, b) => a.datetime.compareTo(b.datetime));
          _stockBars[stockCode] = existing;

          // 记录新增的日期
          for (final bar in newBars) {
            newDates.add(formatDate(bar.datetime));
          }
        }

        onProgress?.call(fetchTotal + i + 1, grandTotal);
      }

      // 更新已完成日期
      // 只有当某个日期有足够多股票的数据时才标记为完成
      final dateCounts = <String, int>{};
      for (final dateKey in newDates) {
        dateCounts[dateKey] = (dateCounts[dateKey] ?? 0) + 1;
      }
      for (final entry in dateCounts.entries) {
        // 至少10%的股票有数据才认为该日期完整
        if (entry.value > stockList.length * 0.1) {
          _completeDates.add(entry.key);
        }
      }

      _lastFetchTime = DateTime.now();
      _cleanupOldData();
      await save();

      return newDates.length;
    } catch (e) {
      debugPrint('Failed to fetch historical kline data: $e');
      return 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 获取数据覆盖范围
  ({String? earliest, String? latest}) getDateRange() {
    if (_completeDates.isEmpty) return (earliest: null, latest: null);
    final sorted = _completeDates.toList()..sort();
    return (earliest: sorted.first, latest: sorted.last);
  }

  /// 获取缓存大小（估算字节数）
  int getCacheSize() {
    int count = 0;
    for (final bars in _stockBars.values) {
      count += bars.length;
    }
    // 每条K线约80字节
    return count * 80;
  }

  /// 格式化缓存大小
  String get cacheSizeFormatted {
    final bytes = getCacheSize();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
```

**Step 2: Run existing tests**

Run: `flutter test test/services/historical_kline_service_test.dart`
Expected: PASS

**Step 3: Commit**

```bash
git add lib/services/historical_kline_service.dart
git commit -m "feat: add fetchMissingDays to HistoricalKlineService"
```

---

## Task 6: Register HistoricalKlineService in Provider

**Files:**
- Modify: `lib/main.dart`

**Step 1: Add import and register provider**

```dart
// In lib/main.dart, add import
import 'package:stock_rtwatcher/services/historical_kline_service.dart';

// Add ChangeNotifierProvider after IndustryRankService registration (around line 70)
        ChangeNotifierProvider(create: (_) {
          final service = HistoricalKlineService();
          service.load();
          return service;
        }),
```

**Step 2: Verify app builds**

Run: `flutter build ios --debug --no-codesign` or `flutter build apk --debug`
Expected: BUILD SUCCESSFUL

**Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register HistoricalKlineService in Provider"
```

---

## Task 7: Add Historical Kline to DataManagementScreen

**Files:**
- Modify: `lib/screens/data_management_screen.dart`

**Step 1: Add import and inject service**

```dart
// Add import at top
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
```

**Step 2: Add UI for historical kline cache**

After the existing cache items (around line 42), add:

```dart
              // 历史分钟K线
              Consumer<HistoricalKlineService>(
                builder: (context, klineService, _) {
                  final range = klineService.getDateRange();
                  final missingDays = klineService.getMissingDays();
                  final subtitle = range.earliest != null
                      ? '${range.earliest} ~ ${range.latest}，缺失 $missingDays 天'
                      : '暂无数据';

                  return _buildKlineCacheItem(
                    context,
                    title: '历史分钟K线',
                    subtitle: subtitle,
                    size: klineService.cacheSizeFormatted,
                    missingDays: missingDays,
                    isLoading: klineService.isLoading,
                    onFetch: () => _fetchHistoricalKline(context),
                    onClear: () => _confirmClear(context, '历史分钟K线', () async {
                      await klineService.clear();
                      // 同时清空依赖的服务缓存
                      if (context.mounted) {
                        context.read<IndustryTrendService>().clearCache();
                        context.read<IndustryRankService>().clearCache();
                      }
                    }),
                  );
                },
              ),
```

**Step 3: Add the fetch method and UI widget**

```dart
  Widget _buildKlineCacheItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String size,
    required int missingDays,
    required bool isLoading,
    required VoidCallback onFetch,
    required VoidCallback onClear,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(size),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (missingDays > 0)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isLoading ? null : onFetch,
                      icon: isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download, size: 18),
                      label: Text(isLoading ? '拉取中...' : '拉取缺失'),
                    ),
                  ),
                if (missingDays > 0) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClear,
                    child: const Text('清空'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fetchHistoricalKline(BuildContext context) async {
    final klineService = context.read<HistoricalKlineService>();
    final marketProvider = context.read<MarketDataProvider>();
    final pool = context.read<TdxPool>();
    final trendService = context.read<IndustryTrendService>();
    final rankService = context.read<IndustryRankService>();

    if (marketProvider.allData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先刷新市场数据')),
      );
      return;
    }

    final stocks = marketProvider.allData.map((d) => d.stock).toList();
    await klineService.fetchMissingDays(pool, stocks, null);

    // 拉取完成后，触发重算
    if (context.mounted) {
      await trendService.recalculateFromKlineData(klineService, marketProvider.allData);
      await rankService.recalculateFromKlineData(klineService, marketProvider.allData);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('历史数据已更新')),
      );
    }
  }
```

**Step 4: Verify the screen builds**

Run: `flutter run`
Navigate to Data Management screen, verify the new item appears.

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart
git commit -m "feat: add historical kline management to DataManagementScreen"
```

---

## Task 8: Add recalculateFromKlineData to IndustryTrendService

**Files:**
- Modify: `lib/services/industry_trend_service.dart`

**Step 1: Add import**

```dart
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
```

**Step 2: Add recalculate method and clearCache**

```dart
  /// 清空趋势缓存
  void clearCache() {
    _trendData = {};
    _missingDays = 0;
    notifyListeners();
  }

  /// 从历史K线数据重新计算趋势
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks,
  ) async {
    if (stocks.isEmpty) return;

    // 按行业分组股票
    final industryStocks = <String, List<StockMonitorData>>{};
    for (final stock in stocks) {
      final industry = stock.industry;
      if (industry != null && industry.isNotEmpty) {
        industryStocks.putIfAbsent(industry, () => []).add(stock);
      }
    }

    // 收集所有日期
    final allDates = <String>{};
    for (final stock in stocks) {
      final volumes = klineService.getDailyVolumes(stock.stock.code);
      allDates.addAll(volumes.keys);
    }

    // 计算每个行业每天的趋势
    final newTrendData = <String, IndustryTrendData>{};

    for (final entry in industryStocks.entries) {
      final industry = entry.key;
      final industryStockList = entry.value;
      final points = <DailyRatioPoint>[];

      for (final dateKey in allDates) {
        var ratioAboveCount = 0;
        var totalStocks = 0;

        for (final stock in industryStockList) {
          final volumes = klineService.getDailyVolumes(stock.stock.code);
          final vol = volumes[dateKey];
          if (vol == null) continue;
          if (vol.down <= 0) continue;

          totalStocks++;
          final ratio = vol.up / vol.down;
          if (ratio > 1.0 && ratio <= StockService.maxValidRatio) {
            ratioAboveCount++;
          }
        }

        if (totalStocks > 0) {
          final ratioAbovePercent = (ratioAboveCount / totalStocks) * 100;
          points.add(DailyRatioPoint(
            date: HistoricalKlineService.parseDate(dateKey),
            ratioAbovePercent: ratioAbovePercent,
            totalStocks: totalStocks,
            ratioAboveCount: ratioAboveCount,
          ));
        }
      }

      if (points.isNotEmpty) {
        points.sort((a, b) => a.date.compareTo(b.date));
        newTrendData[industry] = IndustryTrendData(
          industry: industry,
          points: points,
        );
      }
    }

    _trendData = newTrendData;
    _missingDays = 0;
    await _save();
    notifyListeners();
  }
```

**Step 3: Remove fetchHistoricalData method**

Delete the entire `fetchHistoricalData` method (approximately lines 127-301 in the original file).

**Step 4: Verify tests pass**

Run: `flutter test`
Expected: PASS (or adjust tests if any reference removed methods)

**Step 5: Commit**

```bash
git add lib/services/industry_trend_service.dart
git commit -m "refactor: replace fetchHistoricalData with recalculateFromKlineData in IndustryTrendService"
```

---

## Task 9: Add recalculateFromKlineData to IndustryRankService

**Files:**
- Modify: `lib/services/industry_rank_service.dart`

**Step 1: Add import**

```dart
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
```

**Step 2: Add recalculate method and clearCache**

```dart
  /// 清空排名缓存
  void clearCache() {
    _historyData = {};
    _todayRanks = {};
    notifyListeners();
  }

  /// 从历史K线数据重新计算排名
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks,
  ) async {
    if (stocks.isEmpty) return;

    // 收集所有日期
    final allDates = <String>{};
    for (final stock in stocks) {
      final volumes = klineService.getDailyVolumes(stock.stock.code);
      allDates.addAll(volumes.keys);
    }

    // 计算每个日期的行业排名
    final newHistory = <String, Map<String, IndustryRankRecord>>{};

    for (final dateKey in allDates) {
      // 按行业汇总涨跌量
      final industryVolumes = <String, ({double up, double down})>{};

      for (final stock in stocks) {
        final industry = stock.industry;
        if (industry == null || industry.isEmpty) continue;

        final volumes = klineService.getDailyVolumes(stock.stock.code);
        final vol = volumes[dateKey];
        if (vol == null) continue;
        if (vol.up <= 0 && vol.down <= 0) continue;

        final current = industryVolumes[industry];
        industryVolumes[industry] = (
          up: (current?.up ?? 0) + vol.up,
          down: (current?.down ?? 0) + vol.down,
        );
      }

      // 计算聚合量比并排名
      final industryRatios = <String, double>{};
      for (final entry in industryVolumes.entries) {
        if (entry.value.down > 0) {
          final ratio = entry.value.up / entry.value.down;
          if (ratio <= StockService.maxValidRatio &&
              ratio >= 1 / StockService.maxValidRatio) {
            industryRatios[entry.key] = ratio;
          }
        }
      }

      final sorted = industryRatios.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final dayRanks = <String, IndustryRankRecord>{};
      for (var i = 0; i < sorted.length; i++) {
        dayRanks[sorted[i].key] = IndustryRankRecord(
          date: dateKey,
          ratio: sorted[i].value,
          rank: i + 1,
        );
      }

      if (dayRanks.isNotEmpty) {
        newHistory[dateKey] = dayRanks;
      }
    }

    _historyData = newHistory;
    _cleanupOldData();
    await _save();
    notifyListeners();
  }
```

**Step 3: Remove fetchHistoricalData method**

Delete the entire `fetchHistoricalData` method (approximately lines 187-351 in the original file).

**Step 4: Verify tests pass**

Run: `flutter test`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/industry_rank_service.dart
git commit -m "refactor: replace fetchHistoricalData with recalculateFromKlineData in IndustryRankService"
```

---

## Task 10: Update IndustryScreen - Remove Fetch Logic

**Files:**
- Modify: `lib/screens/industry_screen.dart`

**Step 1: Add import**

```dart
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
```

**Step 2: Remove fetch methods and progress dialog**

Delete these methods:
- `_fetchTrendData` (lines ~159-200)
- `_fetchRankData` (lines ~202-252)
- `_ProgressDialog` class (lines ~752-806)

Also remove the `_fetchProgress` and `_fetchTotal` state variables.

**Step 3: Add data staleness banner**

Add a method and update the build:

```dart
  Widget _buildStaleDataBanner(BuildContext context, HistoricalKlineService klineService) {
    final missingDays = klineService.getMissingDays();
    if (missingDays == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '历史数据缺失 $missingDays 天，部分趋势可能不准确',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DataManagementScreen(),
                ),
              );
            },
            child: const Text('前往更新'),
          ),
        ],
      ),
    );
  }
```

**Step 4: Update build method**

In the `build` method, add `HistoricalKlineService` watcher and insert the banner:

```dart
  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();
    final rankService = context.watch<IndustryRankService>();
    final klineService = context.watch<HistoricalKlineService>(); // Add this

    // ... existing code ...

    return Scaffold(
      appBar: AppBar(
        // ... existing app bar ...
      ),
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            _buildStaleDataBanner(context, klineService), // Add this
            // ... rest of the body ...
          ],
        ),
      ),
    );
  }
```

**Step 5: Update IndustryRankList onFetchData**

Change the `IndustryRankList` from passing `onFetchData: _fetchRankData` to just navigation:

```dart
                  IndustryRankList(
                    fullHeight: true,
                    onFetchData: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DataManagementScreen(),
                        ),
                      );
                    },
                  ),
```

**Step 6: Verify the screen works**

Run: `flutter run`
Navigate to Industry screen, verify banner appears when data is missing.

**Step 7: Commit**

```bash
git add lib/screens/industry_screen.dart
git commit -m "refactor: remove fetch logic from IndustryScreen, add stale data banner"
```

---

## Task 11: Update IndustryRankList Empty State

**Files:**
- Modify: `lib/widgets/industry_rank_list.dart`

**Step 1: Update empty state message**

Change the empty state to guide users to data management:

```dart
      if (histories.isEmpty && !rankService.isLoading) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.trending_up_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无排名数据',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '请先在数据管理页面拉取历史K线数据',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (onFetchData != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onFetchData,
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('前往数据管理'),
                ),
              ],
            ],
          ),
        );
      }
```

**Step 2: Commit**

```bash
git add lib/widgets/industry_rank_list.dart
git commit -m "refactor: update IndustryRankList empty state to guide to data management"
```

---

## Task 12: Final Integration Test and Cleanup

**Files:**
- Multiple files for cleanup

**Step 1: Run all tests**

Run: `flutter test`
Expected: All tests PASS

**Step 2: Build and test manually**

Run: `flutter run`

Test flow:
1. Open app, go to Data Management
2. Verify "历史分钟K线" item shows with missing days
3. Click "拉取缺失" - verify progress
4. After fetch completes, go to Industry tab
5. Verify both tabs show data, banner is gone or shows 0 missing
6. Clear cache, verify banner returns

**Step 3: Remove unused imports and dead code**

Check for any unused imports in modified files:
- `lib/services/industry_trend_service.dart` - remove `tdx_client.dart` if no longer needed
- `lib/services/industry_rank_service.dart` - remove `tdx_client.dart` if no longer needed

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: cleanup unused imports and code after historical kline consolidation"
```

---

## Summary

This plan consolidates minute K-line data fetching into a single `HistoricalKlineService`:

1. **Tasks 1-5**: Build `HistoricalKlineService` with TDD
2. **Task 6**: Register in Provider
3. **Task 7**: Add UI in DataManagementScreen
4. **Tasks 8-9**: Refactor trend/rank services to use shared data
5. **Tasks 10-11**: Update IndustryScreen and widgets
6. **Task 12**: Final testing and cleanup

Each task is small (~5-10 minutes) and produces a working, testable increment.
