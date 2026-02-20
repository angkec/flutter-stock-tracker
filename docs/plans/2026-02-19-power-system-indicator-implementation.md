# Power System Indicator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a new cache-backed Power System indicator (daily + weekly) with Data Management entry/recompute and stock-detail candle coloring from cache only.

**Architecture:** Follow existing EMA/MACD/ADX pattern: file cache store + indicator service prewarm/recompute + Data Management settings entry. Add an optional per-candle color resolver to `KLineChart` so stock detail and linked views can color candles red/green/blue using cached Power System state while preserving existing red/green fallback when no cache exists.

**Tech Stack:** Flutter, Provider, ChangeNotifier, Dart file storage under `market_data/klines`, widget tests with `flutter_test`.

---

### Task 1: Add Power System domain models and cache store

**Files:**
- Create: `lib/models/power_system_point.dart`
- Create: `lib/data/storage/power_system_cache_store.dart`
- Test: `test/data/storage/power_system_cache_store_test.dart`

**Step 1: Write the failing test**

```dart
test('save/load power system cache series for daily and weekly', () async {
  // Arrange cache store + series
  // Act saveSeries then loadSeries
  // Assert points survive with datetime + state fields
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/power_system_cache_store_test.dart`
Expected: FAIL (new classes/files missing)

**Step 3: Write minimal implementation**

```dart
class PowerSystemPoint {
  final DateTime datetime;
  final int state; // 1=red, -1=green, 0=blue
}

class PowerSystemCacheStore {
  Future<void> saveSeries(...)
  Future<PowerSystemCacheSeries?> loadSeries(...)
}
```

Use same serialization and file naming style as `ema_cache_store.dart`/`macd_cache_store.dart`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/power_system_cache_store_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/models/power_system_point.dart lib/data/storage/power_system_cache_store.dart test/data/storage/power_system_cache_store_test.dart
git commit -m "feat: add power system cache model and store"
```

### Task 2: Add Power System indicator service with repository prewarm

**Files:**
- Create: `lib/services/power_system_indicator_service.dart`
- Test: `test/services/power_system_indicator_service_test.dart`

**Step 1: Write the failing tests**

```dart
test('computes red when ema slope up and macd slope up', () async {});
test('computes green when ema slope down and macd slope down', () async {});
test('computes blue when slopes diverge', () async {});
test('prewarmFromRepository writes cache for stock scope and data type', () async {});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/power_system_indicator_service_test.dart`
Expected: FAIL (service missing)

**Step 3: Write minimal implementation**

```dart
class PowerSystemIndicatorService extends ChangeNotifier {
  Future<List<PowerSystemPoint>> getOrComputeFromBars(...)
  Future<void> prewarmFromRepository(...)
}
```

Rules per bar index `i` (require `i-1`):
- red: `ema[i] > ema[i-1] && macdHist[i] > macdHist[i-1]`
- green: `ema[i] < ema[i-1] && macdHist[i] < macdHist[i-1]`
- blue: otherwise when both slopes are valid and opposite
- null/insufficient bars -> no point for that candle

Use existing `EmaIndicatorService`/`MacdIndicatorService` `getOrComputeFromBars(...)` internally so no new network path.

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/power_system_indicator_service_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/services/power_system_indicator_service.dart test/services/power_system_indicator_service_test.dart
git commit -m "feat: add power system indicator service with cache prewarm"
```

### Task 3: Register service in app/provider wiring

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/providers/market_data_provider.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('data management shows power system entries when service injected', (tester) async {});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "power system"`
Expected: FAIL (no wiring/UI yet)

**Step 3: Write minimal implementation**

```dart
// main.dart
ChangeNotifierProxyProvider<DataRepository, PowerSystemIndicatorService>(...)

// market_data_provider.dart
void setPowerSystemService(PowerSystemIndicatorService service) { ... }
```

Keep it parallel to MACD/ADX/EMA wiring patterns.

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "power system"`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/main.dart lib/providers/market_data_provider.dart test/screens/data_management_screen_test.dart
git commit -m "feat: wire power system service into app providers"
```

### Task 4: Add Data Management entry + Power System settings/recompute screen

**Files:**
- Create: `lib/screens/power_system_settings_screen.dart`
- Modify: `lib/screens/data_management_screen.dart`
- Test: `test/screens/power_system_settings_screen_test.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('daily/weekly power system settings cards are shown in data management', (tester) async {});
testWidgets('power system recompute button calls prewarmFromRepository', (tester) async {});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/power_system_settings_screen_test.dart test/screens/data_management_screen_test.dart --plain-name "power"`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
// data_management_screen.dart
_buildPowerSystemSettingsItem(...)

// power_system_settings_screen.dart
FilledButton.icon(key: ValueKey('power_system_recompute_${widget.dataType.name}'), ...)
```

