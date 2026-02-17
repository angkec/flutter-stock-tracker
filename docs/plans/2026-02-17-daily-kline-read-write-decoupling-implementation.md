# Daily K-Line Read/Write Decoupling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Decouple daily K-line sync from read paths so only Data Management explicit actions trigger network fetch, while all daily-K reads are file-cache-only and fail-fast on missing/corrupted cache.

**Architecture:** Introduce two dedicated services: `DailyKlineSyncService` (explicit sync only) and `DailyKlineReadService` (file read + strict validation only). Refactor `MarketDataProvider` into orchestration-only for daily-K workflows, update Data Management UI to provide two explicit daily sync actions (incremental/full), and enforce lightweight checkpoint-only persistence in SharedPreferences.

**Tech Stack:** Flutter/Dart, Provider, SharedPreferences (checkpoints only), file-based daily cache (`DailyKlineCacheStore`), flutter_test, integration_test.

---

## Execution Notes

- Recommended first step: create isolated worktree via `@superpowers:using-git-worktrees`.
- Execute each task with `@superpowers:test-driven-development` (fail -> minimal fix -> pass).
- If any test fails unexpectedly, use `@superpowers:systematic-debugging` before changing implementation.
- Before claiming completion, run `@superpowers:verification-before-completion`.
- Keep commits small and scoped: one commit per task.

### Task 1: Add Daily-K Read Service With Fail-Fast Validation

**Files:**
- Create: `lib/services/daily_kline_read_service.dart`
- Test: `test/services/daily_kline_read_service_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/daily_kline_read_service.dart';

void main() {
  DailyKlineCacheStore buildStore(String path) {
    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(path);
    return DailyKlineCacheStore(storage: storage);
  }

  List<KLine> bars(int count) {
    final start = DateTime(2026, 1, 1);
    return List.generate(count, (i) {
      final dt = start.add(Duration(days: i));
      return KLine(
        datetime: dt,
        open: 10,
        high: 10.5,
        low: 9.8,
        close: 10.2,
        volume: 1000,
        amount: 10000,
      );
    });
  }

  test('readOrThrow returns bars when all files are valid', () async {
    final dir = await Directory.systemTemp.createTemp('daily-read-ok-');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final store = buildStore(dir.path);
    await store.saveAll({'600000': bars(260)});

    final service = DailyKlineReadService(cacheStore: store);
    final result = await service.readOrThrow(
      stockCodes: const ['600000'],
      anchorDate: DateTime(2026, 12, 31),
      targetBars: 260,
    );

    expect(result['600000']?.length, 260);
  });

  test('readOrThrow throws missing_file when any stock cache missing', () async {
    final dir = await Directory.systemTemp.createTemp('daily-read-missing-');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final store = buildStore(dir.path);
    final service = DailyKlineReadService(cacheStore: store);

    expect(
      () => service.readOrThrow(
        stockCodes: const ['600000'],
        anchorDate: DateTime(2026, 12, 31),
        targetBars: 260,
      ),
      throwsA(
        isA<DailyKlineReadException>().having(
          (e) => e.reason,
          'reason',
          DailyKlineReadFailureReason.missingFile,
        ),
      ),
    );
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/daily_kline_read_service_test.dart -r expanded`  
Expected: FAIL with missing `DailyKlineReadService` / `DailyKlineReadException`.

**Step 3: Write minimal implementation**

```dart
// lib/services/daily_kline_read_service.dart
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';

enum DailyKlineReadFailureReason {
  missingFile,
  corruptedPayload,
  invalidOrder,
  insufficientBars,
}

class DailyKlineReadException implements Exception {
  const DailyKlineReadException({
    required this.stockCode,
    required this.reason,
    required this.message,
  });

  final String stockCode;
  final DailyKlineReadFailureReason reason;
  final String message;

  @override
  String toString() =>
      'DailyKlineReadException(stock=$stockCode, reason=$reason, message=$message)';
}

class DailyKlineReadService {
  DailyKlineReadService({required DailyKlineCacheStore cacheStore})
    : _cacheStore = cacheStore;

  final DailyKlineCacheStore _cacheStore;

  Future<Map<String, List<KLine>>> readOrThrow({
    required List<String> stockCodes,
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    final loaded = await _cacheStore.loadForStocks(
      stockCodes,
      anchorDate: anchorDate,
      targetBars: targetBars,
    );

    for (final code in stockCodes) {
      final bars = loaded[code];
      if (bars == null || bars.isEmpty) {
        throw DailyKlineReadException(
          stockCode: code,
          reason: DailyKlineReadFailureReason.missingFile,
          message: 'Daily cache file missing or empty',
        );
      }
      if (bars.length < targetBars) {
        throw DailyKlineReadException(
          stockCode: code,
          reason: DailyKlineReadFailureReason.insufficientBars,
          message: 'Insufficient daily bars: ${bars.length} < $targetBars',
        );
      }
      for (var i = 1; i < bars.length; i++) {
        if (bars[i - 1].datetime.isAfter(bars[i].datetime)) {
          throw DailyKlineReadException(
            stockCode: code,
            reason: DailyKlineReadFailureReason.invalidOrder,
            message: 'Daily bars are not sorted by datetime',
          );
        }
      }
    }

    return loaded;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/daily_kline_read_service_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/services/daily_kline_read_service.dart test/services/daily_kline_read_service_test.dart
git commit -m "feat: add fail-fast daily kline read service"
```

