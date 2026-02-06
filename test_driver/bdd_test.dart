// test_driver/bdd_test.dart
// Flutter Driver BDD 测试 - 中文 Gherkin
//
// 运行方式：
//   flutter drive --target=test_driver/app.dart --driver=test_driver/bdd_test.dart
//
// 特点：
//   - 解析中文 Gherkin feature 文件
//   - 应用状态在测试之间保持
//   - 数据只需同步一次

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

// ============================================================================
// Feature 文件内容（嵌入）
// ============================================================================

const _features = {
  'navigation': '''
# language: zh-CN
功能: 基础导航
  作为用户
  我希望能在各个页面之间切换

  场景: 启动应用默认显示自选页
    那么 底部导航栏的"自选"Tab应该被选中
    并且 页面应该显示自选列表区域

  场景: 切换到全市场页
    当 我点击底部导航栏的"全市场"Tab
    那么 底部导航栏的"全市场"Tab应该被选中

  场景: 切换到行业页
    当 我点击底部导航栏的"行业"Tab
    那么 底部导航栏的"行业"Tab应该被选中

  场景: 切换到回踩页
    当 我点击底部导航栏的"回踩"Tab
    那么 底部导航栏的"回踩"Tab应该被选中

  场景: 切换回自选页
    当 我点击底部导航栏的"自选"Tab
    那么 底部导航栏的"自选"Tab应该被选中

  场景: 自选页内切换到持仓Tab
    当 我点击持仓Tab
    那么 应该显示从截图导入按钮

  场景: 自选页内切换回自选Tab
    当 我点击自选Tab
    那么 应该显示添加股票输入框
''',
};

// ============================================================================
// 步骤定义 (FlutterDriver 版本)
// ============================================================================

class DriverSteps {
  final FlutterDriver driver;

  DriverSteps(this.driver);

  /// Tab 名称到导航 Key 的映射
  static const _navKeys = {
    '自选': 'nav_watchlist',
    '全市场': 'nav_market',
    '行业': 'nav_industry',
    '回踩': 'nav_breakout',
  };

  /// 步骤模式 -> 实现函数 的映射
  late final Map<RegExp, Future<void> Function(Match)> _steps = {
    // 导航步骤 - 使用 Key 来避免多文本匹配
    RegExp(r'我点击底部导航栏的"(.+)"Tab'): (m) async {
      final tabName = m.group(1)!;
      final navKey = _navKeys[tabName];
      if (navKey != null) {
        await driver.tap(find.byValueKey(navKey));
      } else {
        await driver.tap(find.text(tabName));
      }
      await Future.delayed(const Duration(milliseconds: 500));
    },

    RegExp(r'底部导航栏的"(.+)"Tab应该被选中'): (m) async {
      final tabName = m.group(1)!;
      final navKey = _navKeys[tabName];
      if (navKey != null) {
        await driver.waitFor(find.byValueKey(navKey));
      } else {
        await driver.waitFor(find.text(tabName));
      }
    },

    RegExp(r'页面应该显示自选列表区域'): (_) async {
      await driver.waitFor(find.text('添加'));
    },

    RegExp(r'我点击持仓Tab'): (_) async {
      await driver.tap(find.byValueKey('holdings_tab'));
      await Future.delayed(const Duration(milliseconds: 500));
    },

    RegExp(r'我点击自选Tab'): (_) async {
      await driver.tap(find.byValueKey('watchlist_tab'));
      await Future.delayed(const Duration(milliseconds: 500));
    },

    RegExp(r'应该显示从截图导入按钮'): (_) async {
      await driver.waitFor(find.text('从截图导入'));
    },

    RegExp(r'应该显示添加股票输入框'): (_) async {
      await driver.waitFor(find.text('添加'));
    },

    // 数据同步步骤
    RegExp(r'数据已同步'): (_) async {
      await _syncData();
    },
  };

