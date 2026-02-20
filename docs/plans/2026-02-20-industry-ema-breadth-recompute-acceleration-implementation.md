# Industry EMA Breadth Recompute Acceleration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make industry EMA breadth recompute significantly faster and make progress dialog updates visibly responsive throughout the run.

**Architecture:** Keep existing service/UI boundaries, but optimize hot loops and progress granularity in `IndustryEmaBreadthService`. Replace repeated linear EMA scanning with per-stock forward pointers over sorted EMA points. Keep progress updates in the same callback contract (`onProgress(current,total,stage)`) while changing total unit semantics from per-industry to finer-grained per-(industry,date).

**Tech Stack:** Flutter, Dart async/await, Provider, existing cache stores (`DailyKlineCacheStore`, `EmaCacheStore`, `IndustryEmaBreadthCacheStore`), flutter_test.

---

### Task 1: Add failing tests for progress granularity and correctness safety

**Files:**
- Modify: `test/services/industry_ema_breadth_service_test.dart`
- Test: `test/services/industry_ema_breadth_service_test.dart`

**Step 1: Write the failing test for granular progress updates**

Add a new test that captures all `onProgress` callbacks and asserts:
- first callback is setup stage with `current=0`
- there are multiple in-flight updates (not only start/end + per industry)
- final callback reaches `current==total`

```dart
test('recomputeAllIndustries emits fine-grained progress updates', () async {
  final events = <({int current, int total, String stage})>[];

  await service.recomputeAllIndustries(
    startDate: DateTime(2026, 1, 5),
    endDate: DateTime(2026, 1, 11),
    onProgress: (current, total, stage) {
      events.add((current: current, total: total, stage: stage));
    },
  );

  expect(events, isNotEmpty);
  expect(events.first.current, 0);
  expect(events.last.current, events.last.total);
  expect(events.length, greaterThan(4));
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/industry_ema_breadth_service_test.dart`

Expected: FAIL on progress-event count assertion (current implementation only updates at coarse boundaries).

**Step 3: Add safety test for output equivalence on existing sample**

Extend existing coverage to ensure optimized implementation still preserves exact breadth results for known sample data (use existing `recomputeAllIndustries uses cached close and EMA only` assertions as baseline, keep unchanged expected points).

**Step 4: Run the same test file again**

Run: `flutter test test/services/industry_ema_breadth_service_test.dart`

Expected: New granularity test fails; existing correctness test still passes.

**Step 5: Commit**

```bash
git add test/services/industry_ema_breadth_service_test.dart
git commit -m "test: capture granular progress expectation for industry EMA breadth recompute"
```

### Task 2: Optimize recompute loop and introduce fine-grained progress units

**Files:**
- Modify: `lib/services/industry_ema_breadth_service.dart`
- Test: `test/services/industry_ema_breadth_service_test.dart`

**Step 1: Implement per-stock EMA pointer traversal (replace repeated linear scan)**

Inside `recomputeAllIndustries`, prebuild per-stock cursor state:

```dart
final emaCursorByStock = <String, int>{};
final emaValueByStock = <String, double?>{};
for (final code in allStocks) {
  emaCursorByStock[code] = -1;
  emaValueByStock[code] = null;
}
```

Then for each `date` in sorted `axisDates`, advance each stock cursor only forward while `pointDate <= date`, update last EMA once, and reuse for all industries/stocks on that date.

**Step 2: Remove hot-path `_latestWeeklyEma` usage from nested loops**

Replace:

```dart
final ema = _latestWeeklyEma(emaByStock[stockCode], upToDate: date);
```

With direct lookup from precomputed per-date state:

```dart
final ema = emaValueByStock[stockCode];
```

Keep `_latestWeeklyEma` only if needed by tests/helpers; delete if unused.

**Step 3: Change progress total semantics to finer units**

Set:

```dart
final totalUnits = max(1, industries.length * axisDates.length);
var completedUnits = 0;
```

Emit progress during processing (not only at industry end), for example every N units or each date:

```dart
completedUnits++;
onProgress?.call(
  completedUnits,
  totalUnits,
  '计算中 $industry ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
);
```

