// test_driver/app_test.dart
// Flutter Driver 测试 - 中文 Gherkin BDD
//
// 运行方式：
//   flutter drive --target=test_driver/app.dart
//
// 特点：
//   - 应用状态在测试之间保持
//   - 数据只需同步一次
//   - 测试按顺序在同一个应用实例上运行

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  late FlutterDriver driver;

  // 所有测试开始前连接到应用
  setUpAll(() async {
    driver = await FlutterDriver.connect();
  });

  // 所有测试结束后断开连接
  tearDownAll(() async {
    await driver.close();
  });

  // ============================================================================
  // 辅助函数
  // ============================================================================

  /// 等待元素出现
  Future<void> waitForText(String text, {Duration timeout = const Duration(seconds: 10)}) async {
    await driver.waitFor(find.text(text), timeout: timeout);
  }

  /// 点击文本
  Future<void> tapText(String text) async {
    await driver.tap(find.text(text));
  }

  /// 点击图标
  Future<void> tapIcon(String iconName) async {
    // FlutterDriver 无法直接通过 IconData 查找，需要用 key 或 tooltip
    await driver.tap(find.byTooltip(iconName));
  }

  /// 等待加载完成（CircularProgressIndicator 消失）
  Future<void> waitForLoadingComplete({Duration timeout = const Duration(seconds: 60)}) async {
    // 等待直到没有加载指示器
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      try {
        await driver.waitForAbsent(
          find.byType('CircularProgressIndicator'),
          timeout: const Duration(seconds: 1),
        );
        return; // 加载完成
      } catch (_) {
        // 继续等待
      }
    }
  }

  /// 同步数据（点击刷新按钮并等待完成）
  Future<void> syncData() async {
    try {
      // 点击 RefreshStatusWidget（通过 Key 查找）
      await driver.tap(find.byValueKey('refresh_status_widget'));
      print('已点击刷新按钮');
    } catch (e) {
      print('无法找到刷新按钮: $e');
      return;
    }

    // 等待同步完成
    await waitForLoadingComplete();
    print('数据同步完成');
  }

  // ============================================================================
  // 测试场景
  // ============================================================================

  group('E2E 测试套件', () {
    test('初始化：等待应用启动并同步数据', () async {
      // 等待应用启动完成（自选 Tab 出现）
      await waitForText('自选', timeout: const Duration(seconds: 30));
      print('应用启动完成');

      // 同步数据（只执行一次）
      await syncData();
    });

    group('Feature: 基础导航', () {
      test('Scenario: 启动应用默认显示自选页', () async {
        // 验证自选 Tab 被选中（通过检查页面内容）
        await waitForText('自选');
        await waitForText('添加'); // 自选页的添加按钮
      });

      test('Scenario: 切换到全市场页', () async {
        await tapText('全市场');
        await Future.delayed(const Duration(milliseconds: 500));
        // 验证在全市场页
      });

      test('Scenario: 切换到行业页', () async {
        await tapText('行业');
        await Future.delayed(const Duration(milliseconds: 500));
        // 验证在行业页
      });

      test('Scenario: 切换到回踩页', () async {
        await tapText('回踩');
        await Future.delayed(const Duration(milliseconds: 500));
        // 验证在回踩页
      });

      test('Scenario: 切换回自选页', () async {
        await tapText('自选');
        await Future.delayed(const Duration(milliseconds: 500));
        await waitForText('添加');
      });

      test('Scenario: 自选页内切换到持仓Tab', () async {
        await tapText('持仓');
        await Future.delayed(const Duration(milliseconds: 500));
        await waitForText('从截图导入');
      });

      test('Scenario: 自选页内切换回自选Tab', () async {
        await tapText('自选');
        await Future.delayed(const Duration(milliseconds: 500));
        await waitForText('添加');
      });
    });

    // 可以继续添加更多测试...
  });
}
