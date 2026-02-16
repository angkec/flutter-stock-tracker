# Data Management E2E Stall Guard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 `数据管理` 页面建立“5 秒无业务进展即失败”的自动化保障，覆盖离线主回归与真网络全量复验，并把发现的问题沉淀为 unit/widget 防回归测试。

**Architecture:** 采用双轨观测：主判定基于 UI 业务进展（阶段文案、`current/total`、百分比），辅以底层进度事件时间线用于诊断。离线场景使用可控 fake 依赖驱动完整流程，保证稳定可重复；离线改动完成后执行真网络全量复验，验证真实链路表现。测试实现采用 `driver + watchdog + fixtures` 结构，避免重复脚本和脆弱等待。

**Tech Stack:** Flutter (`flutter_test`, `integration_test`), Dart, Provider, 现有 `DataManagementScreen`, `MarketDataProvider`, `DataRepository`。

---

## 执行前准备

- 推荐先执行 `@using-git-worktrees`，在独立 worktree 落地本计划。
- 执行阶段必须遵循：`@test-driven-development`、`@systematic-debugging`、`@verification-before-completion`。
- 每个任务必须按「先失败测试 -> 最小实现 -> 通过测试 -> 提交」执行。
- DRY / YAGNI：仅实现本计划定义的断言与可观测能力，避免顺带重构。

### Task 1: 建立进度卡住判定核心（纯逻辑）

**Files:**
- Create: `lib/testing/progress_watchdog.dart`
- Test: `test/testing/progress_watchdog_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/testing/progress_watchdog.dart';

void main() {
  test('throws when no progress for over threshold', () {
    final watchdog = ProgressWatchdog(
      stallThreshold: const Duration(seconds: 5),
      now: () => DateTime(2026, 2, 15, 10, 0, 0),
    );

    watchdog.markProgress('1/4 拉取K线数据 1/100');
    watchdog.setNow(() => DateTime(2026, 2, 15, 10, 0, 6));

    expect(
      () => watchdog.assertNotStalled(),
      throwsA(isA<ProgressStalledException>()),
    );
  });

  test('does not throw while progress keeps changing', () {
    final watchdog = ProgressWatchdog(
      stallThreshold: const Duration(seconds: 5),
      now: () => DateTime(2026, 2, 15, 10, 0, 0),
    );

    watchdog.markProgress('1/4 拉取K线数据 1/100');
    watchdog.setNow(() => DateTime(2026, 2, 15, 10, 0, 3));
    watchdog.markProgress('1/4 拉取K线数据 2/100');

    watchdog.assertNotStalled();
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/testing/progress_watchdog_test.dart -r expanded`
Expected: FAIL with missing `ProgressWatchdog` / `ProgressStalledException`.

**Step 3: Write minimal implementation**

```dart
class ProgressWatchdog {
  ProgressWatchdog({
    required Duration stallThreshold,
    required DateTime Function() now,
  }) : _stallThreshold = stallThreshold,
       _now = now;

  final Duration _stallThreshold;
  DateTime Function() _now;
  DateTime? _lastProgressAt;
  String _lastSignal = '';

  void markProgress(String signal) {
    if (signal != _lastSignal) {
      _lastSignal = signal;
      _lastProgressAt = _now();
    }
  }

  void assertNotStalled() {
    final last = _lastProgressAt;
    if (last == null) return;
    if (_now().difference(last) > _stallThreshold) {
      throw ProgressStalledException(
        'No business progress for ${_now().difference(last).inSeconds}s, lastSignal=$_lastSignal',
      );
    }
  }

  void setNow(DateTime Function() now) {
    _now = now;
  }
}

class ProgressStalledException implements Exception {
  ProgressStalledException(this.message);
  final String message;
  @override
  String toString() => message;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/testing/progress_watchdog_test.dart -r expanded`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/testing/progress_watchdog.dart test/testing/progress_watchdog_test.dart
