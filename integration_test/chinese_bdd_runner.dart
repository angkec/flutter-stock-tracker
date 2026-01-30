// Chinese Gherkin BDD Test Runner for Flutter Widget Tests
// Parses Chinese feature files and executes them as widget tests

import 'package:flutter_test/flutter_test.dart';
import 'package:gherkin/gherkin.dart';
import 'gherkin_steps/app_steps.dart';

// ============================================================================
// Embedded Feature Files (since integration tests can't access filesystem)
// ============================================================================

const _embeddedFeatures = <String, String>{
  'navigation': '''
# language: zh-CN
功能: 基础导航
  作为用户
  我希望能在各个页面之间切换
  以便查看不同的功能模块

  背景:
    假如 应用已启动
    并且 数据已同步

  场景: 启动应用默认显示自选页
    那么 底部导航栏的"自选"Tab应该被选中
    并且 页面应该显示自选列表区域

  场景: 切换到全市场页
    当 我点击底部导航栏的"全市场"Tab
    那么 底部导航栏的"全市场"Tab应该被选中
    并且 页面应该显示全市场列表区域

  场景: 切换到行业页
    当 我点击底部导航栏的"行业"Tab
    那么 底部导航栏的"行业"Tab应该被选中
    并且 页面应该显示行业列表区域

  场景: 切换到回踩页
    当 我点击底部导航栏的"回踩"Tab
    那么 底部导航栏的"回踩"Tab应该被选中
    并且 页面应该显示回踩列表区域

  场景: 自选页内切换到持仓Tab
    假如 当前在自选页
    当 我点击持仓Tab
    那么 应该显示持仓列表区域
    并且 应该显示从截图导入按钮

  场景: 自选页内切换回自选Tab
    假如 当前在自选页
    当 我点击持仓Tab
    并且 我点击自选Tab
    那么 应该显示自选列表区域
    并且 应该显示添加股票输入框
''',
  'watchlist': '''
# language: zh-CN
功能: 自选股管理
  作为用户
  我希望能管理我的自选股列表
  以便追踪我关注的股票

  背景:
    假如 应用已启动
    并且 自选股列表已清空

  场景: 空自选列表显示提示
    那么 应该显示暂无自选股提示
    并且 应该显示添加提示文字

  场景大纲: 添加有效股票代码到自选
    当 我在输入框中输入"<股票代码>"
    并且 我点击添加按钮
    那么 应该显示已添加"<股票代码>"提示
    并且 自选列表应该包含"<股票代码>"

    例子:
      | 股票代码 |
      | 000001 |
      | 600000 |
      | 300001 |

  场景大纲: 添加无效股票代码
    当 我在输入框中输入"<股票代码>"
    并且 我点击添加按钮
    那么 应该显示无效股票代码提示

    例子:
      | 股票代码 |
      | 123456 |
      | 999999 |
      | 12345  |

  场景大纲: 添加重复股票代码
    假如 自选列表包含"<股票代码>"
    当 我在输入框中输入"<股票代码>"
    并且 我点击添加按钮
    那么 应该显示该股票已在自选列表中提示

    例子:
      | 股票代码 |
      | 000001 |

  场景大纲: 长按删除自选股
    假如 自选列表包含"<股票代码>"
    当 我长按列表中的"<股票代码>"
    那么 应该显示已移除"<股票代码>"提示
    并且 自选列表不应包含"<股票代码>"

    例子:
      | 股票代码 |
      | 000001 |

  场景大纲: 自选股列表数据持久化
    假如 自选列表包含"<股票代码>"
    当 我重启应用
    那么 自选列表应该包含"<股票代码>"

    例子:
      | 股票代码 |
      | 000001 |
''',
};

// ============================================================================
// Data Structures
// ============================================================================

/// Represents a parsed scenario with its name and steps
class ParsedScenario {
  final String name;
  final List<String> steps;
  final bool isOutline;
  final List<Map<String, String>> examples;

  ParsedScenario(
    this.name,
    this.steps, {
    this.isOutline = false,
    this.examples = const [],
  });

