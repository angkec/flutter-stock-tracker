# Data Layer Real Network Full-Stock E2E Design

Date: 2026-02-18

## Summary
Add a single long-running integration test that exercises the full data-layer pipeline with real network and full-stock coverage, using the same runtime strategy as the UI. The test runs daily, weekly, and minute pipelines sequentially, validates full-stock completeness, and writes a detailed report to a stable location. No UI or indicator computation is included; only data fetch, persistence, and integrity checks are verified.

## Goals
- Run a real-network, full-stock data-layer integration test with UI-equivalent fetching strategy.
- Validate data fetch results and full-stock completeness for daily, weekly, and minute K-lines.
- Generate a detailed report at `docs/reports/YYYY-MM-DD-data-layer-real-e2e.md` on every run.
- Keep test execution within 30 minutes (hard timeout).
- Isolate all test storage from user data using a temp root directory.

## Non-Goals
- Do not test UI flows or widget rendering.
- Do not test indicator computation or caches (MACD/ADX/breakout/pullback/industry).
- Do not perform sampling or partial-stock verification.

## Alternatives Considered
- Split into multiple tests for each pipeline. Rejected because it increases total runtime and risks repeated full fetches.
- Use a sampling strategy for read/verification. Rejected because the requirement is full-stock validation.
- Use debug stock limits or batch processing. Rejected by requirement.

## Architecture
### Test File
- `test/integration/data_layer_real_e2e_test.dart`

### Key Components
- Network: `TdxPool(poolSize: 12)`, `StockService`
- Daily pipeline: `DailyKlineSyncService` with fetcher backed by `TdxPool.batchGetSecurityBarsStreaming`
- Weekly/minute pipeline: `MarketDataRepository` using `TdxPoolFetchAdapter` and UI-equivalent `MinuteSyncConfig`
- Storage isolation:
  - SQLite: `databaseFactory = databaseFactoryFfi`, `databaseFactory.setDatabasesPath(tempDbDir)`
  - Files: `KLineFileStorage.setBaseDirPathForTesting(tempFileDir)`
  - Reset singleton: `MarketDatabase.resetInstance()`
- Audit/reporting: `AuditOperationRunner` + `FileAuditSink` rooted at temp dir

## Data Flow (Sequential)
1. **Daily K (force full)**
   - Call `DailyKlineSyncService.sync(mode: forceFull, targetBars: 260)`
   - Persist via `DailyKlineCacheStore` and `DailyKlineCheckpointStore`
2. **Weekly K (refetch)**
   - Call `MarketDataRepository.refetchData(dataType: weekly, dateRange: now-760d..now)`
   - Persist via `KLineMetadataManager` and monthly files
3. **Minute K (refetch)**
   - Call `MarketDataRepository.refetchData(dataType: oneMinute, dateRange: now-30d..now)`
   - Persist via `MinuteSyncWriter`, update `DateCheckStorage` and `MinuteSyncStateStorage`

## Validation Rules (Full-Stock)
- **Daily**: each stock must have at least 260 daily bars in the most recent window (target bars).
- **Weekly**: each stock must have at least 100 weekly bars within the 760-day window.
- **Minute**: for every trading day within the 30-day window (excluding today), each stock must have at least 220 minute bars. Today is allowed to be incomplete.

## Failure Classification
Allowed no-data errors (non-fatal if no other violations):
- `empty_fetch_result`
- `No minute bars returned`

All other errors (connection, timeout, persistence, database, unexpected exceptions) are fatal.

## Reporting
Write a report to `docs/reports/YYYY-MM-DD-data-layer-real-e2e.md` containing:
- Start/end timestamps, total duration, and per-stage durations
- Stock count and pipeline configuration (pool size, batch size, max batches, write concurrency)
- Date ranges and validation rules used
- Per-stage fetch results: total, success, allowed-no-data, fatal errors
- Per-stage validation results: missing/short counts with top offending stocks
- A concise pass/fail summary with failure reasons

Report is written in a `try/finally` to ensure it is emitted on failure or timeout.

## Execution
Example command:
```
flutter test test/integration/data_layer_real_e2e_test.dart -r compact
```

Timeout: 30 minutes.

## Risks and Mitigations
- **Network instability**: classified as fatal and visible in report.
- **Large runtime**: single test with a hard timeout and clear timing breakdown.
- **High memory usage**: accepted per requirement; no batching or sampling is used.
- **Storage growth**: isolated to temp directory and removed in teardown.
