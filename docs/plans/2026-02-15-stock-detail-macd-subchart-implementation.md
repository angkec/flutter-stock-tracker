# Stock Detail MACD SubChart Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在个股详情页的日线/周线/联动模式下显示本地缓存 MACD 附图，并确保附图柱数与主图当前可见 K 线柱数严格一致。

**Architecture:** 通过新增 `KLineChartWithSubCharts` 作为主图+附图组合容器，引入 `KLineViewport` 统一表示主图可见窗口。`KLineChart` 增加 viewport 回调，`MacdSubChart` 仅消费本地缓存并按 viewport 切片渲染。`StockDetailScreen` 与 `LinkedDualKlineView` 只做组合接入，保持现有联动与数据拉取逻辑。

**Tech Stack:** Flutter, Provider, existing `KLineChart`, `MacdCacheStore`, `MacdIndicatorService`, flutter_test widget/integration tests.

---

### Task 1: Add viewport model and KLineChart viewport callback

**Files:**
- Create: `lib/widgets/kline_viewport.dart`
- Modify: `lib/widgets/kline_chart.dart`
- Test: `test/widgets/kline_chart_viewport_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('KLineChart emits initial viewport and updates after horizontal scroll', (tester) async {
  final events = <KLineViewport>[];
  await tester.pumpWidget(...KLineChart(onViewportChanged: events.add)...);
  expect(events, isNotEmpty);

  await tester.tap(find.byIcon(Icons.chevron_left));
  await tester.pump();

  expect(events.length, greaterThan(1));
  expect(events.last.startIndex, isNot(equals(events.first.startIndex)));
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/kline_chart_viewport_test.dart`
Expected: FAIL because `KLineViewport` and `onViewportChanged` do not exist.

**Step 3: Write minimal implementation**

```dart
class KLineViewport {
  final int startIndex;
  final int visibleCount;
  final int totalCount;
  int get endIndex => (startIndex + visibleCount).clamp(0, totalCount);
}
```