  /// Generate concrete scenarios from an outline with examples
  List<ParsedScenario> expandOutline() {
    if (!isOutline || examples.isEmpty) {
      return [this];
    }

    return examples.map((example) {
      final expandedSteps = steps.map((step) {
        String expandedStep = step;
        example.forEach((key, value) {
          expandedStep = expandedStep.replaceAll('<$key>', value);
        });
        return expandedStep;
      }).toList();

      // Create a descriptive name with example values
      final exampleDesc = example.values.join(', ');
      return ParsedScenario('$name ($exampleDesc)', expandedSteps);
    }).toList();
  }
}

/// Represents a parsed feature file
class ParsedFeature {
  final String name;
  final List<String> backgroundSteps;
  final List<ParsedScenario> scenarios;

  ParsedFeature(this.name, this.backgroundSteps, this.scenarios);
}

// ============================================================================
// Step Definition Wrapper
// ============================================================================

/// Wraps a step definition with its pattern for matching
class StepDefinitionWrapper {
  final String patternString;
  final StepDefinitionGeneric<WidgetTesterWorld> definition;
  final RegExp _regex;
  final List<String> _parameterTypes;

  StepDefinitionWrapper(this.patternString, this.definition)
      : _regex = _buildRegex(patternString),
        _parameterTypes = _extractParameterTypes(patternString);

  /// Extract parameter types from pattern
  static List<String> _extractParameterTypes(String pattern) {
    final types = <String>[];
    final matches = RegExp(r'\{(\w+)\}').allMatches(pattern);
    for (final match in matches) {
      types.add(match.group(1)!);
    }
    return types;
  }

