# Daily Kline Force-Full Tolerance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow daily force-full sync to succeed when some stocks have fewer than target daily bars, while keeping daily MACD/ADX recompute manual and verifiable via E2E.

**Architecture:** Add an optional minimum-bar threshold to `DailyKlineReadService.readOrThrow`; keep strict validation for missing/corrupted data. Pass a low minimum (1 bar) from daily sync and cache restore so short listing histories no longer abort the whole sync. Verify using the real-network E2E that daily force-full does not auto-recompute indicators and that manual MACD/ADX renders for a stock with sufficient bars.

**Tech Stack:** Flutter, Dart, `flutter_test`, `integration_test`.

---

**Current State (Saved Report)**
- Real-network E2E `integration_test/features/daily_kline_macd_adx_real_regression_test.dart` fails during “日K强制全量拉取”.
- Error: `DailyKlineReadException(stock=688785, reason=insufficientBars, message=got 13, expected 260)`.
- Root cause location: `lib/services/daily_kline_read_service.dart` throws when `bars.length < targetBars`.
- Impact: daily force-full aborts; downstream cache restore and manual indicator recompute are blocked.

### Task 1: Add a failing unit test for tolerant daily read

**Files:**
- Modify: `test/services/daily_kline_read_service_test.dart`

**Step 1: Write the failing test**
```dart
test('readOrThrow returns partial bars when minBars is lower than target', () async {
  final tempDir = await Directory.systemTemp.createTemp('daily-read-partial-');
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final store = _buildStore(tempDir.path);
  await store.saveAll({'600000': _buildBars(120)});

  final service = DailyKlineReadService(cacheStore: store);
  final result = await service.readOrThrow(
    stockCodes: const ['600000'],
    anchorDate: DateTime(2026, 12, 31),
    targetBars: 260,
    minBars: 1,
  );

  expect(result['600000'], isNotNull);
  expect(result['600000']!.length, 120);
});
```

**Step 2: Run test to verify it fails**
Run: `flutter test test/services/daily_kline_read_service_test.dart -r compact`
Expected: FAIL because `readOrThrow` does not accept `minBars` or still throws `insufficientBars`.

### Task 2: Implement tolerant read in `DailyKlineReadService`

**Files:**
- Modify: `lib/services/daily_kline_read_service.dart`
- Modify: `test/services/daily_kline_read_service_test.dart`
- Modify: `test/providers/market_data_provider_test.dart`

**Step 1: Write minimal implementation**
```dart
Future<Map<String, List<KLine>>> readOrThrow({
  required List<String> stockCodes,
  required DateTime anchorDate,
  required int targetBars,
  int? minBars,
}) async {
  final requiredBars = minBars ?? targetBars;
  // ...
  if (bars.length < requiredBars) {
    throw DailyKlineReadException(
      stockCode: stockCode,
      reason: DailyKlineReadFailureReason.insufficientBars,
      message:
          'Daily bars shorter than target: got ${bars.length}, expected $requiredBars',
    );
  }
  // ...
}
```
Update the fake read service signature to include `minBars` and forward or ignore it.

**Step 2: Run test to verify it passes**
Run: `flutter test test/services/daily_kline_read_service_test.dart -r compact`
Expected: PASS.

**Step 3: Run provider tests to ensure signature changes didn’t break**
Run: `flutter test test/providers/market_data_provider_test.dart -r compact`
Expected: PASS.

### Task 3: Use tolerant read for daily sync and cache restore

**Files:**
- Modify: `lib/providers/market_data_provider.dart`

**Step 1: Update cache restore and reload to accept partial bars**
```dart
final loaded = await _dailyKlineReadService.readOrThrow(
  stockCodes: stockCodes,
  anchorDate: DateTime(anchorDate.year, anchorDate.month, anchorDate.day),
  targetBars: targetBars,
  minBars: 1,
);
```
Apply to `_restoreDailyBarsFromFile` and `_reloadDailyBarsOrThrow`.

**Step 2: Run unit tests again**
Run: `flutter test test/providers/market_data_provider_test.dart -r compact`
Expected: PASS.

### Task 4: Re-run the real-network E2E

**Files:**
- Verify: `integration_test/features/daily_kline_macd_adx_real_regression_test.dart`

**Step 1: Run the E2E**
Run: `flutter test integration_test/features/daily_kline_macd_adx_real_regression_test.dart -d macos -r compact --dart-define=RUN_DATA_MGMT_REAL_E2E=true`
Expected: PASS. No “日K数据强制全量拉取失败” snackbar; manual daily MACD/ADX renders on stock detail.

### Task 5: Commit

**Step 1: Commit test + production changes**
Run:
```bash
git add test/services/daily_kline_read_service_test.dart \
  test/providers/market_data_provider_test.dart \
  lib/services/daily_kline_read_service.dart \
  lib/providers/market_data_provider.dart

git commit -m "fix: tolerate short daily kline histories during reload"
```

---

Plan complete and saved to `docs/plans/2026-02-18-daily-kline-insufficient-bars-plan.md`.

Two execution options:
1. Subagent-Driven (this session)
2. Parallel Session (separate)

Which approach?