### Task 2: Add Daily-K Checkpoint Store (SharedPreferences Lightweight Only)

**Files:**
- Create: `lib/data/storage/daily_kline_checkpoint_store.dart`
- Test: `test/data/storage/daily_kline_checkpoint_store_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';

void main() {
  test('writes and reads global checkpoint metadata', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DailyKlineCheckpointStore();

    await store.saveGlobal(
      dateKey: '2026-02-17',
      mode: DailyKlineSyncMode.incremental,
      successAtMs: 123456,
    );

    final checkpoint = await store.loadGlobal();
    expect(checkpoint?.dateKey, '2026-02-17');
    expect(checkpoint?.mode, DailyKlineSyncMode.incremental);
    expect(checkpoint?.successAtMs, 123456);
  });

  test('persists per-stock success timestamp map', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DailyKlineCheckpointStore();

    await store.savePerStockSuccessAtMs({'600000': 1000, '000001': 2000});
    final map = await store.loadPerStockSuccessAtMs();

    expect(map['600000'], 1000);
    expect(map['000001'], 2000);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/daily_kline_checkpoint_store_test.dart -r expanded`  
Expected: FAIL with missing checkpoint store/types.

**Step 3: Write minimal implementation**

```dart
// lib/data/storage/daily_kline_checkpoint_store.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum DailyKlineSyncMode { incremental, forceFull }

class DailyKlineGlobalCheckpoint {
  const DailyKlineGlobalCheckpoint({
    required this.dateKey,
    required this.mode,
    required this.successAtMs,
  });

  final String dateKey;
  final DailyKlineSyncMode mode;
  final int successAtMs;
}

class DailyKlineCheckpointStore {
  static const _lastDateKey = 'daily_kline_checkpoint_last_success_date';
  static const _lastModeKey = 'daily_kline_checkpoint_last_mode';
  static const _lastSuccessAtKey = 'daily_kline_checkpoint_last_success_at_ms';
  static const _perStockKey =
      'daily_kline_checkpoint_per_stock_last_success_at_ms';

  Future<void> saveGlobal({
    required String dateKey,
    required DailyKlineSyncMode mode,
    required int successAtMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDateKey, dateKey);
    await prefs.setString(_lastModeKey, mode.name);
    await prefs.setInt(_lastSuccessAtKey, successAtMs);
  }

  Future<DailyKlineGlobalCheckpoint?> loadGlobal() async {
    final prefs = await SharedPreferences.getInstance();
    final date = prefs.getString(_lastDateKey);
    final modeName = prefs.getString(_lastModeKey);
    final successAtMs = prefs.getInt(_lastSuccessAtKey);
    if (date == null || modeName == null || successAtMs == null) {
      return null;
    }
    final mode = DailyKlineSyncMode.values.firstWhere(
      (x) => x.name == modeName,
      orElse: () => DailyKlineSyncMode.incremental,
    );
    return DailyKlineGlobalCheckpoint(
      dateKey: date,
      mode: mode,
      successAtMs: successAtMs,
    );
  }

  Future<void> savePerStockSuccessAtMs(Map<String, int> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_perStockKey, jsonEncode(value));
  }

  Future<Map<String, int>> loadPerStockSuccessAtMs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_perStockKey);
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/daily_kline_checkpoint_store_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/storage/daily_kline_checkpoint_store.dart test/data/storage/daily_kline_checkpoint_store_test.dart
git commit -m "feat: add daily kline checkpoint store"
```

