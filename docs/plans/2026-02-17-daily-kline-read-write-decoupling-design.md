# 日K读写解耦重构设计（按钮触发拉取 + 只读文件缓存）

## 1. 背景与目标

当前日K链路在 `MarketDataProvider` 内混合了三类职责：

1. 网络拉取（TDX）
2. 文件落盘与缓存管理
3. 回踩/突破/MACD/ADX 的读取与计算编排

虽然已有“日K大数据不再存 SharedPreferences”的迁移，但仍存在职责边界不够硬的问题：读取路径与拉取路径容易在后续迭代中再次耦合。此次重构目标是建立强约束：

1. 日K网络拉取只能被显式触发（且仅在数据管理页按钮触发）
2. 日K读取路径一律只读本地文件缓存，不触发任何网络行为
3. 日K序列数据不允许进入 SharedPreferences
4. SharedPreferences 仅存日K轻量检查点
5. 对缺失/损坏缓存采用硬失败策略（抛错并中断批处理）
6. 通过 unit test + e2e test 证明行为达标

## 2. 约束与范围

### 2.1 本次范围（In Scope）

1. 数据管理页 `日K数据` 改为两个显式按钮：`增量拉取`、`强制全量拉取`
2. 新增日K同步服务（仅触发拉取与落盘）
3. 新增日K读取服务（仅文件读取与校验）
4. `MarketDataProvider` 重构为编排层，不再直接包含日K网络拉取逻辑
5. 回踩/突破/MACD/ADX 预热链路统一走日K读取服务
6. 删除日K序列相关 SharedPreferences 读写
7. 保留并规范日K轻量检查点
8. 补齐 unit/e2e 验收

### 2.2 非范围（Out of Scope）

按需求确认，本轮不改以下模块：

1. `lib/screens/stock_detail_screen.dart` 中日K直连网络读取逻辑
2. `lib/services/ai_analysis_service.dart` 中日K直连网络读取逻辑

说明：这两处后续可单独开票推进“全应用统一只读缓存”。

## 3. 方案对比与结论

### 3.1 候选方案

1. 最小改动：仅在 Provider 内加分支与限制
2. 边界清晰：抽离 `SyncService` + `ReadService`（推荐）
3. 仓库层全面升级：重塑 DataRepository 契约

### 3.2 选择方案

采用方案 2（边界清晰），原因：

1. 能在当前范围内建立稳定契约，避免“读取链路误触网”回归
2. 改动面可控，较方案 3 风险更低
3. 可通过单元测试直接验证“读取 0 次网络调用”

## 4. 目标架构

### 4.1 新增组件

#### `DailyKlineSyncService`（只负责触发拉取）

职责：

1. 接收显式触发命令：`incremental` / `forceFull`
2. 执行网络拉取（通过 `TdxPool`）
3. 执行文件落盘（通过 `DailyKlineCacheStore`）
4. 更新轻量检查点（通过 `SharedPreferences` 检查点存储）
5. 返回成功/失败汇总结果和结构化进度事件

约束：

1. 不提供任何读取接口
2. 不参与业务指标计算

#### `DailyKlineReadService`（只负责读取缓存）

职责：

1. 读取指定股票日K文件
2. 对读取结果做完整性校验（存在性、可解析、排序、窗口覆盖）
3. 读取失败时抛结构化异常并中断调用方流程

约束：

1. 禁止调用 `TdxClient` / `TdxPool`
2. 禁止任何隐式修复拉取

### 4.2 编排层

`MarketDataProvider` 仅保留：

1. UI 状态管理
2. 调用 `DailyKlineSyncService` 触发拉取
3. 调用 `DailyKlineReadService` 读取并驱动回踩/突破/指标预热

Provider 不再包含“直接下载日K”实现细节。

## 5. 数据流与状态机

### 5.1 同步状态机（触网链路）

`idle -> connecting -> fetching -> persisting -> checkpointing -> completed/failed`

触发入口：

1. 数据管理页 `增量拉取`
2. 数据管理页 `强制全量拉取`

关键规则：

1. 仅按钮触发进入状态机
2. 允许部分成功：单股成功即落盘并更新该股检查点
3. 存在失败时返回聚合失败信息（不回滚已成功股）

### 5.2 读取状态机（只读链路）

`idle -> loading_files -> validating -> ready/failed`

触发入口：

1. 回踩重算
2. 突破重算
3. MACD/ADX 日线预热

关键规则：

1. 不允许触发网络
2. 任意股票文件缺失/损坏即失败并中断批处理

