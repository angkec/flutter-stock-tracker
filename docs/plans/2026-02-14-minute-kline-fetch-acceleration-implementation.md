# Minute K-Line Fetch Acceleration (Phase 1) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deliver a pool-based minute-K fetch pipeline that keeps full-market bootstrap around ~5 minutes and makes subsequent refreshes incremental-first.

**Architecture:** Keep `DataRepository` as the integration boundary, but split minute fetch flow into three focused components: planner, pool fetch adapter, and batch writer. Introduce `minute_sync_state` as the incremental source-of-truth so post-bootstrap refreshes fetch only missing/incomplete trading days. Keep a runtime fallback switch to the legacy path for safe rollout.

**Tech Stack:** Flutter/Dart, `sqflite`, existing `TdxPool` / `TdxClient`, Provider DI, flutter_test integration tests

**Design Doc:** `docs/plans/2026-02-14-minute-kline-fetch-acceleration-design.md`

**Related Skills:** `@test-driven-development` `@systematic-debugging` `@verification-before-completion` `@requesting-code-review`

---

## Pre-Task: Workspace Safety

**Step 0.1: Ensure isolated workspace**

Run:

```bash
git worktree list
```

Expected: Current implementation happens in a dedicated worktree, not the long-lived main workspace.

If not isolated, create one first using `@using-git-worktrees` before Task 1.

---

### Task 1: Add `minute_sync_state` schema + storage model

**Files:**
- Create: `lib/data/models/minute_sync_state.dart`
- Create: `lib/data/storage/minute_sync_state_storage.dart`
- Modify: `lib/data/storage/database_schema.dart`
- Modify: `lib/data/storage/market_database.dart`
- Test: `test/data/storage/minute_sync_state_storage_test.dart`

**Step 1: Write the failing test**

Create `test/data/storage/minute_sync_state_storage_test.dart`:

```dart
test('upsert + read should persist minute sync state', () async {
  final storage = MinuteSyncStateStorage(database: database);
  final state = MinuteSyncState(
    stockCode: '000001',
    lastCompleteTradingDay: DateTime(2026, 2, 13),
    consecutiveFailures: 0,
    updatedAt: DateTime(2026, 2, 14, 9, 0),
  );

  await storage.upsert(state);
  final loaded = await storage.getByStockCode('000001');

  expect(loaded, isNotNull);
  expect(loaded!.stockCode, '000001');
  expect(loaded.lastCompleteTradingDay, DateTime(2026, 2, 13));
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/minute_sync_state_storage_test.dart -r compact`

Expected: FAIL with import errors and/or `no such table: minute_sync_state`.

**Step 3: Write minimal implementation**

Create `lib/data/models/minute_sync_state.dart`:

```dart
class MinuteSyncState {
  final String stockCode;
  final DateTime? lastCompleteTradingDay;
  final DateTime? lastSuccessFetchAt;
  final DateTime? lastAttemptAt;
  final int consecutiveFailures;
  final String? lastError;
  final DateTime updatedAt;

  const MinuteSyncState({
    required this.stockCode,
    required this.lastCompleteTradingDay,
    this.lastSuccessFetchAt,
    this.lastAttemptAt,
    this.consecutiveFailures = 0,
    this.lastError,
    required this.updatedAt,
  });
}
```

Create table/index in `database_schema.dart` and migration in `market_database.dart` (`version` bump + `onUpgrade` branch).

Create `MinuteSyncStateStorage` with `upsert`, `getByStockCode`, `getBatchByStockCodes`, `markFetchFailure`, `markFetchSuccess`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/minute_sync_state_storage_test.dart -r compact`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/models/minute_sync_state.dart \
  lib/data/storage/minute_sync_state_storage.dart \
  lib/data/storage/database_schema.dart \
  lib/data/storage/market_database.dart \
  test/data/storage/minute_sync_state_storage_test.dart
git commit -m "feat: add minute sync state storage and schema"
```

---