**Step 4: Yield periodically to keep UI responsive**

Add cooperative yield in long loops (every fixed unit interval):

```dart
if (completedUnits % 64 == 0) {
  await Future<void>.delayed(Duration.zero);
}
```

**Step 5: Keep completion semantics unchanged for caller**

Ensure final callback still reports completion:

```dart
onProgress?.call(totalUnits, totalUnits, '重算完成');
```

**Step 6: Run focused tests**

Run: `flutter test test/services/industry_ema_breadth_service_test.dart`

Expected: PASS (new granular progress test + old correctness tests).

**Step 7: Commit**

```bash
git add lib/services/industry_ema_breadth_service.dart test/services/industry_ema_breadth_service_test.dart
git commit -m "perf: optimize industry EMA breadth recompute and emit granular progress"
```

### Task 3: Verify UI progress dialog reflects in-flight updates

**Files:**
- Modify: `test/screens/industry_ema_breadth_settings_screen_test.dart`
- Optional modify: `lib/screens/industry_ema_breadth_settings_screen.dart`
- Test: `test/screens/industry_ema_breadth_settings_screen_test.dart`

**Step 1: Add failing widget test with multi-stage progress**

Update fake service in test file to emit 3+ staged updates with short async gaps:

```dart
onProgress?.call(0, 6, '准备重算行业EMA广度...');
await Future<void>.delayed(const Duration(milliseconds: 10));
onProgress?.call(2, 6, '计算中 A');
await Future<void>.delayed(const Duration(milliseconds: 10));
onProgress?.call(4, 6, '计算中 B');
await Future<void>.delayed(const Duration(milliseconds: 10));
onProgress?.call(6, 6, '重算完成');
```

Assert dialog text transitions include intermediate stage and updated counts.

**Step 2: Run test to verify fail (if current fake not adequate)**

Run: `flutter test test/screens/industry_ema_breadth_settings_screen_test.dart`

Expected: FAIL before fake/service alignment.

**Step 3: Minimal UI-side adjustment only if needed**

If test reveals dialog lifecycle race (e.g., immediate pop before frame), add minimal stabilization in screen logic without changing UX contract.

**Step 4: Re-run widget test file**

Run: `flutter test test/screens/industry_ema_breadth_settings_screen_test.dart`

Expected: PASS and progress text/counter visibly updates in test.

**Step 5: Commit**

```bash
git add test/screens/industry_ema_breadth_settings_screen_test.dart lib/screens/industry_ema_breadth_settings_screen.dart
git commit -m "test: verify industry EMA breadth dialog shows intermediate progress updates"
```

### Task 4: Full verification and regression guard

**Files:**
- Verify: `lib/services/industry_ema_breadth_service.dart`
- Verify: `lib/screens/industry_ema_breadth_settings_screen.dart`
- Verify: `test/services/industry_ema_breadth_service_test.dart`
- Verify: `test/screens/industry_ema_breadth_settings_screen_test.dart`

**Step 1: Run modified test targets together**

Run: `flutter test test/services/industry_ema_breadth_service_test.dart test/screens/industry_ema_breadth_settings_screen_test.dart`

Expected: PASS.

**Step 2: Run related integration test**

Run: `flutter test test/integration/industry_ema_breadth_flow_test.dart`

Expected: PASS and no recompute-on-detail regression.

**Step 3: Run diagnostics/build-quality command used by repo**

Run: `flutter test`

Expected: No new failures introduced by this change set.

**Step 4: Final review checklist**

- complexity hotspot removed (no repeated linear scan in inner loop)
- progress callback emitted during in-flight compute
- UI dialog receives and renders intermediate updates
- existing breadth result expectations unchanged

**Step 5: Commit**

```bash
git add lib/services/industry_ema_breadth_service.dart lib/screens/industry_ema_breadth_settings_screen.dart test/services/industry_ema_breadth_service_test.dart test/screens/industry_ema_breadth_settings_screen_test.dart
git commit -m "fix: speed up industry EMA breadth recompute and restore live progress feedback"
```