git commit -m "test: add progress watchdog for 5s stall detection"
```

### Task 2: 构建离线 E2E 测试夹具与操作驱动

**Files:**
- Create: `integration_test/support/data_management_fixtures.dart`
- Create: `integration_test/support/data_management_driver.dart`
- Modify: `integration_test/step/common_steps.dart`
- Test: `integration_test/features/data_management_offline_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('offline fixture opens data management page', (tester) async {
  await launchDataManagementWithFixture(tester);

  expect(find.text('数据管理'), findsOneWidget);
  expect(find.text('历史分钟K线'), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos --name "opens data management page"`
Expected: FAIL with undefined `launchDataManagementWithFixture`.

**Step 3: Write minimal implementation**

```dart
Future<void> launchDataManagementWithFixture(WidgetTester tester) async {
  final fixture = buildDefaultDataManagementFixture();
  await tester.pumpWidget(fixture.app);
  await tester.pumpAndSettle();
}

class DataManagementDriver {
  DataManagementDriver(this.tester);
  final WidgetTester tester;

  Future<void> tapFetchHistoricalKline() async {
    await tester.tap(find.widgetWithText(FilledButton, '拉取缺失').first);
    await tester.pump();
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos --name "opens data management page"`
Expected: PASS.

**Step 5: Commit**

```bash
git add integration_test/support/data_management_fixtures.dart \
  integration_test/support/data_management_driver.dart \
  integration_test/features/data_management_offline_test.dart \
  integration_test/step/common_steps.dart
git commit -m "test: add offline data management e2e fixture and driver"
```

### Task 3: 实现离线主链路 E2E（成功路径）

**Files:**
- Modify: `integration_test/features/data_management_offline_test.dart`
- Modify: `integration_test/integration_test.dart`
- Test: `integration_test/features/data_management_offline_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('historical minute fetch completes with visible progress', (tester) async {
  final ctx = await launchDataManagementWithFixture(tester);
  final driver = DataManagementDriver(tester);

  await driver.tapFetchHistoricalKline();
  await driver.expectProgressDialogVisible();
  await driver.waitForCompletionWithWatchdog(ctx.watchdog);

  expect(find.textContaining('历史数据已更新'), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos --name "historical minute fetch completes"`
Expected: FAIL with missing `waitForCompletionWithWatchdog` / progress assertions.

**Step 3: Write minimal implementation**

```dart
Future<void> waitForCompletionWithWatchdog(ProgressWatchdog watchdog) async {
  while (find.byType(AlertDialog).evaluate().isNotEmpty) {
    await tester.pump(const Duration(milliseconds: 200));
    final signal = readBusinessProgressSignal(tester);
    watchdog.markProgress(signal);
    watchdog.assertNotStalled();
  }
}
```

Add parallel success scenarios in same file:

- `weekly fetch completes and shows stage progress`
- `daily force refetch completes with staged progress`
- `recheck freshness completes and shows completion snackbar`

**Step 4: Run test to verify it passes**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos`
Expected: PASS for all offline success scenarios.

**Step 5: Commit**

```bash
git add integration_test/features/data_management_offline_test.dart integration_test/integration_test.dart
git commit -m "test: add offline e2e success scenarios for data management"
```

### Task 4: 实现离线异常与卡住断言（核心质量门）

**Files:**
- Modify: `integration_test/support/data_management_fixtures.dart`
- Modify: `integration_test/features/data_management_offline_test.dart`
- Test: `integration_test/features/data_management_offline_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('fails when no business progress for over 5 seconds', (tester) async {
  final ctx = await launchDataManagementWithFixture(
    tester,
    preset: FixturePreset.stalledProgress,
  );
  final driver = DataManagementDriver(tester);

  await driver.tapFetchHistoricalKline();

  expect(
    () async => driver.waitForCompletionWithWatchdog(ctx.watchdog),
    throwsA(isA<ProgressStalledException>()),
  );
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos --name "no business progress"`
Expected: FAIL because fixture does not yet simulate stall or exception is not surfaced.

**Step 3: Write minimal implementation**

```dart
enum FixturePreset { normal, failedFetch, stalledProgress }

if (preset == FixturePreset.stalledProgress) {
  fakeRepository.statusEventsDuringFetch = const [
    DataFetching(current: 1, total: 100, currentStock: '000001'),
  ];
  fakeRepository.fetchMissingDataDelay = const Duration(seconds: 20);
}
```

Add failing-path assertions:

- fetch exception should close dialog and show `失败` snackbar
- after failure, action button is tappable again

**Step 4: Run test to verify it passes**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos`
Expected: PASS including stalled/failure scenarios.

**Step 5: Commit**

```bash
git add integration_test/support/data_management_fixtures.dart integration_test/features/data_management_offline_test.dart
git commit -m "test: enforce 5s stall guard and failure recoverability in offline e2e"
```

### Task 5: 补齐 UI 的“可预期等待”保障（当仅动画超过 5 秒）

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('shows explicit expectation info when loading has no business progress over 5s', (tester) async {
  final fixture = buildWidgetFixtureWithSilentLoading();
  await tester.pumpWidget(fixture.app);

  await tester.tap(find.widgetWithText(FilledButton, '拉取缺失').first);
  await tester.pump();
  await tester.pump(const Duration(seconds: 6));

  expect(find.textContaining('正在处理'), findsOneWidget);
  expect(find.textContaining('已等待'), findsOneWidget);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart -r expanded --name "no business progress over 5s"`
Expected: FAIL (current UI only spinner or static stage without explicit expectation copy).

**Step 3: Write minimal implementation**

```dart
// In progress dialog state evaluation:
final idleSeconds = now.difference(lastBusinessProgressAt).inSeconds;
if (idleSeconds > 5) {
  stageLabel = '$stageLabel\n已等待 ${idleSeconds}s，正在处理，请稍候...';
}
```

Ensure this message appears only when stage signal unchanged for >5s.

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart -r expanded --name "no business progress over 5s"`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart test/screens/data_management_screen_test.dart
git commit -m "feat: show explicit expectation message when progress appears stalled"
```

### Task 6: 真网络全量复验场景与执行入口

**Files:**
- Create: `integration_test/features/data_management_real_network_test.dart`
- Create: `scripts/run_data_management_real_e2e.sh`
- Modify: `docs/e2e-testing-guide.md`
- Test: `integration_test/features/data_management_real_network_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('real-network: runs full data-management scenario matrix', (tester) async {
  if (!const bool.fromEnvironment('RUN_DATA_MGMT_REAL_E2E')) {
    return;
  }

  await launchRealAppAndOpenDataManagement(tester);
  await runFullScenarioMatrixWithWatchdog(tester);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test integration_test/features/data_management_real_network_test.dart -d macos --dart-define=RUN_DATA_MGMT_REAL_E2E=true`
Expected: FAIL with missing navigation/runner helpers.

**Step 3: Write minimal implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail
flutter test integration_test/features/data_management_real_network_test.dart \
  -d macos \
  --dart-define=RUN_DATA_MGMT_REAL_E2E=true
```

In test file, implement:

- open app
- navigate to `行业` tab
- push `DataManagementScreen`
- execute same action matrix as offline
- enforce watchdog stall rule (5s)

**Step 4: Run test to verify it passes**

Run: `bash scripts/run_data_management_real_e2e.sh`
Expected: PASS in network-enabled environment; if network unavailable, clear skip with reason.

**Step 5: Commit**

```bash
git add integration_test/features/data_management_real_network_test.dart \
  scripts/run_data_management_real_e2e.sh \
  docs/e2e-testing-guide.md
git commit -m "test: add real-network full scenario verification for data management"
```

### Task 7: 回归闭环与最终验收

**Files:**
- Modify: `docs/plans/2026-02-15-data-management-e2e-stall-guard-design.md`
- Modify: `docs/plans/2026-02-15-data-management-e2e-stall-guard.md`
- Test: `integration_test/features/data_management_offline_test.dart`
- Test: `integration_test/features/data_management_real_network_test.dart`
- Test: `test/screens/data_management_screen_test.dart`
- Test: `test/testing/progress_watchdog_test.dart`

**Step 1: Write the failing test**

新增一个“回归守卫” case（示例）：

```dart
testWidgets('keeps action controls usable after a failed long-running flow', (tester) async {
  final ctx = await launchDataManagementWithFixture(
    tester,
    preset: FixturePreset.failedFetch,
  );
  final driver = DataManagementDriver(tester);

  await driver.tapFetchHistoricalKline();
  await driver.waitForCompletionWithWatchdog(ctx.watchdog);

  expect(driver.canTapPrimaryAction(), isTrue);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos --name "controls usable after a failed"`
Expected: FAIL until error-terminal behavior is fully validated.

**Step 3: Write minimal implementation**

- 补齐遗漏状态恢复逻辑（如按钮禁用状态、弹窗关闭时机、消息展示统一）。
- 若发现新缺陷，先补 `test/screens/data_management_screen_test.dart` 的针对性用例，再修复。

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/testing/progress_watchdog_test.dart -r expanded
flutter test test/screens/data_management_screen_test.dart -r expanded
flutter test integration_test/features/data_management_offline_test.dart -d macos
bash scripts/run_data_management_real_e2e.sh
```

Expected: All PASS (或真实网络环境下给出明确 skip 原因，不允许 silent skip)。

**Step 5: Commit**

```bash
git add docs/plans/2026-02-15-data-management-e2e-stall-guard-design.md \
  docs/plans/2026-02-15-data-management-e2e-stall-guard.md
git commit -m "chore: finalize data management e2e stall-guard verification"
```

---

## 附：执行顺序建议

1. Task 1-2 先搭基建，保证后续测试可维护。
2. Task 3-4 先把离线回归做实（这是主质量闸门）。
3. Task 5 再做 UI 可预期等待增强（由测试驱动）。
4. Task 6 在离线修改稳定后再跑真网络全量复验。
5. Task 7 做收口，确保缺陷都被 unit/widget 测试固化。
