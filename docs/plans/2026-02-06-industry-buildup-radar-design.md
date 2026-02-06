# 行业建仓雷达设计

日期：2026-02-06  
状态：已确认（可进入实现）

## 1. 目标与范围

在 `行业` 页新增第三个子 Tab：`建仓雷达`，与现有 `行业统计 | 排名趋势` 并列，用于盘后日级扫描“主力可能在建仓的行业”。

算法采用 `docs/stock-dailyk-spec.md` 的分钟 K 行业聚合方案，输出以下核心指标：
- `Z_rel`：行业相对市场的异常买入强度（主排序信号）
- `breadth`：行业内部同向偏买广度
- `Q`：可信度评分

第一版明确边界：
- 仅做盘后日级扫描，不做盘中滚动扫描
- 榜单默认按 `Z_rel` 降序
- 展示“最新榜单 + 近 20 日 `Z_rel` 趋势线”
- 结果过期时仅提示，不自动重算
- 手动重算按钮只放在 `建仓雷达` Tab
- 重算按钮运行中显示实际进度，格式为 `阶段名 current/total`

## 2. 方案选型与分层

采用独立计算服务方案：
- 新增 `IndustryBuildUpService`（计算层）
- 保持 `IndustryRankService` 现有职责不变
- 数据读取统一走 `DataRepository`
- 结果层持久化写入 SQLite（非 SharedPreferences）

原因：
- 与现有“数据层 / 计算层 / 展示层”重构方向一致
- 不把业务算法塞进 `MarketDataProvider` 或 `DataRepository`
- 避免“排名趋势”与“建仓雷达”相互耦合
- 后续参数调优、回测、扩展策略更可控

## 3. 架构与数据流

流程分为 5 个阶段：
1. `准备数据`：加载行业映射、交易日列表、股票池
2. `预处理`：按股票逐日计算个股日特征（`X_hat` 等）
3. `行业聚合`：计算 `X_I`、`X_M`、`X_rel`
4. `计算评分`：滚动 `Z_rel` + `breadth` + `Q`
5. `写入结果`：批量事务写入 SQLite

触发策略：
- 监听 `DataRepository.dataUpdatedStream`
- 收到更新后仅标记 `isStale=true`
- 进入 `建仓雷达` Tab 时不自动重算
- 用户点击“重算”后执行 `recalculate(force: true)`

缓存策略：
- 中间特征缓存（个股日特征）只保存在内存
- 以 `dataVersion` 做失效判断
- 结果缓存持久化在 SQLite，供榜单与趋势线直接查询

## 4. 数据模型（SQLite）

数据库版本从 `2` 升级到 `3`，新增表 `industry_buildup_daily`：

```sql
CREATE TABLE industry_buildup_daily (
  date INTEGER NOT NULL,            -- 交易日（00:00 时间戳）
  industry TEXT NOT NULL,           -- 行业名
  z_rel REAL NOT NULL,              -- 异常强度
  breadth REAL NOT NULL,            -- 广度 [0,1]
  q REAL NOT NULL,                  -- 可信度 [0,1]
  x_i REAL NOT NULL,                -- 行业压力原值
  x_m REAL NOT NULL,                -- 市场压力原值
  passed_count INTEGER NOT NULL,    -- 通过过滤的成份股数
  member_count INTEGER NOT NULL,    -- 行业总成份股数
  rank INTEGER NOT NULL,            -- 当日按 z_rel 排名（1-based）
  updated_at INTEGER NOT NULL,      -- 写入时间
  PRIMARY KEY (date, industry)
);

CREATE INDEX idx_buildup_date_rank
ON industry_buildup_daily(date, rank);

CREATE INDEX idx_buildup_industry_date
ON industry_buildup_daily(industry, date);
```

新增存储类 `IndustryBuildUpStorage`（`lib/data/storage/industry_buildup_storage.dart`）：
- `upsertDailyResults(List<IndustryBuildUpDailyRecord>)`
- `getLatestDate()`
- `getLatestBoard({int limit})`
- `getIndustryTrend(String industry, {int days = 20})`
- `clearAll()`

## 5. 计算服务设计

新增 `lib/services/industry_buildup_service.dart`，核心职责：
- 组织扫描流程并对外暴露进度状态
- 执行分钟 K 到行业结果的计算
- 持久化/查询榜单与趋势数据
- 处理“过期但可展示旧结果”的状态

