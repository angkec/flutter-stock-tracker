# E2E 测试指南

## 两种测试模式

| 模式 | 命令 | 特点 |
|------|------|------|
| Widget 测试 | `flutter test integration_test/...` | 快速，每个场景独立，无法共享状态 |
| Driver 测试 | `flutter drive --target=test_driver/app.dart` | 较慢，状态持久，数据只需同步一次 |

---

## 方式一：Flutter Drive（推荐用于需要数据同步的测试）

```bash
# 运行 BDD 测试（推荐）
flutter drive --target=test_driver/app.dart --driver=test_driver/bdd_test.dart

# 运行普通测试
flutter drive --target=test_driver/app.dart --driver=test_driver/app_test.dart

# 指定设备
flutter drive --target=test_driver/app.dart --driver=test_driver/bdd_test.dart -d <device_id>
```

**优点：**
- 应用状态在测试之间保持
- 数据只需同步一次
- 更接近真实用户操作

**文件结构：**
```
test_driver/
├── app.dart        # 应用入口（启用 Driver 扩展）
├── bdd_test.dart   # BDD 测试（中文 Gherkin，推荐）
└── app_test.dart   # 普通测试用例
```

---

## 方式二：Widget 测试（快速验证 UI）

```bash
# 运行所有 e2e 测试
flutter test integration_test/chinese_bdd_runner.dart -d macos

# 只运行导航测试
flutter test integration_test/chinese_bdd_runner.dart -d macos --name "Feature: 基础导航"

# 只运行自选股测试
flutter test integration_test/chinese_bdd_runner.dart -d macos --name "Feature: 自选股管理"
```

---

## 数据管理页防卡住回归

### 离线主回归（默认）

```bash
flutter test integration_test/features/data_management_offline_test.dart -d macos
```

覆盖目标：
- 历史分钟K拉取、周K拉取、日K强制拉取、重新检测
- 失败可恢复路径
- 连续 5 秒无业务进展即判定卡住

### 真网络全量复验（离线修改完成后）

```bash
bash scripts/run_data_management_real_e2e.sh
```

等价命令：

```bash
flutter test integration_test/features/data_management_real_network_test.dart \
  -d macos \
  --dart-define=RUN_DATA_MGMT_REAL_E2E=true
```

说明：不传 `RUN_DATA_MGMT_REAL_E2E=true` 时，真网络场景会主动跳过。

真网络场景中，以下长任务会额外校验“可预期进度”文本（`速率`、`预计剩余`）：
- 周K强制重拉（含周线 MACD 预热阶段）
- 周线 MACD 重算

并输出耗时统计日志，便于对比优化前后性能：
- `[DataManagement Real E2E] historical_fetch_missing_elapsed_ms=...`
- `[DataManagement Real E2E] weekly_fetch_missing_elapsed_ms=...`
- `[DataManagement Real E2E] daily_force_refetch_elapsed_ms=...`
- `[DataManagement Real E2E] historical_recheck_elapsed_ms=...`
- `[DataManagement Real E2E] weekly_force_refetch_elapsed_ms=...`
- `[DataManagement Real E2E] weekly_macd_recompute_elapsed_ms=...`
- `[DataManagement Real E2E] weekly_force_refetch_progress_hint=speed:true/false,eta:true/false`
- `[DataManagement Real E2E] weekly_macd_recompute_progress_hint=dialog:true/false,speed:true/false,eta:true/false`

判定规则：
- 周K强制重拉：当任务总耗时超过 5 秒时，必须观测到 `speed:true`；否则测试失败。
- 周线 MACD 重算：仅当重算对话框出现且总耗时超过 5 秒时，必须观测到 `speed:true`；否则测试失败。

---

## 周线 MACD 重算压测（模拟器）

用于验证“重算周线 MACD”首进度时延和总耗时，并做参数 sweep（`fetchBatchSize` / `persistConcurrency`）。

```bash
scripts/benchmark_weekly_macd_recompute.sh
```

常用参数：

```bash
BENCH_DEVICE='iPhone SE (3rd generation)' \
WEEKLY_MACD_BENCH_STOCK_LIMIT=500 \
WEEKLY_MACD_BENCH_SWEEP='40x6,80x8,120x8' \
scripts/benchmark_weekly_macd_recompute.sh
```

输出：
- 原始日志：`/tmp/weekly_macd_recompute_bench_*.log`
- 汇总表：`/tmp/weekly_macd_recompute_bench_*.tsv`
- 控制台会给出推荐参数

最新基准记录见：`docs/reports/weekly-macd-recompute-benchmark-2026-02-16.md`

---

## 文件结构

```
integration_test/
├── chinese_bdd_runner.dart      # 测试运行器（包含嵌入的 feature 内容）
├── gherkin_steps/
│   └── app_steps.dart           # 步骤定义实现
└── features/
    ├── navigation.feature       # 导航场景（参考文档）
    └── watchlist.feature        # 自选股场景（参考文档）
```

