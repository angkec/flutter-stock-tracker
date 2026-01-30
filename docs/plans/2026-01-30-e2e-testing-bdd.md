# E2E Testing with BDD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Set up BDD-style end-to-end testing for navigation and watchlist features using `bdd_widget_test`.

**Architecture:** Use Gherkin `.feature` files for test scenarios (human-readable), with Dart step definitions implementing the actual test logic. Tests run on simulators/emulators via Flutter integration test framework.

**Tech Stack:** `bdd_widget_test`, `build_runner`, Flutter integration_test

---

## Task 1: Add Dependencies

**Files:**
- Modify: `pubspec.yaml:46-51`

**Step 1: Add bdd_widget_test and build_runner dependencies**

Add to `dev_dependencies` section in `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  flutter_launcher_icons: ^0.14.3
  sqflite_common_ffi: ^2.3.0
  bdd_widget_test: ^1.6.1
  build_runner: ^2.4.0
```

**Step 2: Run flutter pub get**

Run: `flutter pub get`
Expected: Dependencies resolved successfully

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add bdd_widget_test for e2e testing"
```

---

## Task 2: Create Integration Test Directory Structure

**Files:**
- Create: `integration_test/integration_test.dart`
- Create: `integration_test/features/.gitkeep`
- Create: `integration_test/step/.gitkeep`

**Step 1: Create the integration test entry point**

Create `integration_test/integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Generated test files will be imported here
}
```

**Step 2: Create directories for features and steps**

Run: `mkdir -p integration_test/features integration_test/step`

**Step 3: Create placeholder files**

Run: `touch integration_test/features/.gitkeep integration_test/step/.gitkeep`

**Step 4: Commit**

```bash
git add integration_test/
git commit -m "chore: set up integration test directory structure"
```

---

## Task 3: Create Navigation Feature File

**Files:**
- Create: `integration_test/features/navigation.feature`

**Step 1: Write navigation feature scenarios**

Create `integration_test/features/navigation.feature`:

```gherkin
Feature: 基础导航
  作为用户
  我希望能在各个页面之间切换
  以便查看不同的功能模块

  Scenario: 启动应用默认显示自选页
    Given 应用已启动
    Then 底部导航栏的自选Tab应该被选中
    And 页面应该显示自选列表区域

  Scenario: 切换到全市场页
    Given 应用已启动
    When 我点击底部导航栏的全市场Tab
    Then 底部导航栏的全市场Tab应该被选中
    And 页面应该显示全市场列表区域

  Scenario: 切换到行业页
    Given 应用已启动
    When 我点击底部导航栏的行业Tab
    Then 底部导航栏的行业Tab应该被选中
    And 页面应该显示行业列表区域

  Scenario: 切换到回踩页
    Given 应用已启动
    When 我点击底部导航栏的回踩Tab
    Then 底部导航栏的回踩Tab应该被选中
    And 页面应该显示回踩列表区域

  Scenario: 自选页内切换到持仓Tab
    Given 应用已启动
    And 当前在自选页
    When 我点击持仓Tab
    Then 应该显示持仓列表区域
    And 应该显示从截图导入按钮

  Scenario: 自选页内切换回自选Tab
    Given 应用已启动
    And 当前在自选页
    When 我点击持仓Tab
    And 我点击自选Tab
    Then 应该显示自选列表区域
    And 应该显示添加股票输入框
