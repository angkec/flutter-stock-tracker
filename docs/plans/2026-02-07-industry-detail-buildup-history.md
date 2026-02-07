# Industry Detail Buildup History Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在行业详情页接入建仓雷达数据，并展示该行业可用的全部历史记录。

**Architecture:** 在存储层增加“按行业查询全部历史记录”接口；在 `IndustryBuildUpService` 增加行业历史缓存与加载方法；在 `IndustryDetailScreen` 增加建仓雷达历史卡片并触发加载。

**Tech Stack:** Flutter, Provider, sqflite, existing IndustryBuildUp domain model.

---

### Task 1: 先写失败测试覆盖新能力

**Files:**
- Modify: `test/services/industry_buildup_service_test.dart`
- Create: `test/screens/industry_detail_screen_test.dart`

**Step 1: Write failing service test**
- 新增用例：`loadIndustryHistory` 读取行业全历史，按日期倒序，且可通过 getter 获取。

**Step 2: Run test to verify it fails**
Run: `flutter test test/services/industry_buildup_service_test.dart`
Expected: FAIL（缺少历史加载 API / 行为不满足）。

**Step 3: Write failing screen test**
- 新增用例：行业详情页显示“建仓雷达历史”并渲染历史条目。

**Step 4: Run test to verify it fails**
Run: `flutter test test/screens/industry_detail_screen_test.dart`
Expected: FAIL（详情页尚未展示建仓雷达历史）。

### Task 2: 最小实现存储与服务

**Files:**
- Modify: `lib/data/storage/industry_buildup_storage.dart`
- Modify: `lib/services/industry_buildup_service.dart`

**Step 1: Add storage query**
- 增加 `getIndustryHistory(industry)`，返回该行业所有 `IndustryBuildupDailyRecord`（按 `date DESC, rank ASC`）。

**Step 2: Add service cache + loader**
- 增加 `loadIndustryHistory/hasIndustryHistory/isIndustryHistoryLoading/getIndustryHistory`。
- 在重算后清理历史缓存，避免脏读。

**Step 3: Run service tests**
Run: `flutter test test/services/industry_buildup_service_test.dart`
Expected: PASS.

### Task 3: 接入详情页 UI

**Files:**
- Modify: `lib/screens/industry_detail_screen.dart`

**Step 1: Render buildup history card**
- 在详情页头部增加 `建仓雷达历史` 卡片。
- 卡片中展示全部历史数据（可滚动），每条显示日期、Z值、广度、Q、名次。

**Step 2: Trigger lazy load**
- 首次进入详情页时，如果该行业历史未加载，触发 `loadIndustryHistory`。

**Step 3: Run target tests**
Run: `flutter test test/screens/industry_detail_screen_test.dart`
Expected: PASS.

### Task 4: 全量回归与静态检查

**Files:**
- Modify: `lib/...` and `test/...` (above)

**Step 1: Run focused suite**
Run: `flutter test test/services/industry_buildup_service_test.dart test/screens/industry_detail_screen_test.dart test/widgets/industry_buildup_list_test.dart`
Expected: PASS.

**Step 2: Run analyzer**
Run: `flutter analyze`
Expected: 0 issues.
