# Phase 3: HistoricalKlineService Migration to DataRepository

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate HistoricalKlineService from direct TdxPool access to using DataRepository as the single source of truth for K-line data.

**Architecture:** HistoricalKlineService becomes a thin read-only accessor that reads K-line data from DataRepository and caches computed results (like volume aggregations). All fetching is triggered from the UI layer via DataRepository directly. The service listens to DataRepository.dataUpdatedStream to invalidate its computed caches.

**Tech Stack:**
- Dart/Flutter
- DataRepository (Phase 2 implementation)
- ChangeNotifier for reactive updates

---

## Task 1: Add DataRepository Dependency to HistoricalKlineService

**Files:**
- Modify: `lib/services/historical_kline_service.dart`
- Modify: `lib/main.dart`

**Step 1: Write the failing test**

Create test in `test/services/historical_kline_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';

// Mock DataRepository for testing
class MockDataRepository implements DataRepository {
  // Minimal mock implementation - will be expanded in later tasks
}

void main() {
  group('HistoricalKlineService with DataRepository', () {
    test('should accept DataRepository in constructor', () {
      final mockRepo = MockDataRepository();
      final service = HistoricalKlineService(repository: mockRepo);
      expect(service, isNotNull);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/historical_kline_service_test.dart --no-pub`

Expected: FAIL - constructor doesn't accept repository parameter yet

**Step 3: Modify HistoricalKlineService constructor**

In `lib/services/historical_kline_service.dart`, add:

```dart
import '../data/repository/data_repository.dart';

class HistoricalKlineService extends ChangeNotifier {
  final DataRepository _repository;

  // Cache for computed results (version-tracked)
  int _cacheVersion = -1;
  Map<String, Map<String, ({double up, double down})>> _dailyVolumesCache = {};

  HistoricalKlineService({required DataRepository repository})
      : _repository = repository {
    // Listen to data updates to invalidate cache
    _repository.dataUpdatedStream.listen((_) {
      _invalidateCache();
    });
  }

  void _invalidateCache() {
    _dailyVolumesCache.clear();
    _cacheVersion = -1;
    notifyListeners();
  }

  // ... existing code (will be modified in later tasks)
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/historical_kline_service_test.dart --no-pub`

Expected: PASS

**Step 5: Update main.dart to pass DataRepository**

In `lib/main.dart`, update the provider setup:

```dart
// Find the existing HistoricalKlineService creation and update:
ChangeNotifierProvider(create: (context) {
  final repository = context.read<DataRepository>();
  final service = HistoricalKlineService(repository: repository);
  return service;
}),
```

Note: DataRepository provider must be created before HistoricalKlineService.

**Step 6: Commit**

```bash
git add lib/services/historical_kline_service.dart lib/main.dart test/services/historical_kline_service_test.dart
git commit -m "refactor(data): add DataRepository dependency to HistoricalKlineService

- Accept DataRepository in constructor
- Add cache invalidation on data updates
- Update provider setup in main.dart

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Refactor getDailyVolumes to Use DataRepository

**Files:**
- Modify: `lib/services/historical_kline_service.dart`
- Modify: `test/services/historical_kline_service_test.dart`

**Step 1: Write the failing test**

Add to test file:

```dart
test('getDailyVolumes should return cached computed volumes', () async {
  final mockRepo = MockDataRepository();
  // Setup mock to return test K-lines
  mockRepo.setMockKlines('000001', [
    KLine(
      datetime: DateTime(2024, 1, 15, 9, 30),
      open: 10.0, close: 10.5, high: 10.8, low: 9.9,
      volume: 1000, amount: 10000,
    ),
    KLine(
      datetime: DateTime(2024, 1, 15, 9, 31),
      open: 10.5, close: 10.3, high: 10.6, low: 10.2,
      volume: 800, amount: 8200,
    ),
  ]);

  final service = HistoricalKlineService(repository: mockRepo);

  final volumes = await service.getDailyVolumes('000001');

  expect(volumes['2024-01-15'], isNotNull);
  expect(volumes['2024-01-15']!.up, equals(1000)); // First bar is up
  expect(volumes['2024-01-15']!.down, equals(800)); // Second bar is down
});

