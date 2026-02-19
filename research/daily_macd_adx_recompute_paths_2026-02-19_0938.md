# 日 MACD / ADX 重算路径研究（2026-02-19）

## 结论摘要
- 数据管理页执行“日K强制全量拉取”后，日 MACD / ADX 的重算在 `MarketDataProvider._syncDailyBars` 的“3/4 计算指标”阶段触发。
- 该阶段通过 `_prewarmDailyIndicatorsConcurrently` 并行调用 `_prewarmDailyMacd` 与 `_prewarmDailyAdx`，最终分别落到 `MacdIndicatorService.prewarmFromBars` 和 `AdxIndicatorService.prewarmFromBars`。
- MACD/ADX 的“重算入口”分别在 `MacdSettingsScreen._recompute` 与 `AdxSettingsScreen._recompute`；两者都走 `prewarmFromRepository` → `prewarmFromBars` → `getOrComputeFromBars` 路径，只是 ADX 在入口处 `forceRecompute: true`，MACD 入口处 `forceRecompute: false` 且 `ignoreSnapshot: true`。

## 1) 数据管理页“强制拉取日K”后的日 MACD / ADX 重算路径

### 入口（UI → 数据同步）
1. `DataManagementScreen._syncDailyForceFull` → `DataManagementScreen._runDailySync(forceFull: true)`
   - 文件：`lib/screens/data_management_screen.dart`
2. `DataManagementScreen._runDailySync` 内部选择：
   - `syncRunner = provider.syncDailyBarsForceFull`
   - 调用 `MarketDataProvider.syncDailyBarsForceFull`
   - 文件：`lib/screens/data_management_screen.dart`

### 数据同步与指标阶段（Provider）
3. `MarketDataProvider.syncDailyBarsForceFull` → `_syncDailyBars(mode: DailyKlineSyncMode.forceFull)`
   - 文件：`lib/providers/market_data_provider.dart`
4. `_syncDailyBars` 主流程（关键阶段）：
   - `1/4` 连接数据源 → `_dailyKlineSyncService.sync(...)`
   - `2/4` 拉取并持久化日K → `_reloadDailyBarsOrThrow(...)`
   - `3/4 计算指标...` → `_detectBreakouts(...)`
   - **随后调用** `_prewarmDailyIndicatorsConcurrently(...)`
   - 文件：`lib/providers/market_data_provider.dart`

### 日 MACD 预热（MACD 分支）
5. `_prewarmDailyIndicatorsConcurrently` → `_prewarmDailyMacd(...)`
   - 文件：`lib/providers/market_data_provider.dart`
6. `_prewarmDailyMacd` → `MacdIndicatorService.prewarmFromBars(...)`
   - 参数：`dataType: KLineDataType.daily`, `barsByStockCode: payload`
   - 文件：`lib/providers/market_data_provider.dart`
7. `MacdIndicatorService.prewarmFromBars`（并发 worker）
   - 逐股调用 `getOrComputeFromBars(..., forceRecompute: forceRecompute || shouldForceForMissingCache)`
   - 对新计算结果使用 `MacdCacheStore.saveAll(...)` 批量落盘
   - 文件：`lib/services/macd_indicator_service.dart`

### 日 ADX 预热（ADX 分支）
8. `_prewarmDailyIndicatorsConcurrently` → `_prewarmDailyAdx(...)`
   - 文件：`lib/providers/market_data_provider.dart`
9. `_prewarmDailyAdx` → `AdxIndicatorService.prewarmFromBars(...)`
   - 参数：`dataType: KLineDataType.daily`, `barsByStockCode: payload`
   - 文件：`lib/providers/market_data_provider.dart`
10. `AdxIndicatorService.prewarmFromBars`（并发 worker）
   - 逐股调用 `getOrComputeFromBars(..., forceRecompute: forceRecompute || shouldForceForMissingCache)`
   - 对新计算结果使用 `AdxCacheStore.saveAll(...)` 批量落盘
   - 文件：`lib/services/adx_indicator_service.dart`

### 关键说明（强制拉取后是否“必定重算”）
- 数据管理页的“强制拉取日K”本身只保证 **日K源数据刷新**。
- 指标阶段调用 `prewarmFromBars` 时并未显式 `forceRecompute: true`。
- 是否实际重算由 `getOrComputeFromBars` 内部缓存校验决定：
  - 若源数据 `sourceSignature` 或 `config` 变化，缓存失效则重算；
  - 否则复用磁盘/内存缓存。

## 2) 日 MACD 重算入口的函数调用路径

### 入口（UI）
1. `MacdSettingsScreen` 点击“重算日线 MACD”按钮 → `_recompute()`
   - 文件：`lib/screens/macd_settings_screen.dart`

### 服务调用链
2. `_recompute()` → `MacdIndicatorService.prewarmFromRepository(...)`
   - 参数：
     - `dataType: KLineDataType.daily`
     - `dateRange: _buildRecomputeDateRange()`
     - `forceRecompute: false`
     - `ignoreSnapshot: true`
   - 文件：`lib/screens/macd_settings_screen.dart`
3. `MacdIndicatorService.prewarmFromRepository`：
   - 分批调用 `DataRepository.getKlines(...)`
   - 对每批调用 `prewarmFromBars(...)`
   - 文件：`lib/services/macd_indicator_service.dart`
4. `MacdIndicatorService.prewarmFromBars`：
   - worker 中调用 `getOrComputeFromBars(..., forceRecompute: forceRecompute || shouldForceForMissingCache)`
   - 计算结果通过 `MacdCacheStore.saveAll(...)` 批量写盘
   - 文件：`lib/services/macd_indicator_service.dart`

## 3) 日 ADX 重算入口的函数调用路径

### 入口（UI）
1. `AdxSettingsScreen` 点击“重算日线 ADX”按钮 → `_recompute()`
   - 文件：`lib/screens/adx_settings_screen.dart`

### 服务调用链
2. `_recompute()` → `AdxIndicatorService.prewarmFromRepository(...)`
   - 参数：
     - `dataType: KLineDataType.daily`
     - `dateRange: _buildRecomputeDateRange()`
     - `forceRecompute: true`
   - 文件：`lib/screens/adx_settings_screen.dart`
3. `AdxIndicatorService.prewarmFromRepository`：
   - 分批调用 `DataRepository.getKlines(...)`
   - 对每批调用 `prewarmFromBars(...)`
   - 文件：`lib/services/adx_indicator_service.dart`
4. `AdxIndicatorService.prewarmFromBars`：
   - worker 中调用 `getOrComputeFromBars(..., forceRecompute: forceRecompute || shouldForceForMissingCache)`
   - 计算结果通过 `AdxCacheStore.saveAll(...)` 批量写盘
   - 文件：`lib/services/adx_indicator_service.dart`

## 4) 相关文件索引
- 数据管理页：`lib/screens/data_management_screen.dart`
- 日K同步与指标预热：`lib/providers/market_data_provider.dart`
- MACD 服务：`lib/services/macd_indicator_service.dart`
- ADX 服务：`lib/services/adx_indicator_service.dart`
- MACD 重算入口：`lib/screens/macd_settings_screen.dart`
- ADX 重算入口：`lib/screens/adx_settings_screen.dart`
