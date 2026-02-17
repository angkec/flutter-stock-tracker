# Daily/Weekly ADX Indicator Design (2026-02-17)

## 1. Goal

Add a full ADX indicator workflow for both daily and weekly K-line, aligned with existing MACD practices:

1. ADX calculation logic.
2. Explicit recompute entry in Data Management.
3. On-disk indicator cache (plus in-memory reuse).
4. Display in stock detail view.

The UX and engineering objective is consistency: users should manage ADX exactly as they already manage MACD, without introducing a second mental model.

## 2. Confirmed Product Decisions

1. Data Management provides **ADX settings + recompute** for both daily and weekly.
2. Stock detail uses **fixed stacked subcharts** under main K-line: `MACD + ADX`.
3. ADX uses **Wilder method** with configurable parameters:
   - `period` (default `14`)
   - `threshold` (default `25`)
4. ADX subchart renders three lines: `ADX`, `+DI`, `-DI`, plus a threshold reference line.

## 3. Options Considered

### Option A: Parallel ADX Pipeline (Chosen)

Build ADX as a sibling pipeline to MACD with dedicated service/store/widget/settings, while reusing naming and lifecycle conventions.

- Pros: clear boundaries, lower regression risk, fast adoption.
- Cons: some duplicated structure between indicators.

### Option B: Generic Indicator Framework First

Refactor MACD and ADX into a shared abstraction first.

- Pros: long-term architecture purity.
- Cons: large blast radius and unnecessary risk for this increment.

### Option C: UI-Time Compute Without Cache

Compute ADX in stock detail directly and skip persistent cache.

- Pros: less initial code.
- Cons: violates requirement for explicit cache/recompute workflow; poor responsiveness and consistency.

Chosen: **Option A**.

## 4. Architecture

### 4.1 Models

Add:

1. `lib/models/adx_config.dart`
   - `period`
   - `threshold`
   - validation + JSON serialization.
2. `lib/models/adx_point.dart`
   - `datetime`
   - `adx`
   - `plusDi`
   - `minusDi`
   - JSON serialization.

### 4.2 Storage

Add `lib/data/storage/adx_cache_store.dart`.

Design mirrors `MacdCacheStore`:

1. Directory: dedicated `adx_cache` subdirectory.
2. File naming: `${stockCode}_${dataType.name}_adx_cache.json`.
3. Payload:
   - `stockCode`
   - `dataType`
   - `config`
   - `sourceSignature`
   - `points`
   - `updatedAt`
4. APIs:
   - `saveSeries`
   - `saveAll`
   - `loadSeries`
   - `listStockCodes`
   - `clearForStocks` (daily + weekly).

### 4.3 Service

Add `lib/services/adx_indicator_service.dart`.

Core responsibilities:

1. Manage daily/weekly configs in `SharedPreferences`.
2. Compute ADX series from bars (Wilder).
3. Keep memory cache keyed by `stockCode + dataType`.
4. Reuse disk cache when `sourceSignature + config` match.
5. Provide bulk prewarm from bars and from repository for Data Management workflows.

Public API should parallel MACD naming where practical:

1. `configFor(...)`
2. `load()`
3. `updateConfigFor(...)`
4. `resetConfigFor(...)`
5. `getOrComputeFromBars(...)`
6. `getOrComputeFromRepository(...)`
7. `prewarmFromBars(...)`
8. `prewarmFromRepository(...)`

## 5. Calculation Specification

Use Wilder ADX formula over OHLC bars:

1. `TR`, `+DM`, `-DM` per bar.
2. Wilder smoothing over `period` for `TR/+DM/-DM`.
3. `+DI = 100 * smoothed(+DM) / smoothed(TR)`.
4. `-DI = 100 * smoothed(-DM) / smoothed(TR)`.
5. `DX = 100 * abs(+DI - -DI) / (+DI + -DI)`.
6. `ADX` is Wilder-smoothed `DX`.

Rules:

