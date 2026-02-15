# Daily KLine File Persistence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move daily K-line cache persistence from `SharedPreferences` to file-layer storage and restore it across app restart, while preserving data-layer → compute-layer → UI-layer boundaries.

**Architecture:** Daily K-line cache read/write will be handled in the data-layer (`KLineFileStorage`) through a thin persistence component consumed by `MarketDataProvider` (compute-layer). UI-layer does not touch persistence details; it only consumes provider state/progress. Legacy heavy payload in `SharedPreferences` is migrated out and permanently disabled.

**Tech Stack:** Flutter/Dart, `KLineFileStorage`, `SharedPreferences` (metadata only), `flutter_test`.

---

### Task 1: Define data-layer daily cache persistence contract

**Files:**
- Modify: `lib/data/storage/kline_file_storage.dart`
- Create: `lib/data/storage/daily_kline_cache_store.dart`
- Test: `test/data/storage/daily_kline_cache_store_test.dart`

**Step 1: Write failing tests**
- Add tests for writing per-stock daily bars into monthly files and reloading latest N bars.

**Step 2: Run test to verify it fails**
- Run: `flutter test test/data/storage/daily_kline_cache_store_test.dart`
- Expected: FAIL due missing store implementation.

**Step 3: Write minimal implementation**
- Implement `DailyKlineCacheStore` backed by `KLineFileStorage`.
- Keep API data-layer only (`saveAll`, `loadForStocks`, `clearForStocks`).

**Step 4: Run test to verify it passes**
- Run: `flutter test test/data/storage/daily_kline_cache_store_test.dart`
- Expected: PASS.

### Task 2: Integrate compute-layer provider with file-layer store

**Files:**
- Modify: `lib/providers/market_data_provider.dart`
- Modify: `lib/main.dart`
- Test: `test/providers/market_data_provider_test.dart`

**Step 1: Write failing tests**
- Ensure provider persists daily bars to file store after refetch.
- Ensure provider can restore from file store on restart and skip network fetch when metadata is valid.

**Step 2: Run test to verify it fails**
- Run: `flutter test test/providers/market_data_provider_test.dart --plain-name 'refresh should reuse persisted daily bars after restart'`
- Expected: FAIL (currently no file-store integration).

**Step 3: Write minimal implementation**
- Inject data-layer store into provider.
- Keep `SharedPreferences` for light metadata only (`last_fetch_date` etc).
- During pullback detection:
  - restore missing daily bars from file if date is still valid,
  - fallback to network fetch only when restore insufficient,
  - persist fetched daily bars to file store.

**Step 4: Run test to verify it passes**
- Run: `flutter test test/providers/market_data_provider_test.dart`
- Expected: PASS.

### Task 3: Keep UI-layer unchanged and verify no regression

**Files:**
- Modify: `lib/screens/data_management_screen.dart` (only if signature needs sync)
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write failing test (if needed)**
- Add/adjust tests only if provider API changes propagate to UI layer.

**Step 2: Run test to verify it fails**
- Run specific widget test impacted by API changes.

**Step 3: Write minimal implementation**
- Keep UI progress semantics unchanged.

**Step 4: Run test to verify it passes**
- Run: `flutter test test/screens/data_management_screen_test.dart`

### Task 4: Verification and migration safety

**Files:**
- Modify: `lib/providers/market_data_provider.dart`
- Test: `test/providers/market_data_provider_test.dart`

**Step 1: Write failing tests**
- Verify legacy `daily_bars_cache_v1` is removed and not rewritten.

**Step 2: Run test to verify it fails**
- Run target test and confirm red.

**Step 3: Write minimal implementation**
- Enforce migration cleanup during load/save.

**Step 4: Run test to verify it passes**
- Run: `flutter test test/providers/market_data_provider_test.dart`

### Task 5: Final verification

**Files:**
- No code change required.

**Step 1: Run focused test suite**
- `flutter test test/data/storage/daily_kline_cache_store_test.dart`
- `flutter test test/providers/market_data_provider_test.dart`
- `flutter test test/screens/data_management_screen_test.dart`

**Step 2: Run static checks for touched files**
- `flutter analyze lib/data/storage/daily_kline_cache_store.dart lib/providers/market_data_provider.dart test/data/storage/daily_kline_cache_store_test.dart test/providers/market_data_provider_test.dart`

**Step 3: Record evidence**
- Capture command outputs and only then declare completion.