Add `onViewportChanged` to `KLineChart`, emit:
- once after initial layout,
- once after zoom/left-right scroll/data-reset causing viewport change.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/kline_chart_viewport_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/kline_viewport.dart lib/widgets/kline_chart.dart test/widgets/kline_chart_viewport_test.dart
git commit -m "feat: expose kline viewport updates for subcharts"
```

---

### Task 2: Add reusable main+subchart container and extension contract

**Files:**
- Create: `lib/widgets/kline_chart_with_subcharts.dart`
- Modify: `lib/widgets/kline_chart.dart` (if needed for pass-through)
- Test: `test/widgets/kline_chart_with_subcharts_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('forwards viewport to subchart builders', (tester) async {
  KLineViewport? captured;
  await tester.pumpWidget(
    KLineChartWithSubCharts(
      bars: bars,
      subCharts: [
        BuilderSubChart(onViewport: (vp) => captured = vp),
      ],
    ),
  );
  expect(captured, isNotNull);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/kline_chart_with_subcharts_test.dart`
Expected: FAIL because container/contract do not exist.

**Step 3: Write minimal implementation**

- Introduce `abstract class KLineSubChart`.
- `KLineChartWithSubCharts` renders:
  - `KLineChart` (main),
  - each `KLineSubChart` below, passing current `KLineViewport`.
- Keep old `KLineChart` props available via pass-through fields.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/kline_chart_with_subcharts_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/kline_chart_with_subcharts.dart test/widgets/kline_chart_with_subcharts_test.dart
git commit -m "feat: add reusable kline with subcharts container"
```

---

### Task 3: Implement MACD subchart from local cache only

**Files:**
- Create: `lib/widgets/macd_subchart.dart`
- Test: `test/widgets/macd_subchart_test.dart`

**Step 1: Write the failing tests**

```dart
testWidgets('shows cache-miss hint when no cached MACD exists', ...);
testWidgets('renders same number of MACD points as current viewport bars', ...);
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/macd_subchart_test.dart`
Expected: FAIL because `MacdSubChart` does not exist.

**Step 3: Write minimal implementation**

- `MacdSubChart` reads from `MacdCacheStore.loadSeries(stockCode, dataType)`.
- Never calls `MacdIndicatorService.getOrCompute...`.
- Align MACD points by trading date to incoming bars.
- Slice by viewport range (`startIndex` to `endIndex`).
- Render simple custom paint (HIST bars + DIF/DEA lines) in fixed height.
- Empty state text: `暂无MACD缓存，请先在数据管理同步`.

**Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/macd_subchart_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/macd_subchart.dart test/widgets/macd_subchart_test.dart
git commit -m "feat: add local-cache-only MACD subchart"
```

---

### Task 4: Wire StockDetail daily/weekly modes to new container

**Files:**
- Modify: `lib/screens/stock_detail_screen.dart`
- Test: `test/screens/stock_detail_screen_test.dart` (create if missing)

**Step 1: Write the failing tests**

```dart
testWidgets('daily mode displays MACD subchart section', ...);
testWidgets('weekly mode displays MACD subchart section', ...);
```

**Step 2: Run tests to verify they fail**

Run: `flutter test test/screens/stock_detail_screen_test.dart`
Expected: FAIL because stock detail does not render MACD subchart.

**Step 3: Write minimal implementation**

- In `_buildChart`, replace direct `KLineChart` for daily/weekly with `KLineChartWithSubCharts`.
- Inject one `MacdSubChart` configured by:
  - daily mode => `KLineDataType.daily`
  - weekly mode => `KLineDataType.weekly`
- Keep minute mode unchanged.

**Step 4: Run tests to verify they pass**

Run: `flutter test test/screens/stock_detail_screen_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/stock_detail_screen.dart test/screens/stock_detail_screen_test.dart
git commit -m "feat: show cached macd subchart in stock detail daily and weekly"
```

---

### Task 5: Wire linked mode with both weekly and daily MACD subcharts

**Files:**
- Modify: `lib/widgets/linked_dual_kline_view.dart`
- Modify: `test/widgets/linked_dual_kline_view_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('linked mode renders weekly and daily MACD subcharts', (tester) async {
  await tester.pumpWidget(...LinkedDualKlineView(...));
  expect(find.byKey(const ValueKey('linked_weekly_macd_subchart')), findsOneWidget);
  expect(find.byKey(const ValueKey('linked_daily_macd_subchart')), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/linked_dual_kline_view_test.dart`
Expected: FAIL because linked view does not render MACD subcharts.

**Step 3: Write minimal implementation**

- Replace each inner `KLineChart` with `KLineChartWithSubCharts`.
- Weekly panel attach weekly `MacdSubChart`.
- Daily panel attach daily `MacdSubChart`.
- Preserve linked crosshair coordinator wiring.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/linked_dual_kline_view_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/linked_dual_kline_view.dart test/widgets/linked_dual_kline_view_test.dart
git commit -m "feat: show weekly and daily macd subcharts in linked mode"
```

---

### Task 6: Regression verification and cleanup

**Files:**
- Modify: (if needed) `test/widgets/kline_chart_linked_test.dart`
- Modify: (if needed) `test/screens/industry_detail_screen_test.dart` (only if side effects appear)

**Step 1: Run focused suite**

Run:
- `flutter test test/widgets/kline_chart_viewport_test.dart`
- `flutter test test/widgets/kline_chart_with_subcharts_test.dart`
- `flutter test test/widgets/macd_subchart_test.dart`
- `flutter test test/screens/stock_detail_screen_test.dart`
- `flutter test test/widgets/linked_dual_kline_view_test.dart`

Expected: all PASS.

**Step 2: Run broader safety suite**

Run:
- `flutter test test/widgets/kline_chart_linked_test.dart`
- `flutter test test/screens/data_management_screen_test.dart --plain-name "周K"`

Expected: PASS and no regressions in linked touch / weekly sync behavior.

**Step 3: Final full verification (time permitting)**

Run: `flutter test`
Expected: all pass, or only pre-existing unrelated failures.

**Step 4: Final commit**

```bash
git add lib/widgets/*.dart lib/screens/stock_detail_screen.dart test/widgets/*.dart test/screens/stock_detail_screen_test.dart docs/plans/2026-02-15-stock-detail-macd-subchart-design.md docs/plans/2026-02-15-stock-detail-macd-subchart-implementation.md
git commit -m "feat: add cached macd subcharts for stock detail charts"
```