### Task 2: Add minute sync planner (bootstrap/incremental/backfill)

**Files:**
- Create: `lib/data/repository/minute_sync_planner.dart`
- Test: `test/data/repository/minute_sync_planner_test.dart`

**Step 1: Write the failing test**

Create planner tests:

```dart
test('planner returns bootstrap for stock without sync state', () {
  final planner = MinuteSyncPlanner();
  final plan = planner.planForStock(
    stockCode: '000001',
    tradingDates: [DateTime(2026, 2, 10), DateTime(2026, 2, 11)],
    syncState: null,
    knownMissingDates: const [],
    knownIncompleteDates: const [],
  );

  expect(plan.mode, MinuteSyncMode.bootstrap);
  expect(plan.datesToFetch.length, 2);
});

test('planner returns incremental dates after last complete day', () {
  final planner = MinuteSyncPlanner();
  final plan = planner.planForStock(
    stockCode: '000001',
    tradingDates: [
      DateTime(2026, 2, 10),
      DateTime(2026, 2, 11),
      DateTime(2026, 2, 12),
    ],
    syncState: MinuteSyncState(
      stockCode: '000001',
      lastCompleteTradingDay: DateTime(2026, 2, 11),
      updatedAt: DateTime(2026, 2, 14),
    ),
    knownMissingDates: const [],
    knownIncompleteDates: const [],
  );

  expect(plan.mode, MinuteSyncMode.incremental);
  expect(plan.datesToFetch, [DateTime(2026, 2, 12)]);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/minute_sync_planner_test.dart -r compact`

Expected: FAIL with missing planner symbols.

**Step 3: Write minimal implementation**

Create `minute_sync_planner.dart`:

```dart
enum MinuteSyncMode { skip, bootstrap, incremental, backfill }

class MinuteFetchPlan {
  final String stockCode;
  final MinuteSyncMode mode;
  final List<DateTime> datesToFetch;
  const MinuteFetchPlan({
    required this.stockCode,
    required this.mode,
    required this.datesToFetch,
  });
}

class MinuteSyncPlanner {
  MinuteFetchPlan planForStock({
    required String stockCode,
    required List<DateTime> tradingDates,
    required MinuteSyncState? syncState,
    required List<DateTime> knownMissingDates,
    required List<DateTime> knownIncompleteDates,
  }) {
    // Minimal deterministic plan logic.
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/minute_sync_planner_test.dart -r compact`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/repository/minute_sync_planner.dart \
  test/data/repository/minute_sync_planner_test.dart