### Task 3: Add Daily-K Sync Service (Incremental + Full)

**Files:**
- Create: `lib/services/daily_kline_sync_service.dart`
- Test: `test/services/daily_kline_sync_service_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/daily_kline_sync_service.dart';

void main() {
  test('incremental sync fetches only stale stocks and returns partial failures', () async {
    final service = DailyKlineSyncService(
      checkpointStore: FakeCheckpointStore(
        perStock: {'600000': 1000, '000001': 1000},
      ),
      cacheStore: FakeDailyKlineCacheStore(),
      fetcher: ({required stocks, required count, required mode, required onProgress}) async {
        return {
          '600000': [fakeBar(DateTime(2026, 2, 17))],
          // 000001 intentionally missing to simulate failure
        };
      },
      nowProvider: () => DateTime(2026, 2, 17, 10),
    );

    final result = await service.sync(
      mode: DailyKlineSyncMode.incremental,
      stocks: const [
        Stock(code: '600000', name: 'A', market: 1),
        Stock(code: '000001', name: 'B', market: 0),
      ],
      targetBars: 260,
    );

    expect(result.successStockCodes, contains('600000'));
    expect(result.failureStockCodes, contains('000001'));
  });

  test('forceFull sync ignores checkpoints and targets all stocks', () async {
    final fakeFetcher = RecordingFetcher();
    final service = DailyKlineSyncService(
      checkpointStore: FakeCheckpointStore(perStock: {'600000': 1}),
      cacheStore: FakeDailyKlineCacheStore(),
      fetcher: fakeFetcher.call,
      nowProvider: () => DateTime(2026, 2, 17, 10),
    );

    await service.sync(
      mode: DailyKlineSyncMode.forceFull,
      stocks: const [Stock(code: '600000', name: 'A', market: 1)],
      targetBars: 260,
    );

    expect(fakeFetcher.lastMode, DailyKlineSyncMode.forceFull);
    expect(fakeFetcher.lastRequestedCodes, ['600000']);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/daily_kline_sync_service_test.dart -r expanded`  
Expected: FAIL with missing sync service / result model.

**Step 3: Write minimal implementation**

```dart
// lib/services/daily_kline_sync_service.dart
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';

typedef DailyKlineFetcher = Future<Map<String, List<KLine>>> Function({
  required List<Stock> stocks,
  required int count,
  required DailyKlineSyncMode mode,
  void Function(int current, int total)? onProgress,
});

class DailyKlineSyncResult {
  const DailyKlineSyncResult({
    required this.successStockCodes,
    required this.failureStockCodes,
    required this.failureReasons,
  });

  final List<String> successStockCodes;
  final List<String> failureStockCodes;
  final Map<String, String> failureReasons;
}

class DailyKlineSyncService {
  DailyKlineSyncService({
    required DailyKlineCheckpointStore checkpointStore,
    required DailyKlineCacheStore cacheStore,
    required DailyKlineFetcher fetcher,
    DateTime Function()? nowProvider,
  }) : _checkpointStore = checkpointStore,
       _cacheStore = cacheStore,
       _fetcher = fetcher,
       _nowProvider = nowProvider ?? DateTime.now;

  final DailyKlineCheckpointStore _checkpointStore;
  final DailyKlineCacheStore _cacheStore;
  final DailyKlineFetcher _fetcher;
  final DateTime Function() _nowProvider;

  Future<DailyKlineSyncResult> sync({
    required DailyKlineSyncMode mode,
    required List<Stock> stocks,
    required int targetBars,
    void Function(String stage, int current, int total)? onProgress,
  }) async {
    final targetStocks = stocks; // minimal: incremental/full both use provided stocks first

    onProgress?.call('1/4 拉取日K数据...', 0, targetStocks.length <= 0 ? 1 : targetStocks.length);
    final barsByCode = await _fetcher(
      stocks: targetStocks,
      count: targetBars,
      mode: mode,
      onProgress: (c, t) => onProgress?.call('1/4 拉取日K数据...', c, t),
    );

    onProgress?.call('2/4 写入日K文件...', 0, targetStocks.length <= 0 ? 1 : targetStocks.length);
    await _cacheStore.saveAll(barsByCode, onProgress: (c, t) {
      onProgress?.call('2/4 写入日K文件...', c, t);
    });

    final success = <String>[];
    final failure = <String>[];
    final reasons = <String, String>{};
    for (final stock in targetStocks) {
      final bars = barsByCode[stock.code] ?? const <KLine>[];
      if (bars.isEmpty) {
        failure.add(stock.code);
        reasons[stock.code] = 'empty_fetch_result';
      } else {
        success.add(stock.code);
      }
    }

    final now = _nowProvider();
    final nowMs = now.millisecondsSinceEpoch;
    final dateKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final perStock = await _checkpointStore.loadPerStockSuccessAtMs();
    for (final code in success) {
      perStock[code] = nowMs;
    }
    await _checkpointStore.savePerStockSuccessAtMs(perStock);
    await _checkpointStore.saveGlobal(
      dateKey: dateKey,
      mode: mode,
      successAtMs: nowMs,
    );

    onProgress?.call('4/4 保存缓存检查点...', 1, 1);

    return DailyKlineSyncResult(
      successStockCodes: success,
      failureStockCodes: failure,
      failureReasons: reasons,
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/daily_kline_sync_service_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/services/daily_kline_sync_service.dart test/services/daily_kline_sync_service_test.dart
git commit -m "feat: add daily kline sync service with incremental and full modes"
```

