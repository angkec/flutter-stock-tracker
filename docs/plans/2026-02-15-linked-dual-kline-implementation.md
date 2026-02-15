# Linked Dual Kline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为个股详情新增 `联动` 模式（上周K、下日K），实现双向时间映射与同步价格横线，支持长按联动与自动纵轴对齐。

**Architecture:** 在 `StockDetailScreen` 增加 `ChartMode.linked`，由新组件 `LinkedDualKlineView` 承担双图布局与状态协同。联动状态通过轻量协调器管理，`KLineChart` 做最小增量扩展（外部联动状态输入 + 触摸事件输出），保持现有日线/周线模式行为不变。所有时间/价格映射下沉到纯函数工具，先单测后接 UI。

**Tech Stack:** Flutter (`material`), Dart, `flutter_test`, 现有 `KLineChart` 与 `StockDetailScreen` 组件体系。

---

## 执行前准备

- 推荐先使用 `@using-git-worktrees` 创建独立 worktree，再执行本计划。
- 执行时全程遵循：`@test-driven-development`、`@systematic-debugging`、`@verification-before-completion`。
- 每个 Task 都按「先写失败测试 -> 最小实现 -> 通过测试 -> 提交」执行，避免跨任务堆叠改动。

---

### Task 1: 时间映射与联动状态模型

**Files:**
- Create: `lib/widgets/linked_crosshair_models.dart`
- Create: `lib/widgets/linked_kline_mapper.dart`
- Create: `test/support/kline_fixture_builder.dart`
- Test: `test/widgets/linked_kline_mapper_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';
import 'package:stock_rtwatcher/widgets/linked_kline_mapper.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  test('maps daily bar date to weekly bar index', () {
    final weeklyBars = buildWeeklyBars();
    final dailyBars = buildDailyBarsForTwoWeeks();

    final idx = LinkedKlineMapper.findWeeklyIndexForDailyDate(
      weeklyBars: weeklyBars,
      dailyDate: dailyBars.last.datetime,
    );

    expect(idx, 1);
  });

  test('maps weekly bar to last trading day index', () {
    final weeklyBars = buildWeeklyBars();
    final dailyBars = buildDailyBarsForTwoWeeks();

    final idx = LinkedKlineMapper.findDailyIndexForWeeklyDate(
      dailyBars: dailyBars,
      weeklyDate: weeklyBars.first.datetime,
    );

    expect(dailyBars[idx!].datetime.weekday, DateTime.friday);
  });

  test('linked state copyWith preserves untouched fields', () {
    final state = LinkedCrosshairState(
      sourcePane: LinkedPane.daily,
      anchorDate: DateTime(2026, 2, 13),
      anchorPrice: 12.34,
      isLinking: true,
    );

    final next = state.copyWith(anchorPrice: 12.88);
    expect(next.sourcePane, LinkedPane.daily);
    expect(next.anchorDate, DateTime(2026, 2, 13));
    expect(next.anchorPrice, 12.88);
    expect(next.isLinking, true);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/linked_kline_mapper_test.dart -r expanded`

Expected: FAIL with missing imports / undefined `LinkedKlineMapper` and `LinkedCrosshairState`.

**Step 3: Write minimal implementation**

```dart
// lib/widgets/linked_crosshair_models.dart
enum LinkedPane { weekly, daily }

class LinkedCrosshairState {
  final LinkedPane sourcePane;
  final DateTime anchorDate;
  final double anchorPrice;
  final bool isLinking;

  const LinkedCrosshairState({
    required this.sourcePane,
    required this.anchorDate,
    required this.anchorPrice,
    required this.isLinking,
  });

  LinkedCrosshairState copyWith({
    LinkedPane? sourcePane,
    DateTime? anchorDate,
    double? anchorPrice,
    bool? isLinking,
  }) {
    return LinkedCrosshairState(
      sourcePane: sourcePane ?? this.sourcePane,
      anchorDate: anchorDate ?? this.anchorDate,
      anchorPrice: anchorPrice ?? this.anchorPrice,
      isLinking: isLinking ?? this.isLinking,
    );
  }
}

// lib/widgets/linked_kline_mapper.dart
class LinkedKlineMapper {
  static int? findWeeklyIndexForDailyDate({
    required List<KLine> weeklyBars,
    required DateTime dailyDate,
  }) { /* week bucket compare */ }

  static int? findDailyIndexForWeeklyDate({
    required List<KLine> dailyBars,
    required DateTime weeklyDate,
  }) { /* same week + latest date */ }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/linked_kline_mapper_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add test/support/kline_fixture_builder.dart \
  test/widgets/linked_kline_mapper_test.dart \
  lib/widgets/linked_crosshair_models.dart \
  lib/widgets/linked_kline_mapper.dart
git commit -m "feat: add linked kline mapping primitives"
```

