# ADX Real-Data E2E Benchmark & Latency Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 ADX 增加基于实际全量数据的 e2e 耗时观测与 UI 卡顿观测，并在数据管理链路实现可验证的总等待时间优化。

**Architecture:** 在现有 Data Management real-network E2E 基础上扩展 ADX 重算流程与帧时序采样；新增一套 ADX 周线重算基准压测（可选运行）用于参数扫点；在 `MarketDataProvider.forceRefetchDailyBars` 中把 MACD/ADX 日线预热从串行改并行以缩短用户等待时长，并用单测守护并发行为。

**Tech Stack:** Flutter `integration_test`, `flutter_test`, Dart async/Future orchestration, 现有 `DataManagementDriver`/fixtures, `AdxIndicatorService`。

---

### Task 1: Add failing coverage for ADX recompute E2E driver path

**Files:**
- Modify: `integration_test/features/data_management_offline_test.dart`
- Modify: `integration_test/support/data_management_fixtures.dart`
- Modify: `integration_test/support/data_management_driver.dart`

**Step 1: Write failing test for weekly ADX recompute UX observability**

Add a new offline integration test similar to weekly MACD case:
- open weekly ADX settings
- trigger weekly ADX recompute
- assert dialog visible
- assert `速率` and `预计剩余` appear
- wait for dialog close via watchdog
- assert completion snackbar

**Step 2: Run test to verify it fails**

Run:
```bash
flutter test integration_test/features/data_management_offline_test.dart -d macos -r compact --plain-name "weekly ADX recompute should expose progress hints and close without stall"
```
Expected: FAIL because ADX fixture/driver methods are missing.

**Step 3: Implement minimal fixture + driver support**

- Add `tapWeeklyAdxSettings`, `tapWeeklyAdxRecompute`, and ADX dialog wait helpers in driver.
- Add `FakeAdxIndicatorService` in fixture and register it in provider tree.
- Wire fixture context to expose ADX service if needed by assertions.

**Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

**Step 5: Commit**

```bash
git add integration_test/features/data_management_offline_test.dart integration_test/support/data_management_fixtures.dart integration_test/support/data_management_driver.dart
git commit -m "test: cover weekly adx recompute progress in offline e2e"
```

### Task 2: Add ADX real-network E2E timing + UI freeze observability

**Files:**
- Create: `integration_test/support/frame_timing_probe.dart`
- Modify: `integration_test/features/data_management_real_network_test.dart`

**Step 1: Write failing/compilation test expectations in real-network spec path**

Extend real-network scenario with weekly ADX recompute stage and frame metrics logging calls.

**Step 2: Run static verification to catch missing symbols**

Run:
```bash
flutter test integration_test/features/data_management_real_network_test.dart -d macos -r compact
```
Expected: FAIL (or compile error) before probe/helper is added.

**Step 3: Implement frame timing probe and ADX stage instrumentation**

- Add a reusable probe class that records frame timings and summarizes:
  - total frames
  - slow frames (`>=50ms`)
  - severe frames (`>=100ms`)
  - freeze-like frames (`>=700ms`)
  - max frame total ms
- In real-network test, wrap weekly ADX recompute window with probe start/stop and print structured metrics.
- Keep watchdog checks and progress-hint assertions consistent with existing MACD style.

**Step 4: Run compile verification again**

Run the same command as Step 2.
Expected: PASS (test may skip if define not set, but file compiles).

**Step 5: Commit**

```bash
git add integration_test/support/frame_timing_probe.dart integration_test/features/data_management_real_network_test.dart
git commit -m "test: add real-network adx timing and ui jank observability"
```

### Task 3: Add weekly ADX full-data benchmark test + helper script

**Files:**
- Create: `test/integration/weekly_adx_recompute_benchmark_test.dart`
- Create: `scripts/benchmark_weekly_adx_recompute.sh`

**Step 1: Write benchmark test skeleton mirroring weekly MACD benchmark**

