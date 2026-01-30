import 'package:bdd_widget_test/bdd_widget_test.dart';

/// BDD 测试配置
/// 定义步骤映射，将 Gherkin 步骤与 Dart 函数关联
const bddOptions = BddOptions(
  featureDefaultTags: ['@e2e'],
);
