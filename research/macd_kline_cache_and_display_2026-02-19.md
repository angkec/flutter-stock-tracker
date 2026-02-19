# 周K/日K MACD 缓存与个股详情显示研究

## 结论概览
- 周K/日K 的 MACD 采用"内存 + 磁盘"双层缓存，磁盘按"股票 + 数据类型"分文件存 JSON。
- 个股详情不现场计算 MACD，而是直接读取缓存；再按 K 线可视区间对齐日期后绘制。

## 缓存结构与落盘
- 双层缓存：`MacdIndicatorService` 内部 `_memoryCache`（键为 `stockCode + dataType`）+ `MacdCacheStore` 磁盘缓存。
- 磁盘目录：`KLineFileStorage` 的 base 目录下建立 `macd_cache/` 子目录。
- 文件命名：`{stockCode}_{daily|weekly}_macd_cache.json`。
- 写入方式：`AtomicFileWriter` 原子写入，避免部分写导致的损坏。
- 缓存数据结构：`MacdCacheSeries` 包含 `config / sourceSignature / points / updatedAt`。

代码参考：
- `lib/services/macd_indicator_service.dart`
- `lib/data/storage/macd_cache_store.dart`
- `lib/data/storage/kline_file_storage.dart`

## 缓存一致性校验
- 计算 `sourceSignature`：基于 K 线 `close` 与 `datetime` + MACD 配置组合，生成滚动校验签名。
- 读取缓存时同时比对 `sourceSignature` 和 `config`，完全一致才复用；否则重算并覆盖缓存。
- `sourceSignature` 里包含：
  - fast/slow/signal/window
  - bars 长度
  - 首尾时间戳
  - rolling hash

代码参考：
- `lib/services/macd_indicator_service.dart`

## 日K MACD 预热路径
- 日K 缓存来自 `MarketDataProvider` 的 `_dailyBarsCache`。
- `_prewarmDailyMacd` 调用 `MacdIndicatorService.prewarmFromBars`，批量计算并落盘。
- 默认只补齐"没有磁盘缓存"的股票（不强制重算）。

代码参考：
- `lib/providers/market_data_provider.dart`
- `lib/services/macd_indicator_service.dart`

## 周K MACD 预热路径
- 周K 缓存来自数据管理页的周K同步流程。
- `MacdIndicatorService.prewarmFromRepository` 以批次从仓库拉取周K并计算落盘。
- 使用 SharedPreferences 的预热快照（`macd_prewarm_weekly_snapshot_v1`）决定是否整批跳过。
- 手动重算会 `ignoreSnapshot: true`，避免被快照短路。

代码参考：
- `lib/screens/data_management_screen.dart`
- `lib/screens/macd_settings_screen.dart`
- `lib/services/macd_indicator_service.dart`

## 日/周配置差异
- 日K默认 `windowMonths=3`，周K默认 `windowMonths=12`。
- 周K会强制归一化 `windowMonths`，并写回配置。
- 配置变化会清空内存缓存并写入 SharedPreferences。

代码参考：
- `lib/services/macd_indicator_service.dart`
- `lib/models/macd_config.dart`

## 个股详情展示原理
- 非联动模式：`StockDetailScreen` 用 `KLineChartWithSubCharts`，将 `MacdSubChart` 作为子图。
- 联动模式：`LinkedDualKlineView` 上下两张图分别挂 `MacdSubChart`（周K/日K）。
- `MacdSubChart` 在 `initState` / `didUpdateWidget` 时异步 `loadSeries`，读取磁盘缓存。
- 没有缓存或解析失败时展示"暂无MACD缓存"。
- 根据 `KLineViewport` 取可视区间，将 `MacdPoint` 按 `yyyyMMdd` 对齐 K 线日期：
  - 若出现"首个匹配点之后的缺口"，直接返回 null，导致本次不显示 MACD。
- 绘制由 `MacdSubChartPainter` 完成：柱状 `hist` + `DIF/DEA` 折线 + 0 轴 + 选中虚线。

代码参考：
- `lib/screens/stock_detail_screen.dart`
- `lib/widgets/linked_dual_kline_view.dart`
- `lib/widgets/kline_chart_with_subcharts.dart`
- `lib/widgets/macd_subchart.dart`