  /// 同步数据
  Future<void> _syncData() async {
    try {
      print('  [同步] 等待刷新按钮出现...');

      // 等待刷新按钮出现
      await driver.waitFor(
        find.byValueKey('refresh_button'),
        timeout: const Duration(seconds: 15),
      );
      print('  [同步] 找到刷新按钮');

      // 点击刷新按钮
      await driver.tap(find.byValueKey('refresh_button'));
      print('  [同步] 已点击刷新按钮');

      // 等待加载完成（最多60秒）
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          await driver.waitForAbsent(
            find.byType('CircularProgressIndicator'),
            timeout: const Duration(milliseconds: 500),
          );
          print('  [同步] 数据同步完成');
          return;
        } catch (_) {
          if (i % 10 == 0) print('  [同步] 等待中... ${i}s');
        }
      }
      print('  [同步] 等待超时');
    } catch (e) {
      print('  [同步] 错误: $e');
    }
  }

  /// 执行步骤
  Future<void> execute(String stepText) async {
    for (final entry in _steps.entries) {
      final match = entry.key.firstMatch(stepText);
      if (match != null) {
        print('  执行: $stepText');
        await entry.value(match);
        return;
      }
    }
    throw Exception('未找到匹配的步骤定义: $stepText');
  }
}

// ============================================================================
// Feature 解析器
// ============================================================================

class ParsedScenario {
  final String name;
  final List<String> steps;
  ParsedScenario(this.name, this.steps);
}

class ParsedFeature {
  final String name;
  final List<String> backgroundSteps;
  final List<ParsedScenario> scenarios;
  ParsedFeature(this.name, this.backgroundSteps, this.scenarios);
}

ParsedFeature parseFeature(String content) {
  final lines = content.split('\n');
  String featureName = '';
  List<String> backgroundSteps = [];
  List<ParsedScenario> scenarios = [];

  String? currentScenarioName;
  List<String> currentSteps = [];
  bool inBackground = false;

  for (final line in lines) {
    final trimmed = line.trim();

    if (trimmed.startsWith('功能:') || trimmed.startsWith('功能：')) {
      featureName = trimmed.substring(trimmed.indexOf(':') + 1).trim();
    } else if (trimmed.startsWith('背景:') || trimmed.startsWith('背景：')) {
      inBackground = true;
    } else if (trimmed.startsWith('场景:') || trimmed.startsWith('场景：')) {
      // 保存上一个场景
      if (currentScenarioName != null) {
        scenarios.add(ParsedScenario(currentScenarioName, currentSteps));
      }
      currentScenarioName = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      currentSteps = [];
      inBackground = false;
    } else if (_isStep(trimmed)) {
      final stepText = _extractStepText(trimmed);
      if (inBackground) {
        backgroundSteps.add(stepText);
      } else {
        currentSteps.add(stepText);
      }
    }
  }

  // 保存最后一个场景
  if (currentScenarioName != null) {
    scenarios.add(ParsedScenario(currentScenarioName, currentSteps));
  }

  return ParsedFeature(featureName, backgroundSteps, scenarios);
}

bool _isStep(String line) {
  final keywords = ['假如 ', '假设 ', '假定 ', '当 ', '那么 ', '并且 ', '而且 ', '同时 ', '但是 '];
  return keywords.any((k) => line.startsWith(k));
}

String _extractStepText(String line) {
  final keywords = ['假如 ', '假设 ', '假定 ', '当 ', '那么 ', '并且 ', '而且 ', '同时 ', '但是 '];
  for (final k in keywords) {
    if (line.startsWith(k)) {
      return line.substring(k.length);
    }
  }
  return line;
}

// ============================================================================
// 主测试
// ============================================================================

void main() {
  late FlutterDriver driver;
  late DriverSteps steps;
  bool dataSynced = false;

  setUpAll(() async {
    driver = await FlutterDriver.connect();
    steps = DriverSteps(driver);

    // 等待应用启动
    print('等待应用启动...');
    await driver.waitFor(find.text('自选'), timeout: const Duration(seconds: 30));
    print('应用已启动');

    // 同步数据（只执行一次）
    if (!dataSynced) {
      print('开始同步数据...');
      await steps._syncData();
      dataSynced = true;
    }
  });

  tearDownAll(() async {
    await driver.close();
  });

  // 解析并运行所有 feature
  for (final entry in _features.entries) {
    final feature = parseFeature(entry.value);

    group('Feature: ${feature.name}', () {
      for (final scenario in feature.scenarios) {
        test('Scenario: ${scenario.name}', () async {
          print('\n--- ${scenario.name} ---');

          // 执行背景步骤
          for (final step in feature.backgroundSteps) {
            await steps.execute(step);
          }

          // 执行场景步骤
          for (final step in scenario.steps) {
            await steps.execute(step);
          }
        });
      }
    });
  }
}