建议公开状态：
- `bool isCalculating`
- `bool isStale`
- `String stageLabel`（准备数据/预处理/行业聚合/计算评分/写入结果）
- `int progressCurrent`
- `int progressTotal`
- `String? errorMessage`
- `DateTime? latestResultDate`
- `DateTime? lastComputedAt`

建议公开接口：
- `Future<void> load()`
- `Future<void> recalculate({bool force = false})`
- `List<IndustryBuildUpBoardItem> getLatestBoard()`
- `List<double> getZRelTrend(String industry, {int days = 20})`
- `void markStale()`

进度文案约定：
- Tab 按钮在运行中显示：`$stageLabel $progressCurrent/$progressTotal`
- 例如：`预处理 320/1200`

## 6. 算法与参数

算法按 `docs/stock-dailyk-spec.md` 实现，不改口径：
- 个股分钟压力：`p = volume * tanh(r / tau)`，`r = ln(close_t / close_t-1)`
- 个股日归一化压力：`X_hat = Σp / (Σvolume + delta)`
- Hard Filters：`minDailyAmount`、`minMinuteCoverage`、`maxMinuteVolShare`
- 行业聚合：`amount` 权重 + `w_max` 封顶 + 归一化
- 市场基准：`X_M`（全市场通过过滤股票均值）
- 相对值：`X_rel = X_I - X_M`
- 异常：滚动窗口 `W` 的 `Z_rel`
- 结构：`breadth = count(X_hat > 0) / passedCount`
- 可信度：`Q = Q_coverage * Q_breadth * Q_conc * Q_persist`

第一版参数使用代码常量（不做 UI 配置）：
- `tau=0.001`
- `W=20`
- `minDailyAmount=2e7`
- `minMinuteCoverage=0.9`（expected=240）
- `maxMinuteVolShare=0.12`
- `w_max=0.08`
- `breadthLow=0.30`，`breadthHigh=0.55`
- `minPassedMembers=8`
- `HHI0=0.06`，`lambda=12`
- `persist: L=5, persistZ=1.0, persistNeed=3`

## 7. UI 设计（建仓雷达 Tab）

行业页改为 3 子 Tab：
- `行业统计`
- `排名趋势`
- `建仓雷达`（新增）

`建仓雷达` 结构：
- 顶部状态条：展示数据日期、过期提示、错误提示、上次计算时间
- 右上角手动重算按钮（仅此处）
  - 空闲：`重算`
  - 运行中：禁用 + `阶段名 current/total`（如 `预处理 320/1200`）
- 榜单列表（最新交易日）：
  - 行业名
  - `Z_rel`
  - `breadth`
  - `Q`
  - 20 日 `Z_rel` sparkline

交互行为：
- 结果过期时显示 warning，不自动重算
- 重算失败时保留旧榜单并显示错误
- 点击行业行进入现有 `IndustryDetailScreen`

## 8. 错误处理与一致性

- 重算异常不清空旧结果，保障可用性
- 写库采用单事务批量写入，失败整体回滚
- 若某行业当日有效样本不足（`passedCount < minPassedMembers`），允许落库但由 `Q` 降低可信度
- 缺失数据情况下，趋势线允许断点，不做伪补齐

## 9. 代码改动清单（计划）

新增：
- `lib/services/industry_buildup_service.dart`
- `lib/models/industry_buildup.dart`
- `lib/data/storage/industry_buildup_storage.dart`
- `lib/widgets/industry_buildup_list.dart`
- `test/services/industry_buildup_service_test.dart`
- `test/data/storage/industry_buildup_storage_test.dart`

修改：
- `lib/data/storage/database_schema.dart`（版本 + 新表 + 索引）
- `lib/data/storage/market_database.dart`（v2->v3 升级逻辑）
- `lib/main.dart`（注册 `IndustryBuildUpService`）
- `lib/screens/industry_screen.dart`（Tab 扩展为 3，接入建仓雷达）

## 10. 验收标准

功能验收：
- 行业页存在第三个 `建仓雷达` Tab
- 能显示最新榜单与每行业 20 日 `Z_rel` 趋势线
- 重算按钮运行中显示 `阶段名 current/total`
- 结果过期仅提示，不自动重算
- 手动重算后榜单刷新

数据验收：
- 结果持久化在 SQLite 新表
- 重启 App 后榜单与趋势可恢复
- 数据更新事件触发后状态变为过期

质量验收：
- 核心算法单测通过
- SQLite 读写/排序/趋势查询单测通过
- 进度状态流转与错误回退单测通过
