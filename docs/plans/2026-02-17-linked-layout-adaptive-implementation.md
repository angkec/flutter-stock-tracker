# Linked Layout Adaptive Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace fixed linked-chart height math in stock detail with a configurable adaptive layout solver that keeps both panes and all fixed subcharts readable.

**Architecture:** Introduce a global linked-layout config model + config service (SharedPreferences-backed), then compute pane/subchart heights with a generic solver based on available height and subchart count. Integrate solver output into `StockDetailScreen` and `LinkedDualKlineView`, and add a stock-detail top-right debug bottom sheet for runtime tuning/reset.

**Tech Stack:** Flutter, Provider, SharedPreferences, flutter_test (unit + widget tests), existing `KLineChartWithSubCharts`/linked crosshair widgets.

---

## Execution Notes

- Follow `@superpowers:test-driven-development` strictly on every task (red -> green -> refactor).
- Use a dedicated worktree branch before execution (`@superpowers:using-git-worktrees`).
- Keep commits small: one commit per task.
- Before claiming completion, run `@superpowers:verification-before-completion` checks.

### Task 1: Add Layout Models and Solver (Core Algorithm)

**Files:**
- Create: `lib/models/linked_layout_config.dart`
- Create: `lib/models/linked_layout_result.dart`
- Create: `lib/services/linked_layout_solver.dart`
- Test: `test/services/linked_layout_solver_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/linked_layout_config.dart';
import 'package:stock_rtwatcher/services/linked_layout_solver.dart';

void main() {
  test('keeps both pane main charts above minimum in balanced defaults', () {
    const config = LinkedLayoutConfig.balanced();
    final result = LinkedLayoutSolver.resolve(
      availableHeight: 560,
      topSubchartCount: 2,
      bottomSubchartCount: 2,
      config: config,
    );

    expect(result.top.mainChartHeight, greaterThanOrEqualTo(config.mainMinHeight));
    expect(result.bottom.mainChartHeight, greaterThanOrEqualTo(config.mainMinHeight));
  });

  test('scales to 5 fixed subcharts and preserves minimum readable heights', () {
    const config = LinkedLayoutConfig.balanced();
    final result = LinkedLayoutSolver.resolve(
      availableHeight: 720,
      topSubchartCount: 5,
      bottomSubchartCount: 5,
      config: config,
    );

    expect(result.top.subchartHeights.length, 5);
    expect(result.bottom.subchartHeights.length, 5);
    expect(result.top.subchartHeights.every((h) => h >= config.subMinHeight), isTrue);
    expect(result.bottom.subchartHeights.every((h) => h >= config.subMinHeight), isTrue);
  });

  test('clamps container height to config bounds', () {
    const config = LinkedLayoutConfig.balanced(
      containerMinHeight: 640,
      containerMaxHeight: 840,
    );

    final tiny = LinkedLayoutSolver.resolve(
      availableHeight: 300,
      topSubchartCount: 2,
      bottomSubchartCount: 2,
      config: config,
    );
    final huge = LinkedLayoutSolver.resolve(
      availableHeight: 2000,
      topSubchartCount: 2,
      bottomSubchartCount: 2,
      config: config,
    );

    expect(tiny.containerHeight, greaterThanOrEqualTo(640));
    expect(huge.containerHeight, lessThanOrEqualTo(840));
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/linked_layout_solver_test.dart --reporter compact`
Expected: FAIL (missing `LinkedLayoutConfig`, `LinkedLayoutSolver`, and result types).

**Step 3: Write minimal implementation**

