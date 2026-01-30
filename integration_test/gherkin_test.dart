import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gherkin/gherkin.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import 'gherkin_steps/app_steps.dart';

/// 自定义 Feature 文件读取器
class LocalFeatureFileReader implements FeatureFileReader {
  @override
  Future<String> read(String path) async {
    final file = File(path);
    return file.readAsString();
  }
}

/// 自定义 Feature 文件匹配器
class LocalFeatureFileMatcher implements FeatureFileMatcher {
  @override
  Future<Iterable<String>> listFiles(Pattern pattern) async {
    final files = <String>[];

    if (pattern is Glob) {
      final matches = pattern.listSync();
      for (final entity in matches) {
        if (entity is File) {
          files.add(entity.path);
        }
      }
    } else if (pattern is String) {
      if (FileSystemEntity.isFileSync(pattern)) {
        files.add(pattern);
      }
    }

    return files;
  }
}

/// 创建测试配置
TestConfiguration createGherkinConfig() {
  final config = TestConfiguration();
  config.features = [Glob('integration_test/features/*.feature')];
  config.featureDefaultLanguage = 'zh-CN';
  config.stepDefinitions = getAllStepDefinitions();
  config.featureFileMatcher = LocalFeatureFileMatcher();
  config.featureFileReader = LocalFeatureFileReader();
  config.createWorld = (c) async => WidgetTesterWorld();
  config.reporters = [
    StdoutReporter(MessageLevel.verbose),
    ProgressReporter(),
    TestRunSummaryReporter(),
  ];
  return config;
}

void main() {
  group('中文 Gherkin BDD 测试', () {
    testWidgets('验证步骤定义存在', (tester) async {
      final steps = getAllStepDefinitions();

      // 验证步骤数量
      expect(steps.length, greaterThan(20),
          reason: '应该有足够的步骤定义');

      // 获取步骤的模式列表（GherkinExpression 的 originalPattern 属性）
      final patterns = <String>[];
      for (final step in steps) {
        // 直接使用 step 的 toString 来验证
        patterns.add(step.pattern.toString());
      }

      // 验证关键步骤存在
      expect(patterns.any((p) => p.contains('应用已启动')), isTrue,
          reason: '应包含 应用已启动 步骤');
      expect(patterns.any((p) => p.contains('自选股列表已清空')), isTrue,
          reason: '应包含 自选股列表已清空 步骤');
      expect(patterns.any((p) => p.contains('我点击底部导航栏的')), isTrue,
          reason: '应包含 我点击底部导航栏的 步骤');
      expect(patterns.any((p) => p.contains('Tab应该被选中')), isTrue,
          reason: '应包含 Tab应该被选中 步骤');
    });

    testWidgets('验证 Gherkin 配置创建', (tester) async {
      final config = createGherkinConfig();

      expect(config.featureDefaultLanguage, equals('zh-CN'),
          reason: '默认语言应该是 zh-CN');
      expect(config.stepDefinitions, isNotNull,
          reason: '步骤定义不应为空');
      expect(config.stepDefinitions!.isNotEmpty, isTrue,
          reason: '步骤定义应该包含元素');
    });

    testWidgets('验证 World 可以设置 Tester', (tester) async {
      final world = WidgetTesterWorld();
      world.setTester(tester);

      // 验证 tester 已经被设置
      expect(world.tester, equals(tester),
          reason: 'WidgetTesterWorld 应该持有 tester 引用');
    });
  });
}
