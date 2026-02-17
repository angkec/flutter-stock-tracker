# Daily/Weekly ADX Indicator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add full ADX support for daily/weekly K-line, including configurable calculation, cache prewarm/recompute entry points, and stock-detail rendering alongside MACD.

**Architecture:** Implement ADX as a sibling pipeline to MACD: dedicated `AdxIndicatorService`, `AdxCacheStore`, and `AdxSubChart`, with daily/weekly config separation and file-backed caches keyed by stock + data type. Integrate prewarm hooks into existing Data Management daily/weekly flows and expose ADX settings/recompute UI mirroring MACD behavior.

**Tech Stack:** Flutter, Provider, SharedPreferences, file-based JSON cache, Flutter widget tests, flutter_test unit tests.

---

## Execution Notes

- Follow `@superpowers:test-driven-development` for each task: test first, then minimal code.
- Use the isolated worktree branch `feature/adx-daily-weekly`.
- Keep commits small and scoped (one commit per task group).
- Before final success claims, run `@superpowers:verification-before-completion` checks.

### Task 1: Add ADX Models and Unit Tests

**Files:**
- Create: `lib/models/adx_config.dart`
- Create: `lib/models/adx_point.dart`
- Create: `test/models/adx_config_test.dart`
- Create: `test/models/adx_point_test.dart`

**Step 1: Write the failing tests**

```dart
// test/models/adx_config_test.dart
void main() {
  test('defaults are valid', () {
    expect(AdxConfig.defaults.isValid, isTrue);
    expect(AdxConfig.defaults.period, 14);
    expect(AdxConfig.defaults.threshold, 25);
  });

  test('fromJson falls back to defaults on invalid payload', () {
    final config = AdxConfig.fromJson({'period': 0, 'threshold': -1});
    expect(config, AdxConfig.defaults);
  });
}
```

```dart
// test/models/adx_point_test.dart
void main() {
  test('toJson/fromJson roundtrip', () {
    final point = AdxPoint(
      datetime: DateTime(2026, 2, 17),
      adx: 21.5,
      plusDi: 26.0,
      minusDi: 14.0,
    );

    final decoded = AdxPoint.fromJson(point.toJson());
    expect(decoded.datetime, point.datetime);
    expect(decoded.adx, point.adx);
    expect(decoded.plusDi, point.plusDi);
    expect(decoded.minusDi, point.minusDi);
  });
}
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/models/adx_config_test.dart test/models/adx_point_test.dart`
Expected: FAIL due to missing `AdxConfig` / `AdxPoint`.

**Step 3: Write minimal implementation**

```dart
class AdxConfig {
  final int period;
  final double threshold;
  // defaults/copyWith/isValid/toJson/fromJson/==/hashCode
}

class AdxPoint {
  final DateTime datetime;
  final double adx;
  final double plusDi;
  final double minusDi;
  // toJson/fromJson
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/models/adx_config_test.dart test/models/adx_point_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/models/adx_config.dart lib/models/adx_point.dart test/models/adx_config_test.dart test/models/adx_point_test.dart
git commit -m "feat: add adx config and point models"
```

### Task 2: Add ADX Cache Store and Storage Tests

**Files:**
- Create: `lib/data/storage/adx_cache_store.dart`
- Create: `test/data/storage/adx_cache_store_test.dart`

**Step 1: Write the failing tests**

```dart
void main() {
  test('saveSeries + loadSeries roundtrip', () async {
    await store.saveSeries(...);
    final loaded = await store.loadSeries(...);
    expect(loaded, isNotNull);
  });

  test('listStockCodes filters by dataType', () async {
    final weeklyCodes = await store.listStockCodes(dataType: KLineDataType.weekly);
    expect(weeklyCodes, contains('600000'));
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/adx_cache_store_test.dart`
Expected: FAIL due to missing store/types.

**Step 3: Write minimal implementation**

- Mirror `MacdCacheStore` patterns with `AdxCacheSeries` and `AdxCacheStore`.
- Use directory `adx_cache` and suffix `_<type>_adx_cache.json`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/adx_cache_store_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/storage/adx_cache_store.dart test/data/storage/adx_cache_store_test.dart
git commit -m "feat: add adx cache store"
```

### Task 3: Add ADX Indicator Service with Wilder Computation

**Files:**
- Create: `lib/services/adx_indicator_service.dart`
- Create: `test/services/adx_indicator_service_test.dart`

**Step 1: Write the failing tests**

```dart
test('getOrComputeFromBars computes adx and trims by window months', () async {
  final points = await service.getOrComputeFromBars(...);
  expect(points, isNotEmpty);
  expect(points.last.adx, greaterThanOrEqualTo(0));
});