```dart
// lib/models/linked_layout_config.dart
class LinkedLayoutConfig {
  final double mainMinHeight;
  final double mainIdealHeight;
  final double subMinHeight;
  final double subIdealHeight;
  final double infoBarHeight;
  final double subchartSpacing;
  final double paneGap;
  final int topPaneWeight;
  final int bottomPaneWeight;
  final double containerMinHeight;
  final double containerMaxHeight;

  const LinkedLayoutConfig({
    required this.mainMinHeight,
    required this.mainIdealHeight,
    required this.subMinHeight,
    required this.subIdealHeight,
    required this.infoBarHeight,
    required this.subchartSpacing,
    required this.paneGap,
    required this.topPaneWeight,
    required this.bottomPaneWeight,
    required this.containerMinHeight,
    required this.containerMaxHeight,
  });

  const LinkedLayoutConfig.balanced({
    this.mainMinHeight = 92,
    this.mainIdealHeight = 120,
    this.subMinHeight = 52,
    this.subIdealHeight = 78,
    this.infoBarHeight = 24,
    this.subchartSpacing = 10,
    this.paneGap = 10,
    this.topPaneWeight = 42,
    this.bottomPaneWeight = 58,
    this.containerMinHeight = 640,
    this.containerMaxHeight = 840,
  });

  LinkedLayoutConfig normalize() {
    double safe(double value, double fallback) => value.isFinite && value > 0 ? value : fallback;
    return LinkedLayoutConfig(
      mainMinHeight: safe(mainMinHeight, 92),
      mainIdealHeight: safe(mainIdealHeight, 120),
      subMinHeight: safe(subMinHeight, 52),
      subIdealHeight: safe(subIdealHeight, 78),
      infoBarHeight: safe(infoBarHeight, 24),
      subchartSpacing: safe(subchartSpacing, 10),
      paneGap: safe(paneGap, 10),
      topPaneWeight: topPaneWeight <= 0 ? 42 : topPaneWeight,
      bottomPaneWeight: bottomPaneWeight <= 0 ? 58 : bottomPaneWeight,
      containerMinHeight: safe(containerMinHeight, 640),
      containerMaxHeight: safe(containerMaxHeight, 840),
    );
  }

  LinkedLayoutConfig copyWith({
    double? mainMinHeight,
    double? mainIdealHeight,
    double? subMinHeight,
    double? subIdealHeight,
    double? infoBarHeight,
    double? subchartSpacing,
    double? paneGap,
    int? topPaneWeight,
    int? bottomPaneWeight,
    double? containerMinHeight,
    double? containerMaxHeight,
  }) {
    return LinkedLayoutConfig(
      mainMinHeight: mainMinHeight ?? this.mainMinHeight,
      mainIdealHeight: mainIdealHeight ?? this.mainIdealHeight,
      subMinHeight: subMinHeight ?? this.subMinHeight,
      subIdealHeight: subIdealHeight ?? this.subIdealHeight,
      infoBarHeight: infoBarHeight ?? this.infoBarHeight,
      subchartSpacing: subchartSpacing ?? this.subchartSpacing,
      paneGap: paneGap ?? this.paneGap,
      topPaneWeight: topPaneWeight ?? this.topPaneWeight,
      bottomPaneWeight: bottomPaneWeight ?? this.bottomPaneWeight,
      containerMinHeight: containerMinHeight ?? this.containerMinHeight,
      containerMaxHeight: containerMaxHeight ?? this.containerMaxHeight,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mainMinHeight': mainMinHeight,
      'mainIdealHeight': mainIdealHeight,
      'subMinHeight': subMinHeight,
      'subIdealHeight': subIdealHeight,
      'infoBarHeight': infoBarHeight,
      'subchartSpacing': subchartSpacing,
      'paneGap': paneGap,
      'topPaneWeight': topPaneWeight,
      'bottomPaneWeight': bottomPaneWeight,
      'containerMinHeight': containerMinHeight,
      'containerMaxHeight': containerMaxHeight,
    };
  }

  factory LinkedLayoutConfig.fromJson(Map<String, dynamic> json) {
    return LinkedLayoutConfig(
      mainMinHeight: (json['mainMinHeight'] as num?)?.toDouble() ?? 92,
      mainIdealHeight: (json['mainIdealHeight'] as num?)?.toDouble() ?? 120,
      subMinHeight: (json['subMinHeight'] as num?)?.toDouble() ?? 52,
      subIdealHeight: (json['subIdealHeight'] as num?)?.toDouble() ?? 78,
      infoBarHeight: (json['infoBarHeight'] as num?)?.toDouble() ?? 24,
      subchartSpacing: (json['subchartSpacing'] as num?)?.toDouble() ?? 10,
      paneGap: (json['paneGap'] as num?)?.toDouble() ?? 10,
      topPaneWeight: (json['topPaneWeight'] as num?)?.toInt() ?? 42,
      bottomPaneWeight: (json['bottomPaneWeight'] as num?)?.toInt() ?? 58,
      containerMinHeight: (json['containerMinHeight'] as num?)?.toDouble() ?? 640,
      containerMaxHeight: (json['containerMaxHeight'] as num?)?.toDouble() ?? 840,
    );
  }
}
```

