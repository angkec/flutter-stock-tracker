# Indicator Layer Real E2E Design

## Context
We need a full-stock, real-network integration test for the indicator layer. The test must run after the data-layer real E2E finishes, reuse the data-layer cache output, and validate MACD/ADX completeness on daily and weekly K-lines only. Each validation type must meet a 90%+ OK rate.

## Goals
- Full-stock integration test of MACD/ADX for daily and weekly data.
- Use existing optimized compute paths (prewarm and concurrency).
- Base inputs on the data-layer real E2E output (no re-fetching data independently).
- Produce a report with per-stage timing and per-validation-type failure samples.
- Enforce pass criteria: each validation type OK rate >= 90%.

## Non-Goals
- Minute K-line indicator validation.
- UI-driven widget tests.
- New indicator algorithms or performance tuning.

## Dependencies
- Data-layer E2E provides persistent cache and a manifest describing:
  - file root and DB root used for the cache
  - daily/weekly ranges used for validation
  - the list of stocks that are "data-layer complete" for daily + weekly
- Existing indicator services:
  - `MacdIndicatorService.prewarmFromBars` and `.prewarmFromRepository`
  - `AdxIndicatorService.prewarmFromBars` and `.prewarmFromRepository`
- Cache stores:
  - `MacdCacheStore`, `AdxCacheStore`
  - `DailyKlineCacheStore` for reading daily bars

## Manifest Contract (Data Layer Output)
Write a machine-readable JSON manifest alongside the data-layer report.

Suggested path:
- `docs/reports/YYYY-MM-DD-data-layer-real-e2e.json`

Suggested schema:
```
{
  "date": "YYYY-MM-DD",
  "generatedAt": "ISO-8601",
  "cacheRoot": "build/real_e2e_cache/YYYY-MM-DD",
  "fileRoot": "build/real_e2e_cache/YYYY-MM-DD/files",
  "dbRoot": "build/real_e2e_cache/YYYY-MM-DD/db",
  "daily": {
    "anchorDate": "YYYY-MM-DD",
    "targetBars": 260
  },
  "weekly": {
    "rangeDays": 760,
    "rangeStart": "YYYY-MM-DD",
    "rangeEnd": "YYYY-MM-DD",
    "targetBars": 100
  },
  "eligibleStocks": ["000001", "000002", "..."]
}
```

Definition of `eligibleStocks`:
- A stock is eligible if it passes data-layer validation for daily AND weekly bars.
- The indicator test only enforces completeness for these stocks.

## Indicator Test Flow
Test file: `test/integration/indicator_layer_real_e2e_test.dart`.

1. Load manifest. If missing, fail with a clear message: run data-layer real E2E first.
2. Configure storage:
   - `KLineFileStorage.setBaseDirPathForTesting(fileRoot)`
   - `databaseFactory.setDatabasesPath(dbRoot)`
3. Build `MarketDataRepository`, `MacdIndicatorService`, `AdxIndicatorService`.
4. Daily prewarm (fast path):
   - Use `DailyKlineCacheStore.loadForStocksWithStatus` with `anchorDate` and `targetBars` from manifest.
   - Call `macdService.prewarmFromBars` and `adxService.prewarmFromBars` on the loaded daily bars.
5. Weekly prewarm (repository path):
   - Use `DateRange` from manifest.
   - Call `macdService.prewarmFromRepository` and `adxService.prewarmFromRepository`.
   - Use the same weekly batch settings as UI:
     - `fetchBatchSize = 120`
     - `maxConcurrentPersistWrites = 8`
   - Set `forceRecompute = true` to avoid snapshot skips.
6. Validation:
   - Load daily/weekly bars for each eligible stock.
   - Load cached MACD/ADX series from disk.
   - Compute expected point counts and compare.

## Completeness Rules
- MACD expected count:
  - Compute cutoff = last bar date minus `windowMonths` (same rule as service).
  - Expected = number of bars with `datetime >= cutoff`.
- ADX expected count:
  - If `bars.length < period + 1`, expected = 0.
  - Else expected = `max(0, bars.length - (2 * period - 1))`.
- A stock is complete for a validation type if cached series exists and its length == expected.

## Pass Criteria
Each validation type must have OK rate >= 90%:
- daily MACD
- weekly MACD
- daily ADX
- weekly ADX

## Reporting
Write report to:
- `docs/reports/YYYY-MM-DD-indicator-layer-real-e2e.md`

Include:
- Start/end/duration
- Per-stage duration (daily prewarm, weekly prewarm, daily validate, weekly validate)
- Per-validation-type: failed count, failed percent, first 10 stock codes (first-seen order)
- Overall PASS/FAIL

## Error Handling
- Any exception is recorded as fatal and shown in the report.
- Report is always written before the test fails.

## Timeout
- Default test timeout: 30 minutes.