1. Insufficient bars produce empty/partial output safely (no crash).
2. Division by zero returns stable zero values for affected points.
3. Output timestamps align to source bar dates.

## 6. Data Flow and Entrypoints

### 6.1 Data Management Entrypoint

Add two cards/items on Data Management:

1. `日线ADX参数设置`
2. `周线ADX参数设置`

Each opens `AdxSettingsScreen(dataType: ...)` with:

1. parameter editing (`period`, `threshold`)
2. `重算日线ADX` / `重算周线ADX` action
3. progress dialog consistent with MACD UX.

### 6.2 Daily Flow Integration

In `MarketDataProvider.forceRefetchDailyBars(...)`, extend indicator stage:

1. keep existing breakout + daily MACD prewarm
2. append daily ADX prewarm using current daily bar cache
3. keep progress reporting in the same `3/4 计算指标...` stage.

### 6.3 Weekly Flow Integration

In Data Management weekly fetch path, when weekly data changes (or forced fetch):

1. prewarm weekly MACD (existing)
2. prewarm weekly ADX (new)
3. prioritize changed stock codes when available; fall back to full scope.

## 7. Stock Detail UI

Add `AdxSubChart` as a new `KLineSubChart` implementation.

In `StockDetailScreen`, for daily/weekly display modes:

1. Keep existing `MacdSubChart`.
2. Add `AdxSubChart` below MACD, fixed stacked layout.
3. Maintain viewport and selection linkage via existing `KLineChartWithSubCharts` contract.

`AdxSubChart` display behavior:

1. Header: date + `ADX/+DI/-DI` current values.
2. Reference line: threshold (from config).
3. Missing cache: show actionable hint (`暂无ADX缓存，请先在数据管理同步`).
4. Never compute on UI thread.

## 8. Caching, Signature, and Invalidation

Use the same cache validity pattern as MACD:

1. `sourceSignature` derived from normalized bar sequence + config-relevant fields.
2. Config mismatch or signature mismatch triggers recompute.
3. Config update clears only in-memory entries for the affected data type.
4. Disk cache stays append/overwrite by key and naturally invalidates via signature checks.

## 9. Error Handling

Principles:

1. Indicator failures must not break primary data or chart rendering.
2. Batch prewarm is best-effort per stock (continue on single-stock errors).
3. Cache read corruption is treated as cache miss.
4. Cache write failure does not block returning computed points.
5. UI always has deterministic states: loading / no-cache / rendered.

## 10. Testing Plan

### 10.1 Unit Tests

1. `AdxConfig` validation + serialization.
2. `AdxPoint` serialization.
3. Wilder math correctness with fixed fixture bars.
4. Signature hit/miss behavior.
5. Config update effect on recompute behavior.

### 10.2 Storage Tests

1. `AdxCacheStore` save/load/list roundtrip.
2. Corrupted file tolerance.
3. Concurrent `saveAll` stability.

### 10.3 Widget Tests

1. `AdxSubChart` renders no-cache placeholder.
2. viewport slicing and selected index behavior.
3. threshold line and info row values.
4. stock detail renders stacked `MACD + ADX` subcharts.

### 10.4 Integration Tests

1. Data Management ADX settings navigation.
2. Recompute button progress + completion paths.
3. Daily force refetch triggers ADX prewarm stage.
4. Weekly sync triggers ADX prewarm when data changed.

## 11. Implementation Sequence

1. Add ADX models + cache store + service with tests.
2. Wire provider/main dependency injection and daily/weekly prewarm hooks.
3. Add Data Management ADX settings/recompute screens and progress UX.
4. Add ADX subchart and stock detail stacked rendering.
5. Run full test suites for touched layers and adjust regressions.

## 12. Non-Goals (This Iteration)

1. Generic indicator plugin framework.
2. Real-time on-demand ADX compute from stock detail.
3. Multi-indicator layout customization (drag/sort/hide).
4. Signal strategy decisions based on ADX (only indicator computation and presentation).