test('prewarmFromRepository skips unchanged version+config+scope', () async {
  await service.prewarmFromRepository(...);
  await service.prewarmFromRepository(...);
  expect(repo.getKlinesCallCount, 1);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/adx_indicator_service_test.dart`
Expected: FAIL due to missing service.

**Step 3: Write minimal implementation**

- Implement APIs parallel to MACD:
  - `load/updateConfigFor/resetConfigFor/configFor`
  - `getOrComputeFromBars/getOrComputeFromRepository`
  - `prewarmFromBars/prewarmFromRepository`
- Implement Wilder-based ADX (`TR/+DM/-DM -> DI -> DX -> ADX`).
- Add source signature and prewarm snapshot logic.

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/adx_indicator_service_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/services/adx_indicator_service.dart test/services/adx_indicator_service_test.dart
git commit -m "feat: add adx indicator service with prewarm support"
```

### Task 4: Wire ADX Service into App DI and MarketDataProvider

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/providers/market_data_provider.dart`
- Modify: `test/screens/data_management_screen_test.dart` (fake provider/service wiring)

**Step 1: Write the failing tests**

Add/update tests to assert daily indicator stage triggers ADX prewarm callback during daily refetch path.

```dart
expect(adxService.prewarmDataTypes, contains(KLineDataType.daily));
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "3/4 计算指标"`
Expected: FAIL because ADX service is not wired.

**Step 3: Write minimal implementation**

- Register `AdxIndicatorService` in `main.dart`.
- Extend `MarketDataProvider` with `_adxService`, `setAdxService`, and `_prewarmDailyAdx(...)`.
- In `forceRefetchDailyBars(...)`, invoke ADX prewarm inside stage `3/4 计算指标...`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "3/4 计算指标"`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/main.dart lib/providers/market_data_provider.dart test/screens/data_management_screen_test.dart
git commit -m "feat: wire adx service into app and daily indicator prewarm"
```

### Task 5: Add ADX Settings Screen and Data Management Entries

**Files:**
- Create: `lib/screens/adx_settings_screen.dart`
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('数据管理页应提供日线和周线ADX参数入口并可分别打开页面', ...);
testWidgets('日线ADX设置页应支持触发日线重算', ...);
testWidgets('周线ADX设置页应支持触发周线重算', ...);
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "ADX"`
Expected: FAIL due to missing ADX entries/screen.

**Step 3: Write minimal implementation**

- Create ADX settings UI mirroring MACD style:
  - editable `period`, `threshold`
  - `重算日线ADX` / `重算周线ADX`
  - progress dialog with speed/ETA label
- Add Data Management entries:
  - `日线ADX参数设置`
  - `周线ADX参数设置`

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "ADX"`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/adx_settings_screen.dart lib/screens/data_management_screen.dart test/screens/data_management_screen_test.dart
git commit -m "feat: add adx settings and recompute entry in data management"
```

### Task 6: Add Weekly ADX Prewarm in Weekly Sync Flow

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('周K拉取缺失后应触发周线ADX预热', ...);
testWidgets('周K拉取缺失无新增记录时应跳过周线ADX预热', ...);
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "周线ADX预热"`
Expected: FAIL.

**Step 3: Write minimal implementation**

- In `_fetchWeeklyKline(...)`, add ADX prewarm branch parallel to weekly MACD prewarm.
- Reuse same effective stock scope selection and progress presentation.

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "周线ADX预热"`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart test/screens/data_management_screen_test.dart
git commit -m "feat: add weekly adx prewarm after weekly sync"
```

### Task 7: Add ADX Subchart Widget and Tests

**Files:**
- Create: `lib/widgets/adx_subchart.dart`
- Create: `test/widgets/adx_subchart_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('shows cache-miss hint when adx cache does not exist', ...);
testWidgets('renders adx + di lines for visible bars', ...);
testWidgets('renders threshold reference line', ...);
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/adx_subchart_test.dart`
Expected: FAIL due to missing widget/painter.

**Step 3: Write minimal implementation**

- Implement `AdxSubChart extends KLineSubChart`:
  - loads cache via `AdxCacheStore`
  - aligns points by date with viewport
  - shows info row (`ADX/+DI/-DI`) and threshold line
  - draws three lines in painter

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/adx_subchart_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/adx_subchart.dart test/widgets/adx_subchart_test.dart
git commit -m "feat: add adx subchart widget"
```

### Task 8: Integrate ADX Subchart into Stock Detail and Linked View

**Files:**
- Modify: `lib/screens/stock_detail_screen.dart`
- Modify: `lib/widgets/linked_dual_kline_view.dart`
- Modify: `test/screens/stock_detail_screen_test.dart`
- Modify: `test/widgets/linked_dual_kline_view_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('daily mode displays stacked MACD and ADX subcharts', ...);
testWidgets('weekly mode displays stacked MACD and ADX subcharts', ...);
testWidgets('linked mode displays MACD+ADX subcharts in weekly and daily panes', ...);
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/stock_detail_screen_test.dart test/widgets/linked_dual_kline_view_test.dart`
Expected: FAIL because ADX subcharts are not present.

**Step 3: Write minimal implementation**

- Add ADX cache injection props for tests.
- In non-linked daily/weekly chart, stack `MacdSubChart` + `AdxSubChart`.
- In linked view, add ADX subchart per pane.

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/stock_detail_screen_test.dart test/widgets/linked_dual_kline_view_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/stock_detail_screen.dart lib/widgets/linked_dual_kline_view.dart test/screens/stock_detail_screen_test.dart test/widgets/linked_dual_kline_view_test.dart
git commit -m "feat: show adx subcharts in stock detail"
```

### Task 9: Full Verification and Cleanup

**Files:**
- Modify (if needed): `README.md` (only if ADX user-facing workflow docs are missing)

**Step 1: Run focused suites**

Run:

```bash
flutter test test/models/adx_config_test.dart test/models/adx_point_test.dart
flutter test test/data/storage/adx_cache_store_test.dart
flutter test test/services/adx_indicator_service_test.dart
flutter test test/widgets/adx_subchart_test.dart
flutter test test/screens/data_management_screen_test.dart --plain-name "ADX"
flutter test test/screens/stock_detail_screen_test.dart
flutter test test/widgets/linked_dual_kline_view_test.dart
```

Expected: all PASS.

**Step 2: Run broader regression for touched areas**

Run:

```bash
flutter test test/services/macd_indicator_service_test.dart
flutter test test/widgets/macd_subchart_test.dart
```

Expected: PASS (no regression).

**Step 3: Final status checks**

Run:

```bash
git status --short
git log --oneline -n 8
```

Expected: clean working tree or only intentional doc updates.

**Step 4: Final commit (if uncommitted changes remain)**

```bash
git add -A
git commit -m "feat: complete daily-weekly adx indicator workflow"
```