Requirements:
- Daily and weekly entry cards under 技术指标 section
- Recompute dialog/progress UX follows EMA/MACD style
- Recompute persists cache through `PowerSystemIndicatorService.prewarmFromRepository`

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/power_system_settings_screen_test.dart test/screens/data_management_screen_test.dart --plain-name "power"`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/screens/power_system_settings_screen.dart lib/screens/data_management_screen.dart test/screens/power_system_settings_screen_test.dart test/screens/data_management_screen_test.dart
git commit -m "feat: add power system settings and recompute entry"
```

### Task 5: Add KLine per-candle color extension point (backward compatible)

**Files:**
- Modify: `lib/widgets/kline_chart.dart`
- Modify: `lib/widgets/kline_chart_with_subcharts.dart`
- Test: `test/widgets/kline_chart_power_system_color_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('uses resolver color when provided', (tester) async {});
testWidgets('keeps original up/down colors when resolver returns null', (tester) async {});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/kline_chart_power_system_color_test.dart`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
// kline_chart.dart
final Color? Function(KLine bar, int globalIndex)? candleColorResolver;

final resolvedColor = candleColorResolver?.call(bar, startIndex + i);
// fallback to existing kUpColor/kDownColor when null
```

Propagate callback through `KLineChartWithSubCharts` without breaking existing constructors.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/kline_chart_power_system_color_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/widgets/kline_chart.dart lib/widgets/kline_chart_with_subcharts.dart test/widgets/kline_chart_power_system_color_test.dart
git commit -m "feat: support optional per-candle color resolver"
```

### Task 6: Load Power System cache in stock detail/linked view and apply colors

**Files:**
- Modify: `lib/screens/stock_detail_screen.dart`
- Modify: `lib/widgets/linked_dual_kline_view.dart`
- Modify: `lib/widgets/kline_chart_with_subcharts.dart`
- Create: `lib/widgets/power_system_candle_color.dart`
- Test: `test/screens/stock_detail_screen_test.dart`
- Test: `test/widgets/linked_dual_kline_view_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('stock detail applies cached power system colors when cache exists', (tester) async {});
testWidgets('stock detail keeps default colors when power system cache missing', (tester) async {});
testWidgets('linked daily/weekly use their own power system cache series', (tester) async {});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/stock_detail_screen_test.dart test/widgets/linked_dual_kline_view_test.dart --plain-name "power"`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
// stock_detail_screen.dart and linked_dual_kline_view.dart
await powerSystemCacheStore.loadSeries(stockCode: code, dataType: ...)
// build date-indexed map and pass resolver into KLineChartWithSubCharts
```

Resolver behavior:
- use cached state red/green/blue only when point exists for that candle date
- no cached point: return null to keep original up/down color

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/stock_detail_screen_test.dart test/widgets/linked_dual_kline_view_test.dart --plain-name "power"`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/screens/stock_detail_screen.dart lib/widgets/linked_dual_kline_view.dart lib/widgets/power_system_candle_color.dart test/screens/stock_detail_screen_test.dart test/widgets/linked_dual_kline_view_test.dart
git commit -m "feat: render stock detail candles from power system cache"
```

### Task 7: Add weekly sync prewarm integration for Power System

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `lib/providers/market_data_provider.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('weekly sync also prewarms power system cache', (tester) async {});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "power system cache"`
Expected: FAIL

**Step 3: Write minimal implementation**

```dart
await powerSystemService.prewarmFromRepository(
  stockCodes: effectivePrewarmStockCodes,
  dataType: KLineDataType.weekly,
  dateRange: dateRange,
)
```

Keep progress UI stage labels consistent with existing weekly indicator prewarm blocks.

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "power system cache"`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart lib/providers/market_data_provider.dart test/screens/data_management_screen_test.dart
git commit -m "feat: include power system prewarm in weekly sync"
```

### Task 8: Full verification and regression sweep

**Files:**
- Verify only

**Step 1: Run targeted suite**

Run:

```bash
flutter test test/data/storage/power_system_cache_store_test.dart
flutter test test/services/power_system_indicator_service_test.dart
flutter test test/screens/power_system_settings_screen_test.dart
flutter test test/widgets/kline_chart_power_system_color_test.dart
flutter test test/screens/stock_detail_screen_test.dart --plain-name "power"
flutter test test/widgets/linked_dual_kline_view_test.dart --plain-name "power"
flutter test test/screens/data_management_screen_test.dart --plain-name "power"
```

Expected: All PASS

**Step 2: Run broader safety checks**

Run:

```bash
flutter test test/widgets/kline_chart_ema_test.dart
flutter test test/screens/ema_settings_screen_test.dart
flutter test test/screens/data_management_screen_test.dart
```

Expected: PASS, no regressions on existing indicator pages

**Step 3: Final diagnostics**

Run LSP diagnostics for changed Dart files and ensure no new errors.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add cache-backed power system indicator for data management and stock detail"
```