---

## 工作流

### 1. 添加/修改测试场景

编辑 `integration_test/chinese_bdd_runner.dart` 中的 `_embeddedFeatures`：

```dart
const _embeddedFeatures = <String, String>{
  'navigation': '''
# language: zh-CN
功能: 基础导航

  场景: 启动应用默认显示自选页
    假如 应用已启动
    那么 底部导航栏的"自选"Tab应该被选中
''',
  // 添加新的 feature...
};
```

### 2. 添加新的步骤定义

编辑 `integration_test/gherkin_steps/app_steps.dart`：

```dart
/// 我点击{button}按钮
StepDefinitionGeneric iTapButtonStep() {
  return when1<String, WidgetTesterWorld>(
    '我点击{string}按钮',  // 模式，{string} 匹配引号内的文字
    (buttonName, context) async {
      await context.world.tester.tap(find.text(buttonName));
      await context.world.tester.pumpAndSettle();
    },
  );
}
```

然后在 `getAllStepDefinitions()` 中注册：

```dart
List<StepDefinitionGeneric> getAllStepDefinitions() {
  return [
    // ... 现有步骤
    iTapButtonStep(),  // 新增
  ];
}
```

### 3. 运行测试验证

```bash
flutter test integration_test/chinese_bdd_runner.dart -d macos
```

---

## 中文 Gherkin 语法

### 关键字对照

| 英文 | 中文 |
|------|------|
| Feature | 功能 |
| Background | 背景 |
| Scenario | 场景 |
| Scenario Outline | 场景大纲 |
| Examples | 例子 |
| Given | 假如 / 假设 / 假定 |
| When | 当 |
| Then | 那么 |
| And | 并且 / 而且 / 同时 |
| But | 但是 |

### 示例

```gherkin
# language: zh-CN
功能: 自选股管理
  作为用户
  我希望能管理我的自选股列表

  背景:
    假如 应用已启动
    并且 自选股列表已清空

  场景: 添加股票到自选
    当 我在输入框中输入"600519"
    并且 我点击添加按钮
    那么 自选列表应该包含"600519"

  场景大纲: 添加多个股票
    当 我在输入框中输入"<代码>"
    并且 我点击添加按钮
    那么 自选列表应该包含"<代码>"

    例子:
      | 代码   |
      | 000001 |
      | 600000 |
```

---

## 步骤定义模式

### 参数占位符

| 占位符 | 匹配内容 | 示例 |
|--------|----------|------|
| `{string}` | 引号内的文字 | `"自选"` → `自选` |
| `{int}` | 整数 | `123` → `123` |

### 步骤类型

```dart
// Given 步骤
given<WidgetTesterWorld>('应用已启动', (context) async { ... });

// Given 带参数
given1<String, WidgetTesterWorld>('自选列表包含{string}', (code, context) async { ... });

// When 步骤
when<WidgetTesterWorld>('我点击添加按钮', (context) async { ... });

// When 带参数
when1<String, WidgetTesterWorld>('我在输入框中输入{string}', (text, context) async { ... });

// Then 步骤
then<WidgetTesterWorld>('应该显示暂无自选股提示', (context) async { ... });

// Then 带参数
then1<String, WidgetTesterWorld>('自选列表应该包含{string}', (code, context) async { ... });
```

---

## 常见问题

### Q: 测试失败，找不到步骤定义

检查：
1. 步骤文本是否完全匹配（包括空格、引号）
2. 步骤是否已在 `getAllStepDefinitions()` 中注册

### Q: SharedPreferences 状态问题

背景步骤中的 `SharedPreferences.setMockInitialValues({})` 需要在 `pumpWidget` 之前调用。

### Q: 如何调试单个场景

```bash
flutter test integration_test/chinese_bdd_runner.dart -d macos --name "场景名称"
```

---

## 现有步骤定义

### 通用步骤
- `应用已启动` - 启动应用
- `自选股列表已清空` - 清空自选列表
- `我重启应用` - 重启应用
- `当前在自选页` - 验证当前在自选页

### 导航步骤
- `我点击底部导航栏的{string}Tab` - 点击底部 Tab
- `底部导航栏的{string}Tab应该被选中` - 验证 Tab 选中
- `页面应该显示自选列表区域` - 验证自选页面
- `我点击持仓Tab` - 点击持仓 Tab
- `我点击自选Tab` - 点击自选 Tab

### 自选股步骤
- `应该显示暂无自选股提示` - 验证空列表提示
- `我在输入框中输入{string}` - 输入文字
- `我点击添加按钮` - 点击添加
- `应该显示已添加{string}提示` - 验证添加成功
- `自选列表应该包含{string}` - 验证列表包含
- `我长按列表中的{string}` - 长按删除