### Task 4: Refactor MarketDataProvider To Orchestrate Read/Sync Services

**Files:**
- Modify: `lib/providers/market_data_provider.dart`
- Modify: `test/providers/market_data_provider_test.dart`

**Step 1: Write the failing test**

Add tests in `test/providers/market_data_provider_test.dart`:

```dart
test('daily recompute should fail fast when read service reports missing file', () async {
  final provider = buildProviderWithFakeReadService(
    readFailure: const DailyKlineReadException(
      stockCode: '600000',
      reason: DailyKlineReadFailureReason.missingFile,
      message: 'missing',
    ),
  );

  final result = await provider.recalculateBreakouts();
  expect(result, contains('missing'));
});

test('refresh should not trigger daily network sync unless explicit daily action called', () async {
  final fakeSyncService = FakeDailyKlineSyncService();
  final provider = buildProviderWithFakeSyncService(syncService: fakeSyncService);

  await provider.refresh(silent: true);
  expect(fakeSyncService.syncCallCount, 0);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/providers/market_data_provider_test.dart --plain-name "daily recompute should fail fast"`  
Expected: FAIL because provider does not yet inject/use read/sync services.

**Step 3: Write minimal implementation**

Implementation checklist:

- Inject new dependencies into provider constructor:
  - `DailyKlineReadService? dailyKlineReadService`
  - `DailyKlineSyncService? dailyKlineSyncService`
  - default constructors for production.
- Add explicit methods:
  - `Future<void> syncDailyBarsIncremental(...)`
  - `Future<void> syncDailyBarsForceFull(...)`
- Keep `forceRefetchDailyBars(...)` as compatibility wrapper calling `syncDailyBarsForceFull(...)` during migration.
- Replace direct `_pool.batchGetSecurityBarsStreaming(...)` daily fetch path with `DailyKlineSyncService.sync(...)`.
- Replace `_restoreDailyBarsFromFile(...)` plus implicit tolerance with strict `DailyKlineReadService.readOrThrow(...)` in daily compute entrypoints.
- On `DailyKlineReadException`, stop pipeline and surface message.

Minimal skeleton:

```dart
Future<void> syncDailyBarsIncremental({
  void Function(String stage, int current, int total)? onProgress,
  Set<String>? indicatorTargetStockCodes,
}) async {
  final stocks = _allData.map((e) => e.stock).toList(growable: false);
  final result = await _dailyKlineSyncService.sync(
    mode: DailyKlineSyncMode.incremental,
    stocks: stocks,
    targetBars: _dailyCacheTargetBars,
    onProgress: onProgress,
  );
  await _reloadDailyBarsOrThrow();
  await _runDailyIndicatorsAfterSync(indicatorTargetStockCodes);
  if (result.failureStockCodes.isNotEmpty) {
    throw StateError('部分股票日K拉取失败: ${result.failureStockCodes.take(5).join(', ')}');
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/providers/market_data_provider_test.dart --plain-name "daily recompute should fail fast"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/providers/market_data_provider.dart test/providers/market_data_provider_test.dart
git commit -m "refactor: make market data provider orchestrate daily read and sync services"
```

### Task 5: Wire New Services In App DI

**Files:**
- Modify: `lib/main.dart`
- Test: `test/providers/market_data_provider_test.dart`

