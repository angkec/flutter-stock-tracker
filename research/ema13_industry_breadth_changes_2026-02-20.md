# EMA13 行业广度改动总结（2026-02-20）

## 改动目标

- 在行业详情页的 EMA13 行业广度图上支持选中某一天，并显示该天详情。
- 将 EMA13 广度图放到行业详情页的顶部统计/图表区域（个股列表上方）。
- 修复“已选中但看不到详情”的可见性问题。

## 核心代码改动

### 1) 图表交互与选中详情

文件：`lib/widgets/industry_ema_breadth_chart.dart`

- `IndustryEmaBreadthChart` 从静态展示升级为可交互状态组件（`StatefulWidget`）。
- 新增本地选中状态 `_selectedIndex`，并通过 `_resolveIndex(...)` 将点击/拖动位置映射到数据点索引。
- 新增交互入口：
  - `onTapDown`
  - `onHorizontalDragUpdate`
- 新增选中详情区块 `_buildSelectedDetail(...)`，用于展示：
  - 日期
  - 广度百分比
  - Above / Valid / Missing
- 关键测试锚点：
  - `ValueKey('industry_ema_breadth_custom_paint')`
  - `ValueKey('industry_ema_breadth_selected_detail')`
  - `ValueKey('industry_ema_breadth_latest_summary')`

### 2) 行业详情页位置调整

文件：`lib/screens/industry_detail_screen.dart`

- EMA13 广度卡片被放入 `SliverAppBar` 展开区的图表/统计区域，位于“成分股列表”标题之前。
- 卡片容器增加稳定 key：
  - `ValueKey('industry_detail_ema_breadth_card')`
- 这样布局上与其它统计图保持一致，并确保在个股列表之上。

### 3) 详情不可见回归修复

文件：`lib/screens/industry_detail_screen.dart`

- 根因：头部可折叠区域为 EMA 卡片预留高度不足，详情区被裁切。
- 修复：将 `emaBreadthCardHeight` 调整为 `305.0`，给“图表 + 选中详情”足够垂直空间。

## 测试覆盖与验证点

### 图表 Widget 测试

文件：`test/widgets/industry_ema_breadth_chart_test.dart`

- 覆盖项：
  - 最新摘要与阈值文案展示
  - 点击选择日期后显示选中详情
  - 拖动选择行为
  - 空数据场景
  - 百分比空值回退到最近有效点
  - 回归测试：在 `300px+` 容器内，选中详情不被裁切

### 行业详情页测试

文件：`test/screens/industry_detail_screen_test.dart`

- 覆盖项：
  - EMA 广度卡片存在并位于详情页顶部图表区域
  - 图表交互后可看到 `industry_ema_breadth_selected_detail`

### 其他相关测试

- `test/screens/industry_ema_breadth_settings_screen_test.dart`
- `test/integration/industry_ema_breadth_flow_test.dart`
- `test/services/industry_ema_breadth_service_test.dart`
- `test/data/storage/industry_ema_breadth_cache_store_test.dart`
- `test/data/storage/industry_ema_breadth_config_store_test.dart`
- `test/models/industry_ema_breadth_model_test.dart`

## 关联文件清单（本次主题相关）

- `lib/widgets/industry_ema_breadth_chart.dart`
- `lib/screens/industry_detail_screen.dart`
- `lib/services/industry_ema_breadth_service.dart`
- `lib/screens/industry_ema_breadth_settings_screen.dart`
- `lib/providers/market_data_provider.dart`
- `lib/data/storage/industry_ema_breadth_cache_store.dart`
- `lib/data/storage/industry_ema_breadth_config_store.dart`
- `lib/models/industry_ema_breadth.dart`
- `lib/models/industry_ema_breadth_config.dart`
- `test/widgets/industry_ema_breadth_chart_test.dart`
- `test/screens/industry_detail_screen_test.dart`

## 当前结果

- EMA13 广度图已支持“点选/拖动选日 + 详情显示”。
- 行业详情页中 EMA13 广度图已在个股列表上方，和其它统计图同区展示。
- 选中详情不可见问题已修复（高度不足导致的裁切已处理）。
