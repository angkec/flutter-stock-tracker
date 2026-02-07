# Adaptive Top-K Calibration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为行业建仓雷达新增“每周至少一个建仓候选”的自适应阈值配置输出，支持 UI 直接消费 `thresholds/candidates/status`。

**Architecture:** 在 `lib/models` 新增自适应周配置数据模型，在 `lib/services` 新增纯算法模块（breadth 门控、score、topK、percentile、阈值反推、status 判定），并由 `IndustryBuildUpService` 暴露最新周配置。UI 先接入状态与阈值展示字段，候选榜复用现有榜单数据结构。

**Tech Stack:** Flutter/Dart, flutter_test

---

### Task 1: 新增算法与数据模型测试（RED）

**Files:**
- Create: `test/services/adaptive_topk_calibrator_test.dart`

**Step 1: Write the failing test**
- 覆盖 `fBreadth` 截断逻辑、`computeScore`、`selectTopK`、`percentile` 插值、`deriveThresholdsFromCandidates` floor+buffer。
- 覆盖 `buildWeeklyConfig` 的 `strong/weak/none` 判定、NaN/null 过滤、`week` key 稳定性。

**Step 2: Run test to verify it fails**
- Run: `flutter test test/services/adaptive_topk_calibrator_test.dart`
- Expected: FAIL（模块/类型不存在）。

### Task 2: 实现自适应算法模块（GREEN）

**Files:**
- Create: `lib/models/adaptive_weekly_config.dart`
- Create: `lib/services/adaptive_topk_calibrator.dart`

**Step 1: Write minimal implementation**
- 定义参数对象（k/floors/buffers/winner margin/z_p95/minRecords）。
- 实现函数清单：`fBreadth`、`computeScore`、`selectTopK`、`deriveThresholdsFromCandidates`、`percentile`、`buildWeeklyConfig`。
- 输出结构包含：`week/mode/k/floors/thresholds/candidates/status`。

**Step 2: Run tests for green**
- Run: `flutter test test/services/adaptive_topk_calibrator_test.dart`
- Expected: PASS。

### Task 3: 接入 IndustryBuildUpService 并增加回归测试（RED/GREEN）

**Files:**
- Modify: `lib/services/industry_buildup_service.dart`
- Modify: `test/services/industry_buildup_service_test.dart`

**Step 1: Write failing integration tests**
- 在 `recalculate` 后断言 service 可提供本周 adaptive config。
- 验证数据不足/弱周会得到 `none` 或 `weak`。

**Step 2: Implement minimal service wiring**
- service 在加载某日榜单时，抓取最近 5 交易日记录，调用 calibrator 生成 `_latestWeeklyAdaptiveConfig`。
- 暴露 getter 给 UI。

**Step 3: Run tests**
- Run: `flutter test test/services/industry_buildup_service_test.dart`
- Expected: PASS。

### Task 4: UI 字段接入与 Widget 测试（RED/GREEN）

**Files:**
- Modify: `lib/widgets/industry_buildup_list.dart`
- Modify: `test/widgets/industry_buildup_list_test.dart`

**Step 1: Write failing widget tests**
- 校验 `status` 显示（`strong/weak/none` 对应文案）。
- 校验阈值行展示 `z/q/breadth`。

**Step 2: Implement minimal UI wiring**
- 顶部状态栏增加 adaptive status 与 thresholds 的轻量展示。
- 不改变现有主列表交互。

**Step 3: Run tests**
- Run: `flutter test test/widgets/industry_buildup_list_test.dart`
- Expected: PASS。

### Task 5: 全量回归与收尾

**Files:**
- Modify: `docs/plans/2026-02-07-adaptive-topk-calibration-implementation.md`（必要时更新验证结果）

**Step 1: Run regression checks**
- Run: `flutter test test/services/adaptive_topk_calibrator_test.dart test/services/industry_buildup_service_test.dart test/widgets/industry_buildup_list_test.dart`
- Expected: PASS。

**Step 2: Sanity check formatting/analyze（可选）**
- Run: `dart format lib/models/adaptive_weekly_config.dart lib/services/adaptive_topk_calibrator.dart lib/services/industry_buildup_service.dart test/services/adaptive_topk_calibrator_test.dart`
- Run: `flutter analyze`（若耗时过长可跳过并说明）。