**Step 1: Write the failing test**

Add/adjust provider construction test to ensure `MarketDataProvider` receives concrete read/sync services from DI.

```dart
testWidgets('main DI should build market provider with daily read/sync services', (tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();
  // If wiring is broken, provider init throws and test fails.
  expect(find.byType(MaterialApp), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/providers/market_data_provider_test.dart --plain-name "daily read/sync services"`  
Expected: FAIL if constructor signature changed but DI not updated.

**Step 3: Write minimal implementation**

In `lib/main.dart`, register both services and pass them into `MarketDataProvider`:

```dart
Provider(create: (_) => DailyKlineCheckpointStore()),
ProxyProvider<DailyKlineCacheStore, DailyKlineReadService>(
  update: (_, cacheStore, __) => DailyKlineReadService(cacheStore: cacheStore),
),
ProxyProvider3<TdxPool, DailyKlineCacheStore, DailyKlineCheckpointStore, DailyKlineSyncService>(
  update: (_, pool, cacheStore, checkpointStore, __) {
    return DailyKlineSyncService(
      checkpointStore: checkpointStore,
      cacheStore: cacheStore,
      fetcher: buildTdxDailyFetcher(pool),
    );
  },
),
```

Then pass to provider constructor.

**Step 4: Run test to verify it passes**

Run: `flutter test test/providers/market_data_provider_test.dart --plain-name "daily read/sync services"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/main.dart test/providers/market_data_provider_test.dart
git commit -m "chore: wire daily read and sync services in app DI"
```