```dart
// lib/models/linked_layout_result.dart
class LinkedPaneLayoutResult {
  final double mainChartHeight;
  final List<double> subchartHeights;

  const LinkedPaneLayoutResult({
    required this.mainChartHeight,
    required this.subchartHeights,
  });
}

class LinkedLayoutResult {
  final double containerHeight;
  final LinkedPaneLayoutResult top;
  final LinkedPaneLayoutResult bottom;

  const LinkedLayoutResult({
    required this.containerHeight,
    required this.top,
    required this.bottom,
  });
}
```

```dart
// lib/services/linked_layout_solver.dart
import 'dart:math' as math;
import 'package:stock_rtwatcher/models/linked_layout_config.dart';
import 'package:stock_rtwatcher/models/linked_layout_result.dart';

class LinkedLayoutSolver {
  static LinkedLayoutResult resolve({
    required double availableHeight,
    required int topSubchartCount,
    required int bottomSubchartCount,
    required LinkedLayoutConfig config,
  }) {
    final normalized = config.normalize();
    double requiredPaneMinHeight(int subchartCount) {
      final subCount = math.max(0, subchartCount);
      return normalized.mainMinHeight +
          (subCount * normalized.subMinHeight) +
          (subCount * normalized.subchartSpacing);
    }

    final requiredContainer = normalized.infoBarHeight +
        normalized.paneGap +
        requiredPaneMinHeight(topSubchartCount) +
        requiredPaneMinHeight(bottomSubchartCount);

    final effectiveMinContainer = math.max(normalized.containerMinHeight, requiredContainer);
    final container = availableHeight
        .clamp(effectiveMinContainer, normalized.containerMaxHeight)
        .toDouble();

    final panesAvailable = math.max(0.0, container - normalized.infoBarHeight - normalized.paneGap);
    final totalWeight = normalized.topPaneWeight + normalized.bottomPaneWeight;

    final topPaneHeight = panesAvailable * normalized.topPaneWeight / totalWeight;
    final bottomPaneHeight = panesAvailable * normalized.bottomPaneWeight / totalWeight;

    LinkedPaneLayoutResult buildPane(double paneHeight, int subCount) {
      final spacingTotal = math.max(0, subCount) * normalized.subchartSpacing;
      final subMinTotal = math.max(0, subCount) * normalized.subMinHeight;
      final baseline = normalized.mainMinHeight + subMinTotal + spacingTotal;
      final extra = math.max(0.0, paneHeight - baseline);
      final mainExtraTarget = math.max(0.0, normalized.mainIdealHeight - normalized.mainMinHeight);
      final resolvedMain = normalized.mainMinHeight + math.min(extra, mainExtraTarget);

      final leftover = math.max(0.0, extra - mainExtraTarget);
      final subCountSafe = math.max(0, subCount);
      final perSubExtra = subCountSafe == 0 ? 0.0 : leftover / subCountSafe;
      final resolvedSub = List<double>.generate(
        subCountSafe,
        (_) => math.min(normalized.subIdealHeight, normalized.subMinHeight + perSubExtra),
        growable: false,
      );

      // If max container is too small to satisfy minima, keep a hard floor for visibility.
      final safeMain = paneHeight < baseline ? math.max(56.0, paneHeight * 0.3) : resolvedMain;
      return LinkedPaneLayoutResult(mainChartHeight: safeMain, subchartHeights: resolvedSub);
    }

    return LinkedLayoutResult(
      containerHeight: container,
      top: buildPane(topPaneHeight, topSubchartCount),
      bottom: buildPane(bottomPaneHeight, bottomSubchartCount),
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/linked_layout_solver_test.dart --reporter compact`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/models/linked_layout_config.dart lib/models/linked_layout_result.dart lib/services/linked_layout_solver.dart test/services/linked_layout_solver_test.dart
git commit -m "feat: add adaptive linked layout solver and models"
```

### Task 2: Add Linked Layout Config Service (Persistence + Reset)

**Files:**
- Create: `lib/services/linked_layout_config_service.dart`
- Test: `test/services/linked_layout_config_service_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/linked_layout_config.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load returns balanced defaults when no stored config exists', () async {
    final service = LinkedLayoutConfigService();
    await service.load();
    expect(service.config.mainMinHeight, 92);
    expect(service.config.subMinHeight, 52);
  });

  test('update persists values and load restores them', () async {
    final service = LinkedLayoutConfigService();
    await service.load();
    await service.update(
      const LinkedLayoutConfig.balanced(mainMinHeight: 100, subMinHeight: 60),
    );

    final another = LinkedLayoutConfigService();
    await another.load();
    expect(another.config.mainMinHeight, 100);
    expect(another.config.subMinHeight, 60);
  });

  test('resetToDefaults clears override and restores defaults', () async {
    final service = LinkedLayoutConfigService();
    await service.load();
    await service.update(const LinkedLayoutConfig.balanced(mainMinHeight: 101));
    await service.resetToDefaults();

    expect(service.config.mainMinHeight, 92);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/linked_layout_config_service_test.dart --reporter compact`
Expected: FAIL (service not found).

**Step 3: Write minimal implementation**

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/linked_layout_config.dart';

class LinkedLayoutConfigService extends ChangeNotifier {
  static const storageKey = 'linked_layout_config_v1';

  LinkedLayoutConfig _config = const LinkedLayoutConfig.balanced();
  LinkedLayoutConfig get config => _config;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        _config = const LinkedLayoutConfig.balanced();
      } else {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _config = LinkedLayoutConfig.fromJson(map).normalize();
      }
    } catch (_) {
      _config = const LinkedLayoutConfig.balanced();
    }
    notifyListeners();
  }

  Future<void> update(LinkedLayoutConfig next) async {
    _config = next.normalize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(_config.toJson()));
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    _config = const LinkedLayoutConfig.balanced();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
    notifyListeners();
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/linked_layout_config_service_test.dart --reporter compact`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/services/linked_layout_config_service.dart test/services/linked_layout_config_service_test.dart lib/models/linked_layout_config.dart
git commit -m "feat: add linked layout config persistence service"
```

### Task 3: Refactor LinkedDualKlineView to Consume Resolved Layout

**Files:**
- Modify: `lib/widgets/linked_dual_kline_view.dart`
- Test: `test/widgets/linked_dual_kline_view_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('uses injected resolved heights for weekly/daily chart and subcharts', (tester) async {
  const layout = LinkedLayoutResult(
    containerHeight: 700,
    top: LinkedPaneLayoutResult(mainChartHeight: 96, subchartHeights: [60, 60]),
    bottom: LinkedPaneLayoutResult(mainChartHeight: 130, subchartHeights: [62, 62]),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: layout.containerHeight,
          child: LinkedDualKlineView(
            stockCode: '600000',
            weeklyBars: buildWeeklyBars(),
            dailyBars: buildDailyBarsForTwoWeeks(),
            ratios: const [],
            layout: layout,
          ),
        ),
      ),
    ),
  );

  final weeklyChart = tester.widget<KLineChartWithSubCharts>(
    find.byKey(const ValueKey('linked_weekly_chart')),
  );
  final dailyChart = tester.widget<KLineChartWithSubCharts>(
    find.byKey(const ValueKey('linked_daily_chart')),
  );

  expect(weeklyChart.chartHeight, 96);
  expect(dailyChart.chartHeight, 130);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/linked_dual_kline_view_test.dart --reporter compact`
Expected: FAIL (`layout` parameter missing).

**Step 3: Write minimal implementation**

```dart
class LinkedDualKlineView extends StatefulWidget {
  const LinkedDualKlineView({
    super.key,
    required this.stockCode,
    required this.weeklyBars,
    required this.dailyBars,
    required this.ratios,
    this.layout,
    this.macdCacheStoreForTest,
    this.adxCacheStoreForTest,
  });

  final LinkedLayoutResult? layout;
}
```

```dart
final resolved = widget.layout;
final weeklyMainHeight = resolved?.top.mainChartHeight ?? /* fallback */ 90;
final weeklySubHeights = resolved?.top.subchartHeights ?? const [78.0, 78.0];
final dailyMainHeight = resolved?.bottom.mainChartHeight ?? /* fallback */ 130;
final dailySubHeights = resolved?.bottom.subchartHeights ?? const [84.0, 84.0];

return KLineChartWithSubCharts(
  chartHeight: weeklyMainHeight,
  subCharts: [
    MacdSubChart(height: weeklySubHeights[0], ...),
    AdxSubChart(height: weeklySubHeights[1], ...),
  ],
);
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/linked_dual_kline_view_test.dart --reporter compact`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/linked_dual_kline_view.dart test/widgets/linked_dual_kline_view_test.dart lib/models/linked_layout_result.dart
git commit -m "refactor: make linked dual kline view consume resolved adaptive layout"
```

### Task 4: Add Debug Bottom Sheet for Linked Layout Tuning

**Files:**
- Create: `lib/widgets/linked_layout_debug_sheet.dart`
- Test: `test/widgets/linked_layout_debug_sheet_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('updates config values and supports reset to defaults', (tester) async {
  final service = LinkedLayoutConfigService();
  await service.load();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: service,
      child: const MaterialApp(
        home: Scaffold(body: LinkedLayoutDebugSheet()),
      ),
    ),
  );

  await tester.enterText(find.byKey(const ValueKey('linked_layout_main_min_input')), '100');
  await tester.tap(find.text('应用'));
  await tester.pumpAndSettle();
  expect(service.config.mainMinHeight, 100);

  await tester.tap(find.text('恢复默认'));
  await tester.pumpAndSettle();
  expect(service.config.mainMinHeight, 92);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/linked_layout_debug_sheet_test.dart --reporter compact`
Expected: FAIL (`LinkedLayoutDebugSheet` missing).

**Step 3: Write minimal implementation**

```dart
class LinkedLayoutDebugSheet extends StatefulWidget {
  const LinkedLayoutDebugSheet({super.key});

  @override
  State<LinkedLayoutDebugSheet> createState() => _LinkedLayoutDebugSheetState();
}

class _LinkedLayoutDebugSheetState extends State<LinkedLayoutDebugSheet> {
  late final TextEditingController _mainMinController;
  late final TextEditingController _subMinController;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<LinkedLayoutConfigService>();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const ValueKey('linked_layout_main_min_input'), controller: _mainMinController),
          TextField(key: const ValueKey('linked_layout_sub_min_input'), controller: _subMinController),
          FilledButton(
            onPressed: () async {
              await service.update(
                service.config.copyWith(
                  mainMinHeight: double.tryParse(_mainMinController.text) ?? service.config.mainMinHeight,
                  subMinHeight: double.tryParse(_subMinController.text) ?? service.config.subMinHeight,
                ),
              );
            },
            child: const Text('应用'),
          ),
          TextButton(
            onPressed: service.resetToDefaults,
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/linked_layout_debug_sheet_test.dart --reporter compact`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/linked_layout_debug_sheet.dart test/widgets/linked_layout_debug_sheet_test.dart
git commit -m "feat: add linked layout debug bottom sheet"
```

### Task 5: Integrate Adaptive Layout + Debug Entry in Stock Detail

**Files:**
- Modify: `lib/screens/stock_detail_screen.dart`
- Modify: `test/screens/stock_detail_screen_test.dart`
- Modify: `lib/widgets/linked_dual_kline_view.dart` (constructor wiring only)

**Step 1: Write the failing test**

```dart
testWidgets('stock detail provides linked layout debug menu and applies updated thresholds', (tester) async {
  final service = LinkedLayoutConfigService();
  await service.load();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: service,
      child: MaterialApp(
        home: StockDetailScreen(
          stock: Stock(code: '600000', name: '浦发银行', market: 1, preClose: 10.2),
          skipAutoConnectForTest: true,
          showWatchlistToggle: false,
          showIndustryHeatSection: false,
          initialChartMode: ChartMode.linked,
          initialDailyBars: buildDailyBars(count: 60, startDate: DateTime(2026, 1, 1)),
          initialWeeklyBars: buildDailyBars(count: 40, startDate: DateTime(2025, 1, 1)),
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const ValueKey('stock_detail_more_menu_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('联动布局调试'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const ValueKey('linked_layout_main_min_input')), '110');
  await tester.tap(find.text('应用'));
  await tester.pumpAndSettle();

  final weeklyChart = tester.widget<KLineChartWithSubCharts>(
    find.byKey(const ValueKey('linked_weekly_chart')),
  );
  expect(weeklyChart.chartHeight, greaterThanOrEqualTo(110));
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/stock_detail_screen_test.dart --plain-name "stock detail provides linked layout debug menu and applies updated thresholds" --reporter compact`
Expected: FAIL (menu and debug sheet not wired).

**Step 3: Write minimal implementation**

```dart
// stock_detail_screen.dart
PopupMenuButton<String>(
  key: const ValueKey('stock_detail_more_menu_button'),
  onSelected: (value) {
    if (value == 'linked_layout_debug') {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const LinkedLayoutDebugSheet(),
      );
    }
  },
  itemBuilder: (_) => const [
    PopupMenuItem<String>(
      value: 'linked_layout_debug',
      child: Text('联动布局调试'),
    ),
  ],
)
```

```dart
// stock_detail_screen.dart, in linked mode branch
final layoutConfig = context.watch<LinkedLayoutConfigService>().config;
final available = MediaQuery.sizeOf(context).height * 0.72;
final resolved = LinkedLayoutSolver.resolve(
  availableHeight: available,
  topSubchartCount: 2,
  bottomSubchartCount: 2,
  config: layoutConfig,
);

return SizedBox(
  height: resolved.containerHeight,
  child: LinkedDualKlineView(
    stockCode: _currentStock.code,
    weeklyBars: _weeklyBars,
    dailyBars: _dailyBars,
    ratios: _ratioHistory,
    layout: resolved,
    macdCacheStoreForTest: widget.macdCacheStoreForTest,
    adxCacheStoreForTest: widget.adxCacheStoreForTest,
  ),
);
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/stock_detail_screen_test.dart --reporter compact`
Expected: PASS, including existing regression `linked mode keeps weekly main chart readable height`.

**Step 5: Commit**

```bash
git add lib/screens/stock_detail_screen.dart lib/widgets/linked_dual_kline_view.dart test/screens/stock_detail_screen_test.dart lib/widgets/linked_layout_debug_sheet.dart
git commit -m "feat: integrate adaptive linked layout and stock detail debug controls"
```

### Task 6: Wire Service in App DI and Verify End-to-End Behavior

**Files:**
- Modify: `lib/main.dart`
- Create: `test/main_app_provider_test.dart`
- Test: `test/screens/stock_detail_screen_test.dart`
- Test: `test/widgets/linked_dual_kline_view_test.dart`
- Test: `test/widgets/linked_layout_debug_sheet_test.dart`
- Test: `test/services/linked_layout_solver_test.dart`
- Test: `test/services/linked_layout_config_service_test.dart`

**Step 1: Write the failing test**

Add a provider smoke test for `MyApp` to guarantee linked-layout service is registered in DI.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/main.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';

void main() {
  testWidgets('MyApp exposes LinkedLayoutConfigService via provider tree', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final context = tester.element(find.byType(MaterialApp));
    final service = Provider.of<LinkedLayoutConfigService>(context, listen: false);
    expect(service, isNotNull);
    expect(service.config.mainMinHeight, greaterThan(0));
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/main_app_provider_test.dart --reporter compact`
Expected: FAIL (`ProviderNotFoundException` for `LinkedLayoutConfigService`).

**Step 3: Write minimal implementation**

```dart
// main.dart provider list
ChangeNotifierProvider(
  create: (_) {
    final service = LinkedLayoutConfigService();
    service.load();
    return service;
  },
),
```

**Step 4: Run tests to verify pass**

Run:
- `flutter test test/main_app_provider_test.dart --reporter compact`
- `flutter test test/services/linked_layout_solver_test.dart test/services/linked_layout_config_service_test.dart --reporter compact`
- `flutter test test/widgets/linked_layout_debug_sheet_test.dart test/widgets/linked_dual_kline_view_test.dart --reporter compact`
- `flutter test test/screens/stock_detail_screen_test.dart --reporter compact`

Expected: PASS for all commands.

**Step 5: Commit**

```bash
git add lib/main.dart test/main_app_provider_test.dart test/screens/stock_detail_screen_test.dart test/widgets/linked_dual_kline_view_test.dart test/widgets/linked_layout_debug_sheet_test.dart test/services/linked_layout_solver_test.dart test/services/linked_layout_config_service_test.dart
git commit -m "feat: wire linked layout config service into app providers"
```

### Task 7: Final Verification and Documentation Update

**Files:**
- Modify: `docs/plans/2026-02-17-linked-layout-adaptive-implementation.md` (checklist status)
- Optional: `docs/reports/2026-02-17-linked-layout-adaptive-verification.md`

**Step 1: Write verification checklist (failing by default until executed)**

```markdown
- [ ] unit: linked solver/config service
- [ ] widget: linked dual view + debug sheet + stock detail
- [ ] manual: phone-size simulator check (both panes readable)
- [ ] manual: debug reset restores defaults
```

**Step 2: Run verification commands**

Run:
- `flutter test test/services/linked_layout_solver_test.dart test/services/linked_layout_config_service_test.dart --reporter compact`
- `flutter test test/widgets/linked_dual_kline_view_test.dart test/widgets/linked_layout_debug_sheet_test.dart --reporter compact`
- `flutter test test/screens/stock_detail_screen_test.dart --reporter compact`

Expected: PASS (0 failures).

**Step 3: Write minimal docs update**

Add a short “Adaptive Linked Layout” section to the implementation doc with:
1. default balanced values,
2. debug entry path,
3. rollback/reset instructions.

**Step 4: Re-run verification to confirm docs-only change is safe**

Run: `flutter test test/screens/stock_detail_screen_test.dart --reporter compact`
Expected: PASS.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-17-linked-layout-adaptive-implementation.md docs/reports/2026-02-17-linked-layout-adaptive-verification.md
git commit -m "docs: record adaptive linked layout verification"
```
