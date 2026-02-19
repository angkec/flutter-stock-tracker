# EMA Indicator Design

## Context

We need to add EMA overlays for the main K-line charts (daily and weekly). The EMA values must be precomputed and cached (disk + memory) and should never be computed on demand inside stock detail UI. If EMA cache is missing, the stock detail view must show nothing (no lines, no values, no warnings). EMA parameters are configurable via a new EMA settings page (data management entry), and that page should show cache statistics.

Required defaults:
- Daily: EMA 11 / 22
- Weekly: EMA 13 / 26

Display rules:
- Draw EMA on the main chart (two lines: short=orange, long=blue, width=1.2).
- Show EMA values in the selected info row; if no selection, show latest bar values.
- If cache is missing or invalid, do not draw or show EMA values at all.

## Architecture

Introduce a new EMA indicator pipeline mirroring MACD/ADX:

- `EmaIndicatorService` (service layer)
  - Loads/stores daily + weekly EMA config from shared prefs.
  - Computes EMA series from K-line bars.
  - Maintains an in-memory cache keyed by `stockCode + dataType`.
  - Provides `getOrComputeFromRepository`, `getOrComputeFromBars`, `prewarmFromBars`, `prewarmFromRepository`.
  - Validates cached data using `sourceSignature` (bars) + `configSignature` (periods).

- `EmaCacheStore` (disk cache)
  - Stores per-stock EMA series under `market_data/klines/ema_cache`.
  - File naming: `${stockCode}_${dataType.name}_ema_cache.json`.
  - Same API shape as MACD/ADX cache stores.

- `EmaSettingsScreen`
  - Independent settings page (daily/weekly) with parameter form, reset, and recompute.
  - Entry added in Data Management screen (parallel to MACD/ADX).
  - Displays cache stats (coverage count, latest update timestamp per data type).

This keeps indicator storage consistent across MACD/ADX/EMA and allows bulk prewarm to update caches without UI coupling.

## Data Flow

1. **Daily prewarm**
   - `MarketDataProvider` uses `_dailyBarsCache` to call `EmaIndicatorService.prewarmFromBars` for daily EMA during its indicator prewarm pipeline.

2. **Weekly prewarm**
   - After weekly K-line fetch completes in `data_management_screen.dart`, call `emaService.prewarmFromRepository`.

3. **Manual recompute (settings)**
   - `EmaSettingsScreen` recompute button triggers `emaService.prewarmFromRepository` for the selected data type and date range.

4. **Stock detail render**
   - `StockDetailScreen` (and linked dual view) loads EMA series **only** from `EmaCacheStore`.
   - If cache exists and matches config signature: draw EMA lines + show EMA values in info row.
   - If cache is missing or invalid: show no EMA lines and no EMA values.

No UI layer computes EMA on demand.

## UI and Interaction Rules

- **Main chart overlay**: Two EMA lines drawn on top of the K-line candles.
  - Short EMA: orange, width 1.2.
  - Long EMA: blue, width 1.2.
  - Lines are clipped to the K-line plot area.

- **Selected info row**:
  - Show `EMA短` / `EMA长` values alongside existing price/ratio info.
  - When no selection, show values for latest bar.
  - If cache missing/invalid, EMA values are omitted entirely (row still shows price/ratio data).

- **Missing cache behavior**:
  - Stock detail view: no EMA lines, no values, no placeholder text.
  - EMA settings page: surface cache coverage stats so the user can detect missing data.

## Cache Validity and Signatures

- `sourceSignature` built from bar timestamps + close values + length + rolling hash.
- `configSignature` built from `shortPeriod|longPeriod`.
- Cache is treated as invalid if signatures do not match; UI behaves like cache miss.

## Error Handling

- Cache read failure (`I/O`, JSON parse) returns null and is treated as missing cache.
- The UI never throws on EMA cache issues; it simply omits EMA overlays.
- Recompute errors are surfaced only in settings page via snackbars.

## Testing Strategy (Minimal)

1. **Service tests**
   - EMA computation correctness for known inputs.
   - Config signature change triggers cache invalidation.
   - Prewarm writes cache files and updates memory cache.

2. **Cache store tests**
   - Save/load round trip.
   - Corrupt JSON returns null (no exception).

3. **Widget tests**
   - `KLineChart` renders EMA lines when series present.
   - EMA info row shows latest bar values when no selection.
   - Missing cache results in no EMA overlays or values.

## YAGNI Boundaries

- No on-demand EMA compute in stock detail.
- No crosshair-linked EMA values.
- No dynamic indicator registry.
- No multi-line EMA sets beyond short/long.

This design keeps EMA consistent with existing indicator architecture, ensures cache-first behavior, and avoids UI noise when data is missing.