## 6. 模式定义（增量/全量）

### 6.1 增量拉取

1. 根据每股检查点判断是否需要刷新
2. 仅拉取 `stocksToFetch`
3. 成功股覆盖写入文件并更新该股检查点
4. 失败股记录原因并汇总返回

### 6.2 强制全量拉取

1. 忽略每股检查点
2. 对目标股票全部拉取固定窗口（默认近 260 根）
3. 原子替换对应缓存文件
4. 更新全局检查点和每股检查点

## 7. SharedPreferences 策略

### 7.1 明确保留（轻量检查点）

建议统一前缀：`daily_kline_checkpoint_*`

全局：

1. `daily_kline_checkpoint_last_success_date`（例如 `2026-02-17`）
2. `daily_kline_checkpoint_last_mode`（`incremental` / `force_full`）
3. `daily_kline_checkpoint_last_success_at_ms`（毫秒时间戳）

按股：

1. `daily_kline_checkpoint_per_stock_last_success_at_ms`（JSON map: `code -> ms`）

### 7.2 必须删除（禁止项）

1. 任意日K序列 payload（JSON 数组、压缩串、大对象）
2. 历史遗留 `daily_bars_cache_v1` 的读写依赖（仅保留一次性清理）

## 8. 错误模型

新增结构化异常：

`DailyKlineReadException`

字段建议：

1. `stockCode`
2. `reasonCode`（`missing_file` / `corrupted_json` / `invalid_order` / `insufficient_bars`）
3. `message`

行为约束：

1. 读取失败直接抛出，不做静默降级
2. 调用方必须终止当前批处理并向 UI 返回明确错误文案

## 9. UI 交互调整（数据管理页）

`日K数据` 卡片按钮调整：

1. 主按钮：`增量拉取`
2. 次按钮：`强制全量拉取`（保留确认弹窗）

反馈规则：

1. 成功：展示成功提示
2. 部分失败：展示“部分成功 + 失败股票数”
3. 全失败：展示失败原因摘要

进度展示保留四阶段语义（可继续沿用现有文案格式）：

1. 拉取
2. 文件写入
3. 指标/衍生计算
4. 保存检查点

## 10. 测试设计

### 10.1 Unit Tests

### A. `DailyKlineReadService` 读路径

1. `read_success_when_files_valid`
2. `throws_missing_file_when_file_absent`
3. `throws_corrupted_json_when_payload_invalid`
4. `throws_invalid_order_when_bars_not_sorted`
5. `network_call_count_should_be_zero_during_read`

### B. `DailyKlineSyncService` 触发路径

1. `incremental_fetch_only_targets_missing_or_stale_stocks`
2. `force_full_fetch_overwrites_all_target_files`
3. `partial_success_updates_success_stocks_and_collects_failures`
4. `checkpoint_should_update_global_and_per_stock_on_success`

### C. `MarketDataProvider` 编排

1. `daily_recompute_should_use_read_service_only`
2. `should_abort_indicator_pipeline_when_daily_read_fails`
3. `no_auto_fetch_should_happen_on_read_path`

### 10.2 E2E Tests

在 `integration_test/features/data_management_offline_test.dart` 扩展场景：

1. `tap_incremental_daily_fetch_should_trigger_network_once`
2. `without_tap_daily_buttons_should_not_fetch_daily_from_network`
3. `tap_force_full_daily_fetch_should_complete_with_staged_progress`
4. `corrupted_daily_file_should_fail_recompute_and_show_error`
5. `partial_success_should_show_summary_and_allow_retry_failed_only`

验收重点：

1. 拉取触发语义正确
2. 读取失败硬中断
3. 审计事件与进度文案保持稳定

## 11. 迁移与实施建议

建议按以下顺序实施，减少回归风险：

1. 先引入 `DailyKlineReadService`，将现有读取点切换为只读服务
2. 再引入 `DailyKlineSyncService`，替换 Provider 内拉取实现
3. 修改数据管理页按钮与交互
4. 删除日K SharedPreferences 重负载代码
5. 补全单测与 e2e

## 12. 验收标准（Definition of Done）

满足以下条件才可宣告完成：

1. 数据管理页存在两个日K按钮：`增量拉取`、`强制全量拉取`
2. 日K读取链路测试证明网络调用次数为 0
3. 缺失/损坏日K文件会抛结构化错误并中断当前批处理
4. SharedPreferences 中无日K序列缓存，仅保留轻量检查点
5. 相关 unit tests 全绿
6. 相关 e2e tests 全绿
