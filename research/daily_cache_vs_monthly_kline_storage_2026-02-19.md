# 日K daily cache vs 月度K线文件：差异与选型结论（2026-02-19）

## 结论（针对“全量计算”）
如果需要全量计算或任意历史区间读取，必须使用“月度K线文件 + 元数据”路径。`daily cache` 只保留最近窗口数据，不满足全量要求。

## 两套存储的定位与范围

### 1) Daily cache（JSON 文件，最近窗口）
- **位置**：应用文档目录 `market_data/klines/daily_cache/*.json`
- **内容范围**：只保留最近窗口（默认 `targetBars=260`、`lookbackMonths=18`）
- **写入入口**：`DailyKlineSyncService.sync` → `DailyKlineCacheStore.saveAll`
- **读取入口**：`DailyKlineReadService.readOrThrow` → `DailyKlineCacheStore.loadForStocksWithStatus`
- **典型用途**：日K强制拉取后快速加载到 `_dailyBarsCache`，并在内存里直接预热指标
- **关键特性**：
  - 不写 `kline_files` 元数据
  - 不走 `MarketDataRepository.getKlines`
  - 读取逻辑基于 `anchorDate` + `targetBars` 的“最近窗口裁剪”

### 2) 月度K线文件（gzip 二进制 + 元数据）
- **位置**：应用文档目录 `market_data/klines/*_daily_YYYYMM.bin.gz`
- **内容范围**：按月分片，可覆盖全量历史
- **写入入口**：`MarketDataRepository.fetchMissingData/refetchData` → `_metadataManager.saveKlineData`
- **读取入口**：`MarketDataRepository.getKlines` → `_metadataManager.loadKlineData`
- **典型用途**：全量历史读取、任意 `DateRange` 查询、交易日推断等
- **关键特性**：
  - 依赖 `kline_files` 元数据（起止时间、记录数）
  - 支持任意区间加载（跨多月）
  - 是 `DataRepository` 的统一来源

## 对“指标重算”影响
- 设置页“MACD/ADX 重算”走 `getKlines`，即**依赖月度文件**。
- 数据管理页“日K强制拉取”写入 `daily cache`，不会自动生成月度文件。
- 所以当月度文件为空时，指标重算会运行但取到 `bars=0`。

## 选型建议（基于你的需求）
- **需要全量计算** → 必须使用“月度K线文件”路径。
- `daily cache` 只能作为“最近窗口快速读取”的辅助缓存，不适合作为全量指标的唯一来源。

## 关键代码位置（便于进一步确认）
- `lib/data/storage/daily_kline_cache_store.dart`
- `lib/services/daily_kline_sync_service.dart`
- `lib/services/daily_kline_read_service.dart`
- `lib/data/storage/kline_metadata_manager.dart`
- `lib/data/storage/kline_file_storage.dart`
- `lib/data/repository/market_data_repository.dart`
- `lib/providers/market_data_provider.dart`