git commit -m "feat: add minute sync planner for bootstrap and incremental modes"
```

---

### Task 3: Add pool-based minute fetch adapter

**Files:**
- Create: `lib/data/repository/minute_fetch_adapter.dart`
- Create: `lib/data/repository/tdx_pool_fetch_adapter.dart`
- Test: `test/data/repository/tdx_pool_fetch_adapter_test.dart`

**Step 1: Write the failing test**

Create adapter contract tests:

```dart
test('adapter returns per-stock bars map and invokes progress', () async {
  final adapter = TdxPoolFetchAdapter(pool: fakePool);
  final result = await adapter.fetchMinuteBars(
    stockCodes: const ['000001', '000002'],
    start: 0,
    count: 800,
    onProgress: (current, total) {},
  );

  expect(result.keys, containsAll(['000001', '000002']));
  expect(result['000001'], isNotNull);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/tdx_pool_fetch_adapter_test.dart -r compact`

Expected: FAIL due to missing adapter implementation.

**Step 3: Write minimal implementation**

Create interface and implementation:

```dart
abstract class MinuteFetchAdapter {
  Future<Map<String, List<KLine>>> fetchMinuteBars({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  });
}
```

`TdxPoolFetchAdapter`:
- maps code -> `Stock(market: ..., code: ..., name: code)`
- uses `pool.batchGetSecurityBarsStreaming(...)`
- returns `Map<String, List<KLine>>`
- captures empty response as empty list (not exception)

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/tdx_pool_fetch_adapter_test.dart -r compact`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/repository/minute_fetch_adapter.dart \
  lib/data/repository/tdx_pool_fetch_adapter.dart \
  test/data/repository/tdx_pool_fetch_adapter_test.dart
git commit -m "feat: add pool-based minute fetch adapter"
```

---

### Task 4: Add minute sync writer (batch persistence + sync-state updates)

**Files:**
- Create: `lib/data/repository/minute_sync_writer.dart`
- Test: `test/data/repository/minute_sync_writer_test.dart`

**Step 1: Write the failing test**

Create tests:

```dart
test('writer skips empty bars and saves non-empty bars', () async {
  final writer = MinuteSyncWriter(
    metadataManager: metadataManager,
    syncStateStorage: syncStateStorage,
  );

  final result = await writer.writeBatch(
    barsByStock: {
      '000001': [sampleBar],
      '000002': [],
    },
    dataType: KLineDataType.oneMinute,
    fetchedTradingDay: DateTime(2026, 2, 13),
  );

  expect(result.updatedStocks, ['000001']);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/minute_sync_writer_test.dart -r compact`

Expected: FAIL due to missing writer class.

**Step 3: Write minimal implementation**

Create writer with result model:

```dart
class MinuteWriteResult {
  final List<String> updatedStocks;
  final int totalRecords;
  const MinuteWriteResult({required this.updatedStocks, required this.totalRecords});
}
```

`writeBatch` should:
- call `saveKlineData` only for non-empty stock bars
- aggregate `totalRecords`
- update `minute_sync_state` success metadata for updated stocks

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/minute_sync_writer_test.dart -r compact`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/repository/minute_sync_writer.dart \
  test/data/repository/minute_sync_writer_test.dart
git commit -m "feat: add minute sync writer for batch persistence"
```

---

### Task 5: Integrate new minute pipeline into `MarketDataRepository`

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `lib/main.dart`
- Create: `lib/config/minute_sync_config.dart`
- Test: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add repository tests:

```dart
test('fetchMissingData(oneMinute) uses new adapter pipeline when enabled', () async {
  final repository = MarketDataRepository(
    metadataManager: manager,
    minuteFetchAdapter: fakeAdapter,
    minuteSyncPlanner: planner,
    minuteSyncWriter: writer,
    minuteSyncConfig: const MinuteSyncConfig(enablePoolMinutePipeline: true),
  );

  await repository.fetchMissingData(
    stockCodes: ['000001'],
    dateRange: DateRange(DateTime(2026, 2, 10), DateTime(2026, 2, 14)),
    dataType: KLineDataType.oneMinute,
  );

  expect(fakeAdapter.fetchCalls, 1);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart --plain-name "uses new adapter pipeline" -r compact`

Expected: FAIL because constructor/config path not implemented.

**Step 3: Write minimal implementation**

Implement dependency injection in repository:

```dart
MarketDataRepository({
  ...
  MinuteFetchAdapter? minuteFetchAdapter,
  MinuteSyncPlanner? minuteSyncPlanner,
  MinuteSyncWriter? minuteSyncWriter,
  MinuteSyncConfig? minuteSyncConfig,
})
```

Add `MinuteSyncConfig` toggles:
- `enablePoolMinutePipeline`
- `poolBatchCount`
- `maxStocksPerChunk`

Switch `oneMinute` fetch path:
- if enabled: planner -> adapter -> writer -> batch verify/update events
- else: keep legacy path untouched

Wire defaults from `main.dart` DI.

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/data/repository/market_data_repository_test.dart \
  --plain-name "uses new adapter pipeline" -r compact
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart \
  lib/main.dart \
  lib/config/minute_sync_config.dart \
  test/data/repository/market_data_repository_test.dart
git commit -m "feat: integrate pool-based minute pipeline into repository"
```

---

### Task 6: Enforce incremental-first behavior and reduce repeated checks

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `lib/data/storage/minute_sync_state_storage.dart`
- Test: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add test:

```dart
test('second fetch only requests dates after last complete trading day', () async {
  // Arrange state where lastCompleteTradingDay == 2026-02-13
  // Trading dates include 2026-02-14
  // Assert adapter called with one-day target plan
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart --plain-name "only requests dates after last complete" -r compact`

Expected: FAIL due to current broad-range fetch.

**Step 3: Write minimal implementation**

In repository minute path:
- compute `tradingDates` once per call
- batch load sync states once (`getBatchByStockCodes`)
- plan by stock using cached tradingDates + per-stock status
- skip stocks with empty `datesToFetch`

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/data/repository/market_data_repository_test.dart \
  --plain-name "only requests dates after last complete" -r compact
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart \
  lib/data/storage/minute_sync_state_storage.dart \
  test/data/repository/market_data_repository_test.dart
git commit -m "feat: make minute fetch incremental-first with sync-state planning"
```

---

### Task 7: Add observability + rollout guard + targeted perf check

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `lib/config/minute_sync_config.dart`
- Create: `test/integration/minute_pipeline_smoke_test.dart`
- Modify: `docs/reports/system_status_2026-02-10.md`

**Step 1: Write the failing test**

Create smoke test (guarded by env var):

```dart
test('minute pipeline smoke logs throughput and completes sample fetch', () async {
  // RUN_REAL_TDX_TEST=1 required
  // fetch 50 stocks and assert totalRecords > 0 and failureCount acceptable
});
```

**Step 2: Run test to verify it fails**

Run:

```bash
RUN_REAL_TDX_TEST=1 flutter test test/integration/minute_pipeline_smoke_test.dart -r compact
```

Expected: FAIL because smoke test and observability fields are missing.

**Step 3: Write minimal implementation**

Add structured logs around minute pipeline:
- stocks planned / skipped / fetched
- total records / total duration / stocks per minute
- retry count and failure ratio

Add config toggles:
- `enablePoolMinutePipeline`
- `enableMinutePipelineLogs`
- `minutePipelineFallbackToLegacyOnError`

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/integration/minute_pipeline_smoke_test.dart -r compact
```

Expected: PASS when real network env is enabled; otherwise test is skipped by design.

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart \
  lib/config/minute_sync_config.dart \
  test/integration/minute_pipeline_smoke_test.dart \
  docs/reports/system_status_2026-02-10.md
git commit -m "chore: add minute pipeline observability and rollout guardrails"
```

---

## Final Verification Checklist (before PR)

1. Run targeted unit/integration suites:

```bash
flutter test test/data/storage/minute_sync_state_storage_test.dart -r compact
flutter test test/data/repository/minute_sync_planner_test.dart -r compact
flutter test test/data/repository/tdx_pool_fetch_adapter_test.dart -r compact
flutter test test/data/repository/minute_sync_writer_test.dart -r compact
flutter test test/data/repository/market_data_repository_test.dart -r compact
```

2. Run smoke test (optional real network):

```bash
RUN_REAL_TDX_TEST=1 flutter test test/integration/minute_pipeline_smoke_test.dart -r compact
```

3. Verify no regressions in existing real fetch smoke:

```bash
RUN_REAL_TDX_TEST=1 flutter test test/integration/real_tdx_fetch_smoke_test.dart -r compact
```

4. Collect evidence (`@verification-before-completion`):
- Include exact command outputs
- Include timing summary for planned/fetched/skipped stock counts
- Include fallback behavior evidence (toggle on/off)

5. Request review (`@requesting-code-review`) before merge.

---

## Post-Phase-1 Exit Criteria

- Full-market bootstrap path uses pool pipeline by default.
- Incremental refresh requests only post-watermark trading dates.
- Runtime fallback to legacy path is available.
- Test coverage exists for planner, adapter, writer, and repository integration.
- Evidence is captured for bootstrap throughput and incremental latency.