  /// Build a regex from a gherkin pattern like "我点击底部导航栏的{string}Tab"
  static RegExp _buildRegex(String pattern) {
    // Escape regex special characters except for our placeholders
    String regexPattern = pattern
        .replaceAll(r'\', r'\\')
        .replaceAll('.', r'\.')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('^', r'\^')
        .replaceAll(r'$', r'\$')
        .replaceAll('*', r'\*')
        .replaceAll('+', r'\+')
        .replaceAll('?', r'\?')
        .replaceAll('|', r'\|');

    // Replace {string} with regex for quoted strings (matches 'xxx' or "xxx")
    // Support both ASCII quotes and Chinese fullwidth quotes
    regexPattern = regexPattern.replaceAll(
      RegExp(r'\\{string\\}|\{string\}'),
      '["\'"\u201c]([^"\'"\u201d]*)["\'"\u201d]',
    );

    // Replace {int} with regex for integers
    regexPattern = regexPattern.replaceAll(
      RegExp(r'\\{int\\}|\{int\}'),
      r'(\d+)',
    );

    return RegExp('^$regexPattern\$');
  }

  /// Try to match a step text and return extracted parameters
  List<dynamic>? match(String stepText) {
    final match = _regex.firstMatch(stepText);
    if (match == null) return null;

    final params = <dynamic>[];

    for (int i = 1; i <= match.groupCount; i++) {
      final value = match.group(i);
      if (value != null) {
        // Check parameter type from pattern to determine if it should be int
        final paramIndex = params.length;
        if (paramIndex < _parameterTypes.length && _parameterTypes[paramIndex] == 'int') {
          params.add(int.parse(value));
        } else {
          // Keep as string for {string} parameters
          params.add(value);
        }
      }
    }

    return params;
  }
}

// ============================================================================
// Feature File Parser
// ============================================================================

/// Chinese Gherkin keywords
const _chineseKeywords = {
  'feature': ['功能', '功能:'],
  'background': ['背景', '背景:'],
  'scenario': ['场景', '场景:'],
  'scenarioOutline': ['场景大纲', '场景大纲:'],
  'examples': ['例子', '例子:'],
  'given': ['假如', '假设', '设定'],
  'when': ['当', '每当'],
  'then': ['那么', '则'],
  'and': ['并且', '而且', '同时', '且'],
  'but': ['但是', '但'],
};

/// Parse a Chinese Gherkin feature file
ParsedFeature parseFeatureFile(String content, String fileName) {
  final lines = content.split('\n');
  String featureName = fileName;
  List<String> backgroundSteps = [];
  List<ParsedScenario> scenarios = [];

  String? currentSection;
  String? currentScenarioName;
  List<String> currentSteps = [];
  bool isOutline = false;
  List<Map<String, String>> currentExamples = [];
  List<String>? exampleHeaders;

  for (final line in lines) {
    final trimmed = line.trim();

    // Skip empty lines and comments
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    // Feature line
    if (_startsWithKeyword(trimmed, 'feature')) {
      featureName = _extractAfterColon(trimmed);
      continue;
    }

    // Background section
    if (_startsWithKeyword(trimmed, 'background')) {
      _saveCurrentScenario(
        currentScenarioName,
        currentSteps,
        isOutline,
        currentExamples,
        scenarios,
      );
      currentSection = 'background';
      currentScenarioName = null;
      currentSteps = [];
      isOutline = false;
      currentExamples = [];
      exampleHeaders = null;
      continue;
    }

    // Scenario outline
    if (_startsWithKeyword(trimmed, 'scenarioOutline')) {
      _saveCurrentScenario(
        currentScenarioName,
        currentSteps,
        isOutline,
        currentExamples,
        scenarios,
      );
      if (currentSection == 'background') {
        backgroundSteps = List.from(currentSteps);
      }
      currentSection = 'scenario';
      currentScenarioName = _extractAfterColon(trimmed);
      currentSteps = [];
      isOutline = true;
      currentExamples = [];
      exampleHeaders = null;
      continue;
    }

    // Regular scenario
    if (_startsWithKeyword(trimmed, 'scenario')) {
      _saveCurrentScenario(
        currentScenarioName,
        currentSteps,
        isOutline,
        currentExamples,
        scenarios,
      );
      if (currentSection == 'background') {
        backgroundSteps = List.from(currentSteps);
      }
      currentSection = 'scenario';
      currentScenarioName = _extractAfterColon(trimmed);
      currentSteps = [];
      isOutline = false;
      currentExamples = [];
      exampleHeaders = null;
      continue;
    }

    // Examples section for scenario outline
    if (_startsWithKeyword(trimmed, 'examples')) {
      currentSection = 'examples';
      exampleHeaders = null;
      continue;
    }

    // Parse example table rows
    if (currentSection == 'examples' && trimmed.startsWith('|')) {
      final cells = _parseTableRow(trimmed);
      if (exampleHeaders == null) {
        exampleHeaders = cells;
      } else {
        final example = <String, String>{};
        for (int i = 0; i < exampleHeaders.length && i < cells.length; i++) {
          example[exampleHeaders[i]] = cells[i];
        }
        currentExamples.add(example);
      }
      continue;
    }

    // Step line
    if (_isStepLine(trimmed)) {
      final stepText = _extractStepText(trimmed);
      if (currentSection == 'background') {
        backgroundSteps.add(stepText);
      } else {
        currentSteps.add(stepText);
      }
      continue;
    }
  }

  // Save last scenario
  _saveCurrentScenario(
    currentScenarioName,
    currentSteps,
    isOutline,
    currentExamples,
    scenarios,
  );

  return ParsedFeature(featureName, backgroundSteps, scenarios);
}

bool _startsWithKeyword(String line, String keywordType) {
  final keywords = _chineseKeywords[keywordType] ?? [];
  for (final keyword in keywords) {
    if (line.startsWith(keyword)) return true;
  }
  // Also check with colon variants (both Chinese and ASCII)
  for (final keyword in keywords) {
    if (line.startsWith('$keyword:') || line.startsWith('$keyword：')) {
      return true;
    }
  }
  return false;
}

String _extractAfterColon(String line) {
  // Find colon (ASCII or Chinese fullwidth)
  int colonIndex = line.indexOf(':');
  if (colonIndex == -1) colonIndex = line.indexOf('：');
  if (colonIndex == -1) {
    // Look for space after keyword
    final spaceIndex = line.indexOf(' ');
    if (spaceIndex != -1) return line.substring(spaceIndex + 1).trim();
    return line;
  }
  return line.substring(colonIndex + 1).trim();
}

bool _isStepLine(String line) {
  final stepKeywords = [
    ..._chineseKeywords['given']!,
    ..._chineseKeywords['when']!,
    ..._chineseKeywords['then']!,
    ..._chineseKeywords['and']!,
    ..._chineseKeywords['but']!,
  ];
  for (final keyword in stepKeywords) {
    if (line.startsWith(keyword)) return true;
  }
  return false;
}

String _extractStepText(String line) {
  final stepKeywords = [
    // Longer keywords first to avoid partial matches
    ..._chineseKeywords['given']!,
    ..._chineseKeywords['when']!,
    ..._chineseKeywords['then']!,
    ..._chineseKeywords['and']!,
    ..._chineseKeywords['but']!,
  ]..sort((a, b) => b.length.compareTo(a.length));

  for (final keyword in stepKeywords) {
    if (line.startsWith(keyword)) {
      String rest = line.substring(keyword.length);
      // Remove leading space if present
      if (rest.startsWith(' ')) rest = rest.substring(1);
      return rest;
    }
  }
  return line;
}

List<String> _parseTableRow(String line) {
  return line
      .split('|')
      .map((cell) => cell.trim())
      .where((cell) => cell.isNotEmpty)
      .toList();
}

void _saveCurrentScenario(
  String? name,
  List<String> steps,
  bool isOutline,
  List<Map<String, String>> examples,
  List<ParsedScenario> scenarios,
) {
  if (name != null && steps.isNotEmpty) {
    scenarios.add(ParsedScenario(
      name,
      List.from(steps),
      isOutline: isOutline,
      examples: List.from(examples),
    ));
  }
}

// ============================================================================
// Minimal Reporter Implementation
// ============================================================================

class NoOpReporter extends Reporter {}

// ============================================================================
// Step Execution
// ============================================================================

/// Build step definition wrappers from the step definitions
List<StepDefinitionWrapper> buildStepWrappers() {
  final definitions = getAllStepDefinitions();
  final wrappers = <StepDefinitionWrapper>[];

  for (final def in definitions) {
    // Extract pattern from the step definition
    // pattern is a Pattern, we need to convert to String
    final pattern = def.pattern;
    final patternString = pattern is RegExp ? pattern.pattern : pattern.toString();
    wrappers.add(StepDefinitionWrapper(patternString, def as StepDefinitionGeneric<WidgetTesterWorld>));
  }

  return wrappers;
}

/// Execute a step by matching it against step definitions
Future<void> executeStep(
  String stepText,
  WidgetTesterWorld world,
  List<StepDefinitionWrapper> stepWrappers,
  Reporter reporter,
) async {
  for (final wrapper in stepWrappers) {
    final params = wrapper.match(stepText);
    if (params != null) {
      // Use the gherkin package's run method with proper parameters
      final result = await wrapper.definition.run(
        world,
        reporter,
        const Duration(seconds: 30),
        params,
      );

      // Check if the step failed
      if (result.result == StepExecutionResult.fail) {
        throw Exception('Step failed: ${result.resultReason ?? "Unknown reason"}');
      } else if (result.result == StepExecutionResult.error) {
        // Get more detailed error info from ErroredStepResult if available
        if (result is ErroredStepResult) {
          throw Exception('Step error executing "$stepText": ${result.exception}\n${result.stackTrace}');
        }
        throw Exception('Step error: ${result.resultReason ?? "Unknown error"}');
      } else if (result.result == StepExecutionResult.timeout) {
        throw Exception('Step timed out');
      }

      return;
    }
  }

  // No matching step found
  throw Exception(
    'No matching step definition for: "$stepText"\n'
    'Available patterns:\n'
    '${stepWrappers.map((w) => '  - ${w.patternString}').join('\n')}',
  );
}

// ============================================================================
// Main Test Runner
// ============================================================================

void main() {
  final stepWrappers = buildStepWrappers();
  final reporter = NoOpReporter();

  for (final entry in _embeddedFeatures.entries) {
    final fileName = entry.key;
    final content = entry.value;
    final feature = parseFeatureFile(content, fileName);

    group('Feature: ${feature.name}', () {
      for (final scenario in feature.scenarios) {
        // Expand scenario outlines into concrete scenarios
        final concreteScenarios = scenario.expandOutline();

        for (final concreteScenario in concreteScenarios) {
          testWidgets('Scenario: ${concreteScenario.name}', (tester) async {
            final world = WidgetTesterWorld();
            world.setTester(tester);

            // Execute background steps first
            for (final step in feature.backgroundSteps) {
              await executeStep(step, world, stepWrappers, reporter);
            }

            // Execute scenario steps
            for (final step in concreteScenario.steps) {
              await executeStep(step, world, stepWrappers, reporter);
            }
          });
        }
      }
    });
  }
}
