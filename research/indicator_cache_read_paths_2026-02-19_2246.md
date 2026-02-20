# Indicator Cache Read Paths (MACD / EMA)

- Timestamp: 2026-02-19 22:46 (Asia/Shanghai)
- Scope: How cached indicator results are read, with focus on MACD and EMA, and whether stock detail uses cache.

## Conclusion

1. Indicator caches are file-based under `market_data/klines` base path, then subfolders `macd_cache` and `ema_cache`.
2. Direct cache reads are through:
   - `MacdCacheStore.loadSeries(stockCode, dataType)`
   - `EmaCacheStore.loadSeries(stockCode, dataType)`
3. Service-level reads use read-through logic:
   - `MacdIndicatorService.getOrComputeFromBars(...)`
   - `EmaIndicatorService.getOrComputeFromBars(...)`
   These first check in-memory cache, then disk cache (`loadSeries`), validate `sourceSignature + config`, and recompute only when needed.
4. Stock detail page uses cache reads:
   - EMA: `StockDetailScreen` directly calls `EmaCacheStore.loadSeries(...)`, then aligns points to bars by date.
   - MACD: `StockDetailScreen` renders `MacdSubChart`, and `MacdSubChart` directly calls `MacdCacheStore.loadSeries(...)`.

## Key Code References

- Cache storage layout and file naming:
  - `lib/data/storage/macd_cache_store.dart`
  - `lib/data/storage/ema_cache_store.dart`
  - `lib/data/storage/kline_file_storage.dart`
- Read-through service logic:
  - `lib/services/macd_indicator_service.dart`
  - `lib/services/ema_indicator_service.dart`
- Stock detail usage:
  - `lib/screens/stock_detail_screen.dart`
  - `lib/widgets/macd_subchart.dart`
  - `lib/widgets/linked_dual_kline_view.dart`

## Practical Read Entry Points

- If you only want cached data (no recompute): call `MacdCacheStore/EmaCacheStore.loadSeries(...)`.
- If you want cache + auto-recompute fallback: call `MacdIndicatorService/EmaIndicatorService.getOrComputeFromBars(...)`.