- Gate by `RUN_REAL_WEEKLY_ADX_BENCH=1`
- Support env sweep:
  - `WEEKLY_ADX_BENCH_STOCK_LIMIT`
  - `WEEKLY_ADX_BENCH_POOL_SIZE`
  - `WEEKLY_ADX_BENCH_RANGE_DAYS`
  - `WEEKLY_ADX_BENCH_SWEEP` (`fetchBatch x persistConcurrency`)
- Emit rows with `[WEEKLY_ADX_BENCH][run]` for script parsing.

**Step 2: Run benchmark test in skipped mode to verify compile**

Run:
```bash
flutter test test/integration/weekly_adx_recompute_benchmark_test.dart -d macos -r compact
```
Expected: PASS with skip message when env not enabled.

**Step 3: Add parser script for sweep summary and recommendation**

- Parse log rows with `rg`
- Output TSV summary
- Print best combination based on totalMs and firstProgressMs constraint.

**Step 4: Lint script formatting quickly**

Run:
```bash
bash -n scripts/benchmark_weekly_adx_recompute.sh
```
Expected: PASS.

**Step 5: Commit**

```bash
git add test/integration/weekly_adx_recompute_benchmark_test.dart scripts/benchmark_weekly_adx_recompute.sh
git commit -m "test: add weekly adx recompute benchmark sweep tooling"
```

### Task 4: Optimize indicator-stage total wait by parallel MACD+ADX prewarm

**Files:**
- Modify: `test/providers/market_data_provider_test.dart`
- Modify: `lib/providers/market_data_provider.dart`

**Step 1: Write failing provider test for concurrent daily indicator prewarm startup**

Add a test that:
- injects blocking fake MACD and ADX services
- starts `forceRefetchDailyBars`
- verifies both prewarm paths start before either is unblocked

**Step 2: Run targeted test to verify it fails on sequential behavior**

Run:
```bash
flutter test test/providers/market_data_provider_test.dart -r compact --plain-name "forceRefetchDailyBars should start MACD and ADX prewarm concurrently"
```
Expected: FAIL because current code awaits MACD then ADX.

**Step 3: Implement concurrent prewarm orchestration**

- In `forceRefetchDailyBars`, run daily MACD/ADX prewarm via `Future.wait` with aggregated progress mapping.
- Preserve existing stage labels and progress safety handling.
- Keep behavior unchanged when one service is absent.

**Step 4: Run targeted and related tests**

Run:
```bash
flutter test test/providers/market_data_provider_test.dart -r compact
```
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/providers/market_data_provider.dart test/providers/market_data_provider_test.dart
git commit -m "perf: parallelize daily macd-adx prewarm to reduce wait"
```

### Task 5: Final verification pass

**Files:**
- Modify (if needed): none or touched files above

**Step 1: Run focused regression suite**

Run:
```bash
flutter test integration_test/features/data_management_offline_test.dart -d macos -r compact
flutter test test/services/adx_indicator_service_test.dart -r compact
flutter test test/screens/data_management_screen_test.dart -r compact --plain-name "ADX"
flutter test test/providers/market_data_provider_test.dart -r compact
```
Expected: PASS.

**Step 2: Run full test suite (or agreed broad suite)**

Run:
```bash
flutter test
```
Expected: PASS.

**Step 3: Summarize benchmark/e2e commands for real full-data run**

Document runnable commands in final response:
```bash
flutter test integration_test/features/data_management_real_network_test.dart -d macos --dart-define=RUN_DATA_MGMT_REAL_E2E=true -r compact
RUN_REAL_WEEKLY_ADX_BENCH=1 WEEKLY_ADX_BENCH_STOCK_LIMIT=500 WEEKLY_ADX_BENCH_SWEEP='40x6,80x8,120x8' scripts/benchmark_weekly_adx_recompute.sh
```

**Step 4: Commit remaining changes**

```bash
git add docs/plans/2026-02-17-adx-e2e-benchmark-optimization-implementation.md
git commit -m "docs: add adx e2e benchmark and optimization implementation plan"
```