---

### Task 2: 同步价格横线的自动纵轴对齐算法

**Files:**
- Modify: `lib/widgets/linked_kline_mapper.dart`
- Test: `test/widgets/linked_price_range_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/linked_kline_mapper.dart';

void main() {
  test('keeps range unchanged when anchor in range', () {
    final range = LinkedKlineMapper.ensurePriceVisible(
      minPrice: 10,
      maxPrice: 15,
      anchorPrice: 12,
      paddingRatio: 0.08,
    );
    expect(range.minPrice, 10);
    expect(range.maxPrice, 15);
  });

  test('expands range when anchor below min', () {
    final range = LinkedKlineMapper.ensurePriceVisible(
      minPrice: 10,
      maxPrice: 15,
      anchorPrice: 8,
      paddingRatio: 0.08,
    );
    expect(range.minPrice, lessThanOrEqualTo(8));
    expect(range.maxPrice, greaterThan(15));
  });

  test('expands range when anchor above max', () {
    final range = LinkedKlineMapper.ensurePriceVisible(
      minPrice: 10,
      maxPrice: 15,
      anchorPrice: 18,
      paddingRatio: 0.08,
    );
    expect(range.maxPrice, greaterThanOrEqualTo(18));
    expect(range.minPrice, lessThan(10));
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/linked_price_range_test.dart -r expanded`

Expected: FAIL with undefined method `ensurePriceVisible`.

**Step 3: Write minimal implementation**

```dart
class PriceRange {
  final double minPrice;
  final double maxPrice;
  const PriceRange(this.minPrice, this.maxPrice);
}

static PriceRange ensurePriceVisible({
  required double minPrice,
  required double maxPrice,
  required double anchorPrice,
  double paddingRatio = 0.08,
  double minSpan = 0.01,
}) {
  if (anchorPrice >= minPrice && anchorPrice <= maxPrice) {
    return PriceRange(minPrice, maxPrice);
  }
  final newMin = anchorPrice < minPrice ? anchorPrice : minPrice;
  final newMax = anchorPrice > maxPrice ? anchorPrice : maxPrice;
  final span = (newMax - newMin).clamp(minSpan, double.infinity);
  final padding = span * paddingRatio;
  return PriceRange(newMin - padding, newMax + padding);
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/linked_price_range_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add test/widgets/linked_price_range_test.dart lib/widgets/linked_kline_mapper.dart
git commit -m "feat: add linked price auto-fit range helper"
```

---

### Task 3: 扩展 KLineChart 联动输入输出能力

**Files:**
- Modify: `lib/widgets/kline_chart.dart`
- Modify: `lib/widgets/linked_crosshair_models.dart`
- Test: `test/widgets/kline_chart_linked_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  testWidgets('emits linked touch events during long press move', (tester) async {
    final events = <LinkedTouchEvent>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KLineChart(
            key: const ValueKey('chart'),
            bars: buildDailyBarsForTwoWeeks(),
            linkedPane: LinkedPane.daily,
            onLinkedTouchEvent: events.add,
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const ValueKey('chart')));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(20, -30));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(events.where((e) => e.phase == LinkedTouchPhase.update), isNotEmpty);
    expect(events.last.phase, LinkedTouchPhase.end);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/kline_chart_linked_test.dart -r expanded`

Expected: FAIL with unknown named parameters `linkedPane` / `onLinkedTouchEvent`.

**Step 3: Write minimal implementation**

```dart
// linked_crosshair_models.dart
enum LinkedTouchPhase { start, update, end }

class LinkedTouchEvent {
  final LinkedPane pane;
  final LinkedTouchPhase phase;
  final DateTime date;
  final double price;
  final int barIndex;
  const LinkedTouchEvent({
    required this.pane,
    required this.phase,
    required this.date,
    required this.price,
    required this.barIndex,
  });
}

// kline_chart.dart (新增可选参数)
final LinkedPane? linkedPane;
final ValueChanged<LinkedTouchEvent>? onLinkedTouchEvent;
final LinkedCrosshairState? externalLinkedState;

// 在 _handleTouch 中回调 update 事件，在长按开始/结束回调 start/end。
// 在 painter 中根据 externalLinkedState 额外绘制横向价格线。
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/kline_chart_linked_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add test/widgets/kline_chart_linked_test.dart \
  lib/widgets/kline_chart.dart \
  lib/widgets/linked_crosshair_models.dart
git commit -m "feat: add linked touch event hooks to kline chart"
```

