# SW Industry Daily K-Line Feature Summary (2026-02-20)

## Goal

Summarize the newly added SW industry daily K-line interface so follow-up features can build on stable integration points.

## What Was Added

### 1) Data model: Tushare row -> domain KLine

- File: `lib/models/sw_daily_bar.dart`
- Core class: `SwDailyBar`
- Key methods:
  - `SwDailyBar.fromTushareMap(...)`: parses Tushare fields (`ts_code`, `trade_date`, `open/high/low/close`, `vol`, `amount`, etc.)
  - `toKLine()`: converts to existing `KLine` domain model
  - `toJson()`: serializes SW bar payload

Design impact:
- SW daily data is mapped into existing KLine-driven infrastructure, avoiding parallel chart model stacks.

### 2) Tushare API client

- File: `lib/services/tushare_client.dart`
- Core class: `TushareClient`
- Error class: `TushareApiException`
- Key methods:
  - `buildRequestEnvelope(...)`
  - `fetchSwDaily(...)`
  - `parseSwDailyResponse(...)`

Contract:
- Endpoint: `https://api.tushare.pro`
- Envelope: `api_name`, `token`, `params`, `fields`
- Current endpoint integrated: `sw_daily`

### 3) Token lifecycle service

- File: `lib/services/tushare_token_service.dart`
- Core class: `TushareTokenService`
- Storage abstraction: `TokenStorage` + default `SecureTokenStorage`
- Key methods:
  - `load()`, `saveToken(...)`, `setTempToken(...)`, `clearTempToken()`, `deleteToken()`
  - getters: `token`, `hasToken`, `maskedToken`

Design impact:
- Mirrors existing secure-key flow (saved token + temporary token override), enabling safe API credential management.

### 4) Repository layer for SW index data

- File: `lib/data/repository/sw_index_repository.dart`
- Core class: `SwIndexRepository`
- Result DTOs:
  - `SwIndexSyncResult` (fetched codes + total bars)
  - `SwIndexCacheStats` (code count + data version)
- Key methods:
  - `syncMissingDaily(...)`: incremental fetch based on local coverage
  - `refetchDaily(...)`: force full refetch
  - `getDailyKlines(...)`: read cached K-lines by ts code + date range
  - `getCacheStats()`
  - `toLocalCode(...)` mapping (`801010.SI` -> `sw_801010_si`)

Storage strategy:
- Reuses `KLineMetadataManager` and existing KLine storage/data versioning path.
- SW data is namespaced in local stock code keys via `sw_` prefix.

### 5) UI state orchestration provider

- File: `lib/providers/sw_index_data_provider.dart`
- Core class: `SwIndexDataProvider`
- Key state:
  - `isLoading`, `lastError`, `cacheCodeCount`, `dataVersion`, `lastFetchedCodes`
- Key methods:
  - `refreshStats()`
  - `syncIncremental(...)`
  - `syncRefetch(...)`

Design impact:
- Provides a single source of UI state for SW index sync operations and status display.

### 6) Dependency injection wiring

- File: `lib/main.dart`
- Added wiring:
  - `ChangeNotifierProvider<TushareTokenService>`
  - `ProxyProvider<TushareTokenService, SwIndexRepository>`
  - `ChangeNotifierProxyProvider<SwIndexRepository, SwIndexDataProvider>`

DI flow:
- Token service -> client -> repository -> provider.

### 7) Data Management entry points

- File: `lib/screens/data_management_screen.dart`
- Added constants/actions:
  - `_defaultSwIndexCodes`
  - `_buildSwIndexDailyCacheItem(...)`
  - `_syncSwIndexIncremental(...)`
  - `_syncSwIndexForceFull(...)`
  - `_showTushareTokenDialog(...)`
- Added cache type/icon: `申万行业日指数`

UX behavior:
- When token exists: supports incremental fetch and force refetch actions.
- When token missing: prompts token dialog (`仅本次使用` / `保存并使用`).

## End-to-End Data Flow

1. User triggers SW action in Data Management page.
2. `SwIndexDataProvider` starts sync (`syncIncremental` or `syncRefetch`).
3. `SwIndexRepository` determines fetch window and calls `TushareClient.fetchSwDaily`.
4. `SwDailyBar` maps response rows into `KLine`.
5. Repository writes via `KLineMetadataManager` using local code namespace `sw_*`.
6. Provider refreshes stats and updates UI state.

## Test Coverage Added

- `test/models/sw_daily_bar_test.dart`
  - parsing and KLine mapping
- `test/services/tushare_token_service_test.dart`
  - saved token, temp token override, masking, delete flow
- `test/services/tushare_client_test.dart`
  - request envelope, response parsing, error path (`code != 0`)
- `test/data/repository/sw_index_repository_test.dart`
  - incremental sync persistence path
  - read path with normalized local code
- `test/providers/sw_index_data_provider_test.dart`
  - loading/error/fetched-codes state transitions
- `test/screens/data_management_screen_test.dart`
  - SW card presence in Data Management page (`基础数据区显示申万行业日指数卡片`)

## Current Constraints / Known Gaps

1. `main.dart` currently uses fallback token string `__NO_TOKEN__` when token is empty.
   - Follow-up can introduce guarded repository/client creation to avoid placeholder token usage.
2. SW code list is currently static (`_defaultSwIndexCodes`) in screen state.
   - Follow-up can move this to config/repository-level capability discovery.
3. Data management actions currently use fixed 365-day range.
   - Follow-up can expose user-selectable sync windows.
4. No dedicated SW trend/rank analytics yet.
   - Current integration provides fetch/cache plumbing only.

## Recommended Next Feature Directions

1. Build SW index list/detail screens using `SwIndexRepository.getDailyKlines(...)`.
2. Add SW industry trend computation on top of cached KLines.
3. Add sync telemetry (latency/failure reasons/rate limits) in provider and audit stream.
4. Add environment-gated real Tushare integration tests for API contract drift.

## Related Files (Quick Index)

- `lib/models/sw_daily_bar.dart`
- `lib/services/tushare_client.dart`
- `lib/services/tushare_token_service.dart`
- `lib/data/repository/sw_index_repository.dart`
- `lib/providers/sw_index_data_provider.dart`
- `lib/main.dart`
- `lib/screens/data_management_screen.dart`
- `test/models/sw_daily_bar_test.dart`
- `test/services/tushare_token_service_test.dart`
- `test/services/tushare_client_test.dart`
- `test/data/repository/sw_index_repository_test.dart`
- `test/providers/sw_index_data_provider_test.dart`
- `test/screens/data_management_screen_test.dart`