test('getDailyVolumes should use cache on second call', () async {
  final mockRepo = MockDataRepository();
  mockRepo.setMockKlines('000001', [/* test data */]);

  final service = HistoricalKlineService(repository: mockRepo);

  // First call
  await service.getDailyVolumes('000001');
  final callCount1 = mockRepo.getKlinesCallCount;

  // Second call should use cache
  await service.getDailyVolumes('000001');
  final callCount2 = mockRepo.getKlinesCallCount;

  expect(callCount2, equals(callCount1)); // No additional calls
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/historical_kline_service_test.dart --no-pub`

Expected: FAIL - method signature changed (now async)

**Step 3: Implement getDailyVolumes with DataRepository**

Replace the existing `getDailyVolumes` method:

```dart
/// 获取某只股票所有日期的涨跌量汇总（带缓存）
/// 返回 { dateKey: (up: upVolume, down: downVolume) }
Future<Map<String, ({double up, double down})>> getDailyVolumes(String stockCode) async {
  // Check cache validity
  final repoVersion = await _repository.getCurrentVersion();
  if (repoVersion != _cacheVersion) {
    _dailyVolumesCache.clear();
    _cacheVersion = repoVersion;
  }

  // Return cached if available
  if (_dailyVolumesCache.containsKey(stockCode)) {
    return _dailyVolumesCache[stockCode]!;
  }

  // Compute from DataRepository
  final klines = await _repository.getKlines(
    stockCodes: [stockCode],
    dateRange: DateRange(
      DateTime.now().subtract(const Duration(days: 30)),
      DateTime.now(),
    ),
    dataType: KLineDataType.oneMinute,
  );

  final bars = klines[stockCode] ?? [];
  final result = _computeDailyVolumes(bars);

  // Cache result
  _dailyVolumesCache[stockCode] = result;
  return result;
}

/// 计算每日涨跌量（纯计算，无IO）
Map<String, ({double up, double down})> _computeDailyVolumes(List<KLine> bars) {
  if (bars.isEmpty) return {};

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

Run: `flutter test test/services/historical_kline_service_test.dart --no-pub`

Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "refactor(data): getDailyVolumes uses DataRepository with caching

- Fetch K-lines from DataRepository instead of internal _stockBars
- Cache computed volumes with version tracking
- Invalidate cache when repository data version changes

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Update Callers of getDailyVolumes (Make Async)

**Files:**
- Modify: `lib/services/industry_trend_service.dart`
- Modify: `lib/services/industry_rank_service.dart`

**Step 1: Identify call sites**

In `industry_trend_service.dart` line ~138:
```dart
final volumes = klineService.getDailyVolumes(stock.stock.code);
```

In `industry_rank_service.dart` line ~296:
```dart
final volumes = klineService.getDailyVolumes(stock.stock.code);
```

**Step 2: Update IndustryTrendService**

Change synchronous calls to async:

```dart
// Before:
final volumes = klineService.getDailyVolumes(stock.stock.code);

// After:
final volumes = await klineService.getDailyVolumes(stock.stock.code);
```

Ensure the containing method is async.

**Step 3: Update IndustryRankService**

Same pattern - add await to getDailyVolumes calls.

**Step 4: Run tests**

Run: `flutter test --no-pub`

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/services/industry_trend_service.dart lib/services/industry_rank_service.dart
git commit -m "refactor(data): update getDailyVolumes callers to async

- IndustryTrendService: await getDailyVolumes calls
- IndustryRankService: await getDailyVolumes calls

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Refactor getMissingDays to Use DataRepository.checkFreshness

**Files:**
- Modify: `lib/services/historical_kline_service.dart`
- Modify: `test/services/historical_kline_service_test.dart`

**Step 1: Write the failing test**

```dart
test('getMissingDays should delegate to DataRepository.checkFreshness', () async {
  final mockRepo = MockDataRepository();
  // Mock returns Stale for stock, indicating missing data
  mockRepo.setFreshnessResult('000001', Stale(missingRange: DateRange(...)));

  final service = HistoricalKlineService(repository: mockRepo);

  final missing = await service.getMissingDays(['000001']);

  expect(missing, greaterThan(0));
});
```

**Step 2: Implement getMissingDays with DataRepository**

```dart
/// 获取缺失天数（基于 DataRepository.checkFreshness）
Future<int> getMissingDays(List<String> stockCodes) async {
  if (stockCodes.isEmpty) return 0;

  final freshness = await _repository.checkFreshness(
    stockCodes: stockCodes,
    dataType: KLineDataType.oneMinute,
  );

  int missingCount = 0;
  for (final entry in freshness.entries) {
    if (entry.value is Missing) {
      missingCount++; // Entire stock is missing
    } else if (entry.value is Stale) {
      final stale = entry.value as Stale;
      missingCount += stale.missingRange.duration.inDays;
    }
  }

  return missingCount;
}
```

**Step 3: Run test**

Run: `flutter test test/services/historical_kline_service_test.dart --no-pub`

Expected: PASS

**Step 4: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "refactor(data): getMissingDays delegates to DataRepository.checkFreshness

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Remove fetchMissingDays and Update UI Caller

**Files:**
- Modify: `lib/services/historical_kline_service.dart`
- Modify: `lib/screens/data_management_screen.dart`

**Step 1: Delete fetchMissingDays from HistoricalKlineService**

Remove the entire `fetchMissingDays` method (lines 545-705 approximately).

**Step 2: Update data_management_screen.dart**

Replace the call to `klineService.fetchMissingDays()` with `DataRepository.fetchMissingData()`:

```dart
// Before (line 267):
await klineService.fetchMissingDays(pool, stocks, (current, total, stage) {...});

// After:
final repository = context.read<DataRepository>();
final stockCodes = stocks.map((s) => s.code).toList();
final dateRange = DateRange(
  DateTime.now().subtract(const Duration(days: 30)),
  DateTime.now(),
);

await repository.fetchMissingData(
  stockCodes: stockCodes,
  dateRange: dateRange,
  dataType: KLineDataType.oneMinute,
  onProgress: (current, total) {
    progressNotifier.value = (
      current: current,
      total: total,
      stage: '1/3 拉取K线数据',
    );
  },
);
```

**Step 3: Verify the app builds**

Run: `flutter build apk --debug`

Expected: Build succeeds

**Step 4: Commit**

```bash
git add lib/services/historical_kline_service.dart lib/screens/data_management_screen.dart
git commit -m "refactor(data): remove fetchMissingDays, UI uses DataRepository directly

- Delete fetchMissingDays method from HistoricalKlineService
- Update DataManagementScreen to call DataRepository.fetchMissingData
- Fetching is now handled at the data layer

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Remove Legacy Storage Code

**Files:**
- Modify: `lib/services/historical_kline_service.dart`

**Step 1: Remove legacy fields and methods**

Delete the following from HistoricalKlineService:

**Fields to remove:**
- `_stockBars` (Map<String, List<KLine>>)
- `_completeDates` (Set<String>)
- `_lastFetchTime` (DateTime?)
- `_dataVersion` (int)
- `_stockCount` (int)
- `_klineDataLoaded` (bool)
- `_isLoading` (bool)
- File path constants (`_storageKey`, `_fileName`, etc.)

**Methods to remove:**
- `_getCacheFile()`, `_getMetaFile()`, `_getOldCacheFile()`
- `serializeMetadata()`, `serializeKlineData()`, `serializeCache()`
- `deserializeMetadata()`, `deserializeKlineData()`, `deserializeCache()`
- `load()`, `loadKlineData()`, `save()`, `clear()`
- `_migrateFromOldFormat()`, `_cleanupOldData()`
- `setStockBars()` (test helper)
- `addCompleteDate()` (test helper)

**Getters to update:**
- `stockCount` -> delegate to DataRepository
- `dataVersion` -> delegate to DataRepository
- Remove `klineDataLoaded`, `isLoading`, `lastFetchTime`, `completeDates`

**Step 2: Keep utility methods**

Keep these static utility methods:
- `formatDate(DateTime)`
- `parseDate(String)`

**Step 3: Verify tests still pass**

Run: `flutter test --no-pub`

Fix any test failures by updating tests to use mocked DataRepository.

**Step 4: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "refactor(data): remove legacy storage code from HistoricalKlineService

- Remove _stockBars, file storage, serialization methods
- Service is now a thin wrapper over DataRepository
- Computed results (volumes) still cached locally

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Update Remaining UI References

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `lib/screens/industry_screen.dart` (if needed)

**Step 1: Remove references to deleted properties**

In `data_management_screen.dart`, update any references to:
- `klineService.klineDataLoaded` -> remove or replace with DataRepository status
- `klineService.loadKlineData()` -> remove (DataRepository loads on demand)

**Step 2: Update industry_screen.dart if needed**

Check for any references to removed HistoricalKlineService properties.

**Step 3: Verify app runs**

Run: `flutter run`

Test the data management screen manually.

**Step 4: Commit**

```bash
git add lib/screens/data_management_screen.dart lib/screens/industry_screen.dart
git commit -m "refactor(ui): update screens for new HistoricalKlineService API

- Remove references to deleted properties
- DataRepository handles data loading

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Add DataRepository Provider to main.dart

**Files:**
- Modify: `lib/main.dart`

**Step 1: Create DataRepository provider**

Add DataRepository to the MultiProvider in main.dart, ensuring it's created before HistoricalKlineService:

```dart
MultiProvider(
  providers: [
    // ... existing providers ...

    // DataRepository must come before services that depend on it
    Provider<DataRepository>(
      create: (_) => MarketDataRepository(),
      dispose: (_, repo) => repo.dispose(),
    ),

    ChangeNotifierProvider(create: (context) {
      final repository = context.read<DataRepository>();
      return HistoricalKlineService(repository: repository);
    }),

    // ... other providers ...
  ],
)
```

**Step 2: Verify app starts**

Run: `flutter run`

Expected: App starts without errors

**Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(di): add DataRepository provider to main.dart

- Create MarketDataRepository as DataRepository provider
- Ensure proper dispose on app shutdown
- Update HistoricalKlineService to receive injected repository

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary

This plan migrates HistoricalKlineService from direct TdxPool access to using DataRepository:

**Tasks completed:**
1. Add DataRepository dependency injection
2. Refactor getDailyVolumes to use DataRepository with caching
3. Update callers (IndustryTrendService, IndustryRankService) to async
4. Refactor getMissingDays to use checkFreshness
5. Remove fetchMissingDays, update UI to use DataRepository directly
6. Remove legacy storage code (file handling, serialization)
7. Update remaining UI references
8. Add DataRepository provider to main.dart

**Result:**
- HistoricalKlineService is now a thin read-only accessor
- All K-line data flows through DataRepository
- Computed results (volumes) are cached with version tracking
- UI triggers fetching via DataRepository.fetchMissingData()

**What's next:** Phase 4 - StockService migration (optional) or Phase 5 - Presentation layer integration