---

### Task 4: 实现联动协调器与双图容器

**Files:**
- Create: `lib/widgets/linked_crosshair_coordinator.dart`
- Create: `lib/widgets/linked_dual_kline_view.dart`
- Test: `test/widgets/linked_crosshair_coordinator_test.dart`
- Test: `test/widgets/linked_dual_kline_view_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_coordinator.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  test('coordinator maps weekly touch to daily last-trading-day index', () {
    final coordinator = LinkedCrosshairCoordinator(
      weeklyBars: buildWeeklyBars(),
      dailyBars: buildDailyBarsForTwoWeeks(),
    );

    coordinator.handleTouch(
      const LinkedTouchEvent(
        pane: LinkedPane.weekly,
        phase: LinkedTouchPhase.update,
        date: DateTime(2026, 2, 13),
        price: 12.5,
        barIndex: 1,
      ),
    );

    expect(coordinator.value?.sourcePane, LinkedPane.weekly);
    expect(coordinator.mappedDailyIndex, isNotNull);
  });
}
```

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/widgets/linked_dual_kline_view.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  testWidgets('renders weekly and daily charts in linked mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkedDualKlineView(
            weeklyBars: buildWeeklyBars(),
            dailyBars: buildDailyBarsForTwoWeeks(),
            ratios: const [],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('linked_weekly_chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('linked_daily_chart')), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/linked_crosshair_coordinator_test.dart test/widgets/linked_dual_kline_view_test.dart -r expanded`

Expected: FAIL with missing classes/components.

**Step 3: Write minimal implementation**

```dart
class LinkedCrosshairCoordinator extends ValueNotifier<LinkedCrosshairState?> {
  final List<KLine> weeklyBars;
  final List<KLine> dailyBars;
  int? mappedWeeklyIndex;
  int? mappedDailyIndex;

  LinkedCrosshairCoordinator({
    required this.weeklyBars,
    required this.dailyBars,
  }) : super(null);

  void handleTouch(LinkedTouchEvent event) {
    if (event.phase == LinkedTouchPhase.end) {
      value = null;
      return;
    }
    value = LinkedCrosshairState(
      sourcePane: event.pane,
      anchorDate: event.date,
      anchorPrice: event.price,
      isLinking: true,
    );
    mappedWeeklyIndex = ...;
    mappedDailyIndex = ...;
  }
}
```

```dart
class LinkedDualKlineView extends StatefulWidget {
  // weeklyBars, dailyBars, ratios
}

// build():
// 1) 顶部状态条（联动中 + 价格）
// 2) Expanded(flex: 42) 周K图
// 3) SizedBox(height: 10)
// 4) Expanded(flex: 58) 日K图
// 两个 KLineChart 通过 coordinator 同步 externalLinkedState
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/linked_crosshair_coordinator_test.dart test/widgets/linked_dual_kline_view_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/linked_crosshair_coordinator.dart \
  lib/widgets/linked_dual_kline_view.dart \
  test/widgets/linked_crosshair_coordinator_test.dart \
  test/widgets/linked_dual_kline_view_test.dart
git commit -m "feat: implement linked dual kline coordinator and view"
```

---

### Task 5: 抽离可测试的图表面板并接入联动模式

**Files:**
- Create: `lib/widgets/stock_detail_chart_panel.dart`
- Modify: `lib/screens/stock_detail_screen.dart`
- Test: `test/widgets/stock_detail_chart_panel_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/screens/stock_detail_screen.dart';
import 'package:stock_rtwatcher/widgets/stock_detail_chart_panel.dart';

import '../support/kline_fixture_builder.dart';

void main() {
  testWidgets('shows linked segment and renders linked view when selected', (tester) async {
    ChartMode mode = ChartMode.linked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockDetailChartPanel(
            chartMode: mode,
            onModeChanged: (next) => mode = next,
            isLoadingKLine: false,
            isLoadingRatio: false,
            klineError: null,
            ratioError: null,
            todayBars: const [],
            preClose: 10,
            dailyBars: buildDailyBarsForTwoWeeks(),
            weeklyBars: buildWeeklyBars(),
            ratios: const [],
            markedIndices: const {},
            nearMissIndices: const {},
            getDetectionResult: (_) => null,
            onRetryKline: () {},
            onRetryRatio: () {},
            onScaling: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('联动'), findsOneWidget);
    expect(find.byKey(const ValueKey('linked_dual_kline_view')), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/stock_detail_chart_panel_test.dart -r expanded`

Expected: FAIL with missing `StockDetailChartPanel` and/or missing `ChartMode.linked`.

**Step 3: Write minimal implementation**

```dart
// stock_detail_screen.dart
enum ChartMode { minute, daily, weekly, linked }

// stock_detail_chart_panel.dart
class StockDetailChartPanel extends StatelessWidget {
  // 接收原 _buildKLineSection / _buildChart 所有必要参数
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SegmentedButton<ChartMode>(
          segments: const [
            ButtonSegment(value: ChartMode.minute, label: Text('分时')),
            ButtonSegment(value: ChartMode.daily, label: Text('日线')),
            ButtonSegment(value: ChartMode.weekly, label: Text('周线')),
            ButtonSegment(value: ChartMode.linked, label: Text('联动')),
          ],
          selected: {chartMode},
          onSelectionChanged: (set) => onModeChanged(set.first),
        ),
        if (chartMode == ChartMode.linked)
          LinkedDualKlineView(
            key: const ValueKey('linked_dual_kline_view'),
            weeklyBars: weeklyBars,
            dailyBars: dailyBars,
            ratios: ratios,
          )
        else
          // 原有 minute / daily / weekly 分支
      ],
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/stock_detail_chart_panel_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/stock_detail_chart_panel.dart \
  lib/screens/stock_detail_screen.dart \
  test/widgets/stock_detail_chart_panel_test.dart
git commit -m "feat: add linked mode entry in stock detail chart panel"
```

---

### Task 6: 联动模式回归验证与文档收口

**Files:**
- Modify: `docs/plans/2026-02-15-linked-dual-kline-design.md`
- Modify: `README.md` (仅新增一段“联动模式”说明，如有必要)
- Test: `test/widgets/linked_kline_mapper_test.dart`
- Test: `test/widgets/linked_price_range_test.dart`
- Test: `test/widgets/kline_chart_linked_test.dart`
- Test: `test/widgets/linked_crosshair_coordinator_test.dart`
- Test: `test/widgets/linked_dual_kline_view_test.dart`
- Test: `test/widgets/stock_detail_chart_panel_test.dart`

**Step 1: Write/adjust failing documentation expectation test (optional)**

```dart
// 若项目无 docs 测试框架，则跳过该测试步骤，直接进入 Step 2。
```

**Step 2: Run focused regression tests**

Run:

```bash
flutter test test/widgets/linked_kline_mapper_test.dart -r expanded
flutter test test/widgets/linked_price_range_test.dart -r expanded
flutter test test/widgets/kline_chart_linked_test.dart -r expanded
flutter test test/widgets/linked_crosshair_coordinator_test.dart -r expanded
flutter test test/widgets/linked_dual_kline_view_test.dart -r expanded
flutter test test/widgets/stock_detail_chart_panel_test.dart -r expanded
```

Expected: PASS all.

**Step 3: Run broader safety net**

Run: `flutter test test/widgets test/screens/industry_screen_test.dart -r compact`

Expected: PASS, no regression from shared widget/theme changes.

**Step 4: Update docs with final behavior**

```markdown
- 在设计文档补充“已实现项”与“手势说明（长按激活，松手退出）”。
- README 增加“联动模式：周K + 日K + 同步价格轨”一段简述。
```

**Step 5: Commit**

```bash
git add docs/plans/2026-02-15-linked-dual-kline-design.md README.md
git commit -m "docs: document linked dual-kline mode behavior"
```

---

## 最终验收清单（执行结束前）

1. `StockDetailScreen` 的分段按钮包含 `联动`。
2. 联动模式固定上周K/下日K，任一图长按时另一图时间同步。
3. 两图横线价格一致，且目标图在超界时自动扩轴并保持可见。
4. 松手后联动覆盖层清除，普通浏览手势恢复。
5. 新增测试全部通过，既有关键测试无回归。

