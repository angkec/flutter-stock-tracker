# 指标接口梳理（现有系统）

> 仅描述当前实现中的接口与调用路径，不包含新增设计。

## 1. 核心数据接口（K 线来源）

**数据仓库接口**
- `DataRepository.getKlines({stockCodes, dateRange, dataType})`
  - 日/周线都通过 `dataType: KLineDataType.daily|weekly` 区分。
  - 文件：`lib/data/repository/data_repository.dart`

**周线本地优先读取（个股详情页）**
- 详情页读取周K时，先从 `DataRepository.getKlines` 本地缓存读取，若不足再 `fetchMissingData` 补齐，再重读。
- 文件：`lib/screens/stock_detail_screen.dart`

## 2. 指标服务接口（MACD/ADX 现状）

**MACD**
- 服务：`MacdIndicatorService`
- 关键接口：
  - `load()`：读取日/周配置
  - `configFor(dataType)`：取日/周参数
  - `getOrComputeFromRepository({stockCode, dataType, dateRange})`
  - `getOrComputeFromBars({stockCode, dataType, bars, ...})`
  - `prewarmFromBars({dataType, barsByStockCode, ...})`
  - `prewarmFromRepository({stockCodes, dataType, dateRange, ...})`
- 文件：`lib/services/macd_indicator_service.dart`

**ADX**
- 服务：`AdxIndicatorService`
- 关键接口与 MACD 对称：`load/configFor/getOrCompute*/prewarm*`
- 文件：`lib/services/adx_indicator_service.dart`

## 3. 指标缓存接口（磁盘与内存）

**内存缓存**
- 两个服务各自维护 `_memoryCache`，以 `stockCode + dataType` 为 key。
- 文件：
  - `lib/services/macd_indicator_service.dart`
  - `lib/services/adx_indicator_service.dart`

**磁盘缓存**
- MACD：`MacdCacheStore`
  - `saveSeries` / `saveAll` / `loadSeries` / `listStockCodes`
  - 缓存文件名：`${stockCode}_${dataType.name}_macd_cache.json`
  - 子目录：`market_data/klines/macd_cache`
  - 文件：`lib/data/storage/macd_cache_store.dart`
- ADX：`AdxCacheStore`
  - 同上结构
  - 子目录：`market_data/klines/adx_cache`
  - 文件：`lib/data/storage/adx_cache_store.dart`

**缓存根目录**
- 由 `KLineFileStorage` 统一提供，根目录为：`market_data/klines`
- 文件：`lib/data/storage/kline_file_storage.dart`

## 4. 日线预热接口（MarketDataProvider）

- `MarketDataProvider` 持有指标服务引用：
  - `setMacdService(...)`
  - `setAdxService(...)`
  - 文件：`lib/providers/market_data_provider.dart`

- 日线预热入口：
  - `_prewarmDailyMacd(...)`
  - `_prewarmDailyAdx(...)`
  - `_prewarmDailyIndicatorsConcurrently(...)`
- 日K数据来源：`_dailyBarsCache`，由 `DailyKlineReadService` 从日K文件缓存读取。
- 文件：
  - `lib/providers/market_data_provider.dart`
  - `lib/services/daily_kline_read_service.dart`

## 5. 周线预热接口（数据管理页面）

- 在周K拉取完成后，按需调用指标服务：
  - `macdService.prewarmFromRepository(...)`
  - `adxService.prewarmFromRepository(...)`
- 文件：`lib/screens/data_management_screen.dart`

## 6. 指标参数与手动重算接口

- MACD 参数页面：`MacdSettingsScreen`
  - 调 `MacdIndicatorService.updateConfigFor` / `prewarmFromRepository`
  - 文件：`lib/screens/macd_settings_screen.dart`
- ADX 参数页面：`AdxSettingsScreen`
  - 调 `AdxIndicatorService.updateConfigFor` / `prewarmFromRepository`
  - 文件：`lib/screens/adx_settings_screen.dart`

## 7. 详情图调用接口

- 个股详情页显示指标子图：
  - `MacdSubChart` / `AdxSubChart`
  - 传入 `dataType` 决定日/周线
- 子图直接从 `MacdCacheStore.loadSeries` / `AdxCacheStore.loadSeries` 读取磁盘缓存，不触发计算。
- 文件：
  - `lib/screens/stock_detail_screen.dart`
  - `lib/widgets/macd_subchart.dart`
  - `lib/widgets/adx_subchart.dart`

## 8. 筛选任务相关接口（现状）

- 当前筛选/选股逻辑主要使用 `StockMonitorData` 的标记字段（如 `isBreakout`, `isPullback`），未直接读取 MACD/ADX 缓存。
- 文件：
  - `lib/services/stock_service.dart`（`StockMonitorData`）
  - `lib/screens/breakout_screen.dart`
  - `lib/providers/market_data_provider.dart`