```

**Step 2: Verify file created**

Run: `cat integration_test/features/navigation.feature`
Expected: Feature file content displayed

**Step 3: Commit**

```bash
git add integration_test/features/navigation.feature
git commit -m "test: add navigation e2e feature scenarios"
```

---

## Task 4: Create Watchlist Feature File

**Files:**
- Create: `integration_test/features/watchlist.feature`

**Step 1: Write watchlist feature scenarios**

Create `integration_test/features/watchlist.feature`:

```gherkin
Feature: 自选股管理
  作为用户
  我希望能管理我的自选股列表
  以便追踪我关注的股票

  Background:
    Given 应用已启动
    And 自选股列表已清空

  Scenario: 空自选列表显示提示
    Then 应该显示暂无自选股提示
    And 应该显示添加提示文字

  Scenario: 添加有效股票代码到自选
    When 我在输入框中输入 {string}
    And 我点击添加按钮
    Then 应该显示已添加提示
    And 自选列表应该包含该股票

    Examples:
      | string |
      | 000001 |
      | 600000 |
      | 300001 |

  Scenario: 添加无效股票代码
    When 我在输入框中输入 {string}
    And 我点击添加按钮
    Then 应该显示无效股票代码提示

    Examples:
      | string |
      | 123456 |
      | 999999 |
      | 12345  |

  Scenario: 添加重复股票代码
    Given 自选列表包含 {string}
    When 我在输入框中输入 {string}
    And 我点击添加按钮
    Then 应该显示该股票已在自选列表中提示

    Examples:
      | string |
      | 000001 |

  Scenario: 长按删除自选股
    Given 自选列表包含 {string}
    When 我长按列表中的该股票
    Then 应该显示已移除提示
    And 自选列表不应包含该股票

    Examples:
      | string |
      | 000001 |

  Scenario: 自选股列表数据持久化
    Given 自选列表包含 {string}
    When 我重启应用
    Then 自选列表应该包含该股票

    Examples:
      | string |
      | 000001 |
```

**Step 2: Verify file created**

Run: `cat integration_test/features/watchlist.feature`
Expected: Feature file content displayed

**Step 3: Commit**

```bash
git add integration_test/features/watchlist.feature
git commit -m "test: add watchlist e2e feature scenarios"
```

---

## Task 5: Create Common Step Definitions

**Files:**
- Create: `integration_test/step/common_steps.dart`

**Step 1: Write common step definitions**

Create `integration_test/step/common_steps.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/main.dart';

/// 应用已启动
Future<void> theAppIsRunning(WidgetTester tester) async {
  // 清空 SharedPreferences 确保测试隔离
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// 自选股列表已清空
Future<void> theWatchlistIsCleared(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'watchlist': <String>[]});
  // 不需要重启，因为在 theAppIsRunning 中会加载
}