### Task 6: Update Data Management UI To Two Explicit Daily Buttons

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `lib/audit/models/audit_operation_type.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing test**

Add widget tests asserting two buttons inside `日K数据` card:

```dart
testWidgets('日K数据卡片显示增量拉取与强制全量拉取两个动作', (tester) async {
  await pumpDataManagement(...);
  await scrollToText(tester, '日K数据');

  final dailyCard = find.ancestor(
    of: find.text('日K数据'),
    matching: find.byType(Card),
  );

  expect(
    find.descendant(of: dailyCard, matching: find.text('增量拉取')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: dailyCard, matching: find.text('强制全量拉取')),
    findsOneWidget,
  );
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "日K数据卡片显示增量拉取与强制全量拉取两个动作"`  
Expected: FAIL (current UI has only one button).

**Step 3: Write minimal implementation**

- Extend `_buildCacheItem(...)` to support two actions for daily card.
- Replace current daily action binding:
  - `增量拉取` -> `_syncDailyIncremental(context)`
  - `强制全量拉取` -> `_syncDailyForceFull(context)` with confirm dialog.
- Add new audit operation enum case:
  - `dailyFetchIncremental`
- Keep existing `dailyForceRefetch` for full mode.

Minimal API shape:

```dart
Future<void> _syncDailyIncremental(BuildContext context) async { ... }
Future<void> _syncDailyForceFull(BuildContext context) async { ... }
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "日K数据卡片显示增量拉取与强制全量拉取两个动作"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart lib/audit/models/audit_operation_type.dart test/screens/data_management_screen_test.dart
git commit -m "feat: split daily data management actions into incremental and force-full"
```

### Task 7: Remove Daily-K Payload Semantics From SharedPreferences Paths

**Files:**
- Modify: `lib/providers/market_data_provider.dart`
- Test: `test/providers/market_data_provider_test.dart`

**Step 1: Write the failing test**

Add test to guarantee no daily bars payload key is written:

```dart
test('daily sync should not write daily bars payload into SharedPreferences', () async {
  SharedPreferences.setMockInitialValues({});
  final provider = buildProviderWithFakes(...);

  await provider.syncDailyBarsForceFull();

  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getString('daily_bars_cache_v1'), isNull);
  expect(prefs.getString('daily_kline_checkpoint_last_mode'), isNotNull);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/providers/market_data_provider_test.dart --plain-name "not write daily bars payload"`  
Expected: FAIL if old payload handling still writes/depends on daily cache payload key.

**Step 3: Write minimal implementation**

- Remove any remaining code branch that serializes daily bars into prefs.
- Keep only migration cleanup logic (one-way remove old key if exists).
- Move all ongoing daily metadata writes to checkpoint store keys.

Minimal migration helper:

```dart
Future<void> _cleanupLegacyDailyPayload() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey('daily_bars_cache_v1')) {
    await prefs.remove('daily_bars_cache_v1');
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/providers/market_data_provider_test.dart --plain-name "not write daily bars payload"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/providers/market_data_provider.dart test/providers/market_data_provider_test.dart
git commit -m "refactor: keep daily shared preferences as checkpoint-only"
```

### Task 8: Update Integration Test Driver + Fixtures For New Daily Actions

**Files:**
- Modify: `integration_test/support/data_management_driver.dart`
- Modify: `integration_test/support/data_management_fixtures.dart`
- Modify: `integration_test/features/data_management_offline_test.dart`

**Step 1: Write the failing test**

Add/adjust e2e tests:

```dart
testWidgets('daily incremental sync completes with staged progress', (tester) async {
  final context = await launchDataManagementWithFixture(tester);
  final driver = DataManagementDriver(tester);

  await driver.tapDailyIncrementalFetch();
  await driver.expectProgressDialogVisible();
  await driver.waitForProgressDialogClosedWithWatchdog(context.createWatchdog());

  await driver.expectSnackBarContains('日K数据已增量拉取');
  expect(context.marketProvider.dailyIncrementalSyncCount, 1);
});
```

```dart
testWidgets('daily compute fails fast on corrupted cache preset', (tester) async {
  final context = await launchDataManagementWithFixture(
    tester,
    preset: DataManagementFixturePreset.corruptedDailyCache,
  );
  final driver = DataManagementDriver(tester);

  await driver.tapDailyIncrementalFetch();
  await driver.waitForProgressDialogClosedWithWatchdog(context.createWatchdog());

  await driver.expectSnackBarContains('日K读取失败');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test integration_test/features/data_management_offline_test.dart --plain-name "daily incremental sync completes with staged progress"`  
Expected: FAIL because driver/fixture still only exposes force action.

**Step 3: Write minimal implementation**

- Add new driver methods:
  - `tapDailyIncrementalFetch()` -> tap `增量拉取`
  - `tapDailyForceFullFetch()` -> tap `强制全量拉取` + confirm
- Extend fake provider fields:
  - `dailyIncrementalSyncCount`
  - `dailyForceFullSyncCount`
- Update fixture progress stage labels to new mode-specific messages.
- Add preset `corruptedDailyCache` to force read failure message.

**Step 4: Run test to verify it passes**

Run: `flutter test integration_test/features/data_management_offline_test.dart --plain-name "daily incremental sync completes with staged progress"`  
Expected: PASS.

**Step 5: Commit**

```bash
git add integration_test/support/data_management_driver.dart integration_test/support/data_management_fixtures.dart integration_test/features/data_management_offline_test.dart
git commit -m "test: add e2e coverage for daily incremental and force-full flows"
```

### Task 9: Final Verification Matrix And Plan-Linked Evidence

**Files:**
- Modify: `docs/plans/2026-02-17-daily-kline-read-write-decoupling-implementation.md`

**Step 1: Run targeted unit tests**

Run:

```bash
flutter test test/services/daily_kline_read_service_test.dart -r expanded
flutter test test/data/storage/daily_kline_checkpoint_store_test.dart -r expanded
flutter test test/services/daily_kline_sync_service_test.dart -r expanded
flutter test test/providers/market_data_provider_test.dart -r expanded
flutter test test/screens/data_management_screen_test.dart -r expanded
```

Expected: PASS all.

**Step 2: Run targeted integration tests**

Run:

```bash
flutter test integration_test/features/data_management_offline_test.dart -r expanded
```

Expected: PASS all daily incremental/full scenarios, including fail-fast read case.

**Step 3: Run regression smoke for existing daily refetch behavior naming migration**

Run:

```bash
flutter test test/integration/daily_kline_storage_e2e_test.dart -r expanded
flutter test test/integration/daily_kline_refetch_performance_e2e_test.dart -r expanded
```

Expected: PASS (or updated assertions if message labels changed intentionally).

**Step 4: Record verification evidence in this plan file**

Append a short checklist section:

```markdown
## Verification Evidence
- [ ] daily read service tests passed
- [ ] checkpoint store tests passed
- [ ] sync service tests passed
- [ ] provider + data management widget tests passed
- [ ] offline integration tests passed
```

**Step 5: Commit**

```bash
git add docs/plans/2026-02-17-daily-kline-read-write-decoupling-implementation.md
git commit -m "docs: attach verification checklist for daily kline decoupling rollout"
```