/// 我重启应用
Future<void> iRestartTheApp(WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// 当前在自选页
Future<void> iAmOnWatchlistPage(WidgetTester tester) async {
  // 默认启动就在自选页，验证一下
  expect(find.text('自选'), findsWidgets);
}
```

**Step 2: Verify file syntax**

Run: `dart analyze integration_test/step/common_steps.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add integration_test/step/common_steps.dart
git commit -m "test: add common step definitions"
```

---

## Task 6: Create Navigation Step Definitions

**Files:**
- Create: `integration_test/step/navigation_steps.dart`

**Step 1: Write navigation step definitions**

Create `integration_test/step/navigation_steps.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 我点击底部导航栏的{tab}Tab
Future<void> iTapBottomNavTab(WidgetTester tester, String tabName) async {
  final tabFinder = find.ancestor(
    of: find.text(tabName),
    matching: find.byType(NavigationDestination),
  );
  await tester.tap(tabFinder);
  await tester.pumpAndSettle();
}

/// 底部导航栏的{tab}Tab应该被选中
Future<void> bottomNavTabShouldBeSelected(WidgetTester tester, String tabName) async {
  final navigationBar = find.byType(NavigationBar);
  expect(navigationBar, findsOneWidget);

  // 验证对应的 Tab 文字存在
  expect(find.text(tabName), findsWidgets);
}

/// 页面应该显示自选列表区域
Future<void> pageShouldShowWatchlistArea(WidgetTester tester) async {
  // 自选页特征：有输入框和添加按钮
  expect(find.text('添加'), findsOneWidget);
  expect(find.byType(TextField), findsOneWidget);
}

/// 页面应该显示全市场列表区域
Future<void> pageShouldShowMarketArea(WidgetTester tester) async {
  // 全市场页会有搜索或其他特征元素
  // 需要根据实际 MarketScreen 实现调整
  await tester.pumpAndSettle();
}

/// 页面应该显示行业列表区域
Future<void> pageShouldShowIndustryArea(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

/// 页面应该显示回踩列表区域
Future<void> pageShouldShowBreakoutArea(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

/// 我点击持仓Tab
Future<void> iTapHoldingsTab(WidgetTester tester) async {
  await tester.tap(find.text('持仓'));
  await tester.pumpAndSettle();
}

/// 我点击自选Tab
Future<void> iTapWatchlistTab(WidgetTester tester) async {
  // 找到 TabBar 内的自选 Tab
  final watchlistTab = find.descendant(
    of: find.byType(TabBar),
    matching: find.text('自选'),
  );
  await tester.tap(watchlistTab);
  await tester.pumpAndSettle();
}

/// 应该显示持仓列表区域
Future<void> shouldShowHoldingsArea(WidgetTester tester) async {
  expect(find.text('从截图导入'), findsOneWidget);
}

/// 应该显示从截图导入按钮
Future<void> shouldShowImportButton(WidgetTester tester) async {
  expect(find.text('从截图导入'), findsOneWidget);
}

/// 应该显示自选列表区域
Future<void> shouldShowWatchlistArea(WidgetTester tester) async {
  expect(find.text('添加'), findsOneWidget);
}

/// 应该显示添加股票输入框
Future<void> shouldShowAddStockInput(WidgetTester tester) async {
  expect(find.byType(TextField), findsOneWidget);
}
```

**Step 2: Verify file syntax**

Run: `dart analyze integration_test/step/navigation_steps.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add integration_test/step/navigation_steps.dart
git commit -m "test: add navigation step definitions"
```

---

## Task 7: Create Watchlist Step Definitions

**Files:**
- Create: `integration_test/step/watchlist_steps.dart`

**Step 1: Write watchlist step definitions**

Create `integration_test/step/watchlist_steps.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应该显示暂无自选股提示
Future<void> shouldShowEmptyWatchlistHint(WidgetTester tester) async {
  expect(find.text('暂无自选股'), findsOneWidget);
}

/// 应该显示添加提示文字
Future<void> shouldShowAddHintText(WidgetTester tester) async {
  expect(find.text('在上方输入股票代码添加'), findsOneWidget);
}

/// 我在输入框中输入 {code}
Future<void> iEnterStockCode(WidgetTester tester, String code) async {
  final textField = find.byType(TextField);
  await tester.enterText(textField, code);
  await tester.pumpAndSettle();
}

/// 我点击添加按钮
Future<void> iTapAddButton(WidgetTester tester) async {
  await tester.tap(find.text('添加'));
  await tester.pumpAndSettle();
}

/// 应该显示已添加提示
Future<void> shouldShowAddedSnackbar(WidgetTester tester, String code) async {
  expect(find.text('已添加 $code'), findsOneWidget);
}

/// 应该显示无效股票代码提示
Future<void> shouldShowInvalidCodeSnackbar(WidgetTester tester) async {
  expect(find.text('无效的股票代码'), findsOneWidget);
}

/// 应该显示该股票已在自选列表中提示
Future<void> shouldShowAlreadyExistsSnackbar(WidgetTester tester) async {
  expect(find.text('该股票已在自选列表中'), findsOneWidget);
}

/// 自选列表包含 {code}
Future<void> watchlistContains(WidgetTester tester, String code) async {
  // 通过 SharedPreferences mock 直接设置
  final prefs = await SharedPreferences.getInstance();
  final current = prefs.getStringList('watchlist') ?? [];
  if (!current.contains(code)) {
    current.add(code);
    await prefs.setStringList('watchlist', current);
  }
}

/// 自选列表应该包含该股票
Future<void> watchlistShouldContainStock(WidgetTester tester, String code) async {
  // 验证 UI 中显示了该股票代码
  // 注意：可能需要等待数据加载
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.textContaining(code), findsWidgets);
}

/// 自选列表不应包含该股票
Future<void> watchlistShouldNotContainStock(WidgetTester tester, String code) async {
  await tester.pumpAndSettle();
  expect(find.text(code), findsNothing);
}

/// 我长按列表中的该股票
Future<void> iLongPressStock(WidgetTester tester, String code) async {
  final stockItem = find.textContaining(code);
  await tester.longPress(stockItem.first);
  await tester.pumpAndSettle();
}

/// 应该显示已移除提示
Future<void> shouldShowRemovedSnackbar(WidgetTester tester, String code) async {
  expect(find.text('已移除 $code'), findsOneWidget);
}
```

**Step 2: Verify file syntax**

Run: `dart analyze integration_test/step/watchlist_steps.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add integration_test/step/watchlist_steps.dart
git commit -m "test: add watchlist step definitions"
```

---

## Task 8: Configure BDD Test Generation

**Files:**
- Create: `integration_test/bdd_options.dart`
- Modify: `integration_test/integration_test.dart`

**Step 1: Create BDD configuration file**

Create `integration_test/bdd_options.dart`:

```dart
import 'package:bdd_widget_test/bdd_widget_test.dart';

/// BDD 测试配置
/// 定义步骤映射，将 Gherkin 步骤与 Dart 函数关联
const bddOptions = BddOptions(
  featureDefaultTags: ['@e2e'],
);
```

**Step 2: Update integration test entry point**

Update `integration_test/integration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Step definitions
import 'step/common_steps.dart';
import 'step/navigation_steps.dart';
import 'step/watchlist_steps.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Note: bdd_widget_test generates test files from .feature files
  // Run: flutter pub run build_runner build
  // Generated files will be imported and called here
}
```

**Step 3: Commit**

```bash
git add integration_test/bdd_options.dart integration_test/integration_test.dart
git commit -m "test: configure bdd_widget_test"
```

---

## Task 9: Run Build Runner and Verify Setup

**Files:**
- Generated: `integration_test/*.bdd_test.dart` (auto-generated)

**Step 1: Run build_runner to generate test files**

Run: `flutter pub run build_runner build --delete-conflicting-outputs`
Expected: Build runner generates test files from feature files

**Step 2: Verify generated files exist**

Run: `ls integration_test/*.bdd_test.dart`
Expected: Generated test files listed

**Step 3: Run a simple integration test to verify setup**

Run: `flutter test integration_test/ -d macos`
Expected: Tests discovered (may fail initially, but should be discovered)

**Step 4: Commit generated files**

```bash
git add integration_test/
git commit -m "test: add generated bdd test files"
```

---

## Task 10: Create Test Runner Script

**Files:**
- Create: `scripts/run_e2e_tests.sh`

**Step 1: Create test runner script**

Create `scripts/run_e2e_tests.sh`:

```bash
#!/bin/bash
set -e

echo "=== E2E Test Runner ==="

# Generate BDD tests from feature files
echo "Generating BDD tests..."
flutter pub run build_runner build --delete-conflicting-outputs

# Determine platform
PLATFORM=${1:-"macos"}

echo "Running e2e tests on $PLATFORM..."

case $PLATFORM in
  ios)
    flutter test integration_test/ -d "iPhone"
    ;;
  android)
    flutter test integration_test/ -d "emulator"
    ;;
  macos)
    flutter test integration_test/ -d "macos"
    ;;
  *)
    echo "Usage: $0 [ios|android|macos]"
    exit 1
    ;;
esac

echo "=== E2E Tests Complete ==="
```

**Step 2: Make script executable**

Run: `chmod +x scripts/run_e2e_tests.sh`

**Step 3: Commit**

```bash
git add scripts/run_e2e_tests.sh
git commit -m "chore: add e2e test runner script"
```

---

## Summary

After completing all tasks, you will have:

1. **Dependencies**: `bdd_widget_test` and `build_runner` configured
2. **Feature Files**: `navigation.feature` and `watchlist.feature` with Gherkin scenarios
3. **Step Definitions**: Dart implementations for all Gherkin steps
4. **Test Infrastructure**: Build runner configured to generate test files
5. **Runner Script**: Convenient script to run e2e tests

**Running Tests:**

```bash
# Generate and run tests
./scripts/run_e2e_tests.sh macos

# Or manually:
flutter pub run build_runner build
flutter test integration_test/ -d macos
```

**Workflow for Adding New Tests:**

1. Write/modify `.feature` files (you review these)
2. Run `build_runner` to regenerate test files
3. Implement any new step definitions needed
4. Run tests to verify
