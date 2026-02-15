# MACD Local Cache & Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-stock daily/weekly MACD calculation in computation layer, cache results to disk (not SharedPreferences payload), and expose a new MACD settings entry from Data Management with a dedicated settings page.

**Architecture:** Introduce a dedicated `MacdIndicatorService` (`ChangeNotifier`) plus `MacdCacheStore` file storage under app docs directory. Service owns parameter config (small JSON in SharedPreferences), MACD computation, local-first load/compute/persist flow, and batch prewarm APIs. Existing refresh/sync flows call service for automatic local prewarm without triggering network fetches.

**Tech Stack:** Flutter, Provider, SharedPreferences (config only), file-based JSON cache via `dart:io`, existing `DataRepository` and `KLineFileStorage`.

---

### Task 1: Add MACD domain model and file cache store

**Files:**
- Create: `lib/models/macd_config.dart`
- Create: `lib/models/macd_point.dart`
- Create: `lib/data/storage/macd_cache_store.dart`
- Test: `test/data/storage/macd_cache_store_test.dart`

**Step 1: Write the failing storage test**
- Add test for save/load/clear flow by `stockCode + dataType`.
- Add test for config/source-signature retention.

**Step 2: Run failing test**
- Run: `flutter test test/data/storage/macd_cache_store_test.dart`
- Expected: fail because store/model files are missing.

**Step 3: Implement minimal models/store**
- Add immutable model classes with `toJson/fromJson`.
- Add cache store with atomic write (`tmp` + rename), per-stock-type file naming, and batch save progress callback.

**Step 4: Re-run storage test**
- Run: `flutter test test/data/storage/macd_cache_store_test.dart`
- Expected: pass.

---

### Task 2: Add MACD service (compute + config + local-first cache)

**Files:**
- Create: `lib/services/macd_indicator_service.dart`
- Test: `test/services/macd_indicator_service_test.dart`

**Step 1: Write failing service tests**
- Test MACD sequence calculation (DIF/DEA/HIST) produces non-empty and ordered points.
- Test service uses disk cache when config + source signature unchanged.
- Test config persistence only stores small config payload in SharedPreferences.

**Step 2: Run failing service tests**
- Run: `flutter test test/services/macd_indicator_service_test.dart`
- Expected: fail because service does not exist yet.

**Step 3: Implement minimal service**
- Add config load/update/reset.
- Add `getOrComputeFromBars` and `prewarmFromBars` / `prewarmFromRepository`.
- Keep local-only behavior: repository read via `getKlines` only, no `fetchMissingData`.
- Trim output to recent 3 months.

**Step 4: Re-run service tests**
- Run: `flutter test test/services/macd_indicator_service_test.dart`
- Expected: pass.

---

### Task 3: Integrate service into app provider graph and refresh workflows

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/providers/market_data_provider.dart`
- Test: `test/providers/market_data_provider_test.dart`

**Step 1: Write failing provider integration test**
- Add/extend test to verify force daily refetch triggers MACD daily prewarm and persists results.

**Step 2: Run failing provider test**
- Run: `flutter test test/providers/market_data_provider_test.dart`
- Expected: fail because provider has no MACD integration.

**Step 3: Implement minimal integration**
- Register `MacdIndicatorService` in `main.dart`.
- Inject service into `MarketDataProvider` via proxy update.
- After daily-bar related compute flows, invoke local prewarm APIs (without changing network behavior).

**Step 4: Re-run provider tests**
- Run: `flutter test test/providers/market_data_provider_test.dart`
- Expected: pass.

---

### Task 4: Add Data Management entry and MACD settings page UI

**Files:**
- Create: `lib/screens/macd_settings_screen.dart`
- Modify: `lib/screens/data_management_screen.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write failing screen test**
- Add test that Data Management shows MACD entry and can navigate to settings screen.

**Step 2: Run failing screen test**
- Run: `flutter test test/screens/data_management_screen_test.dart`
- Expected: fail because entry/page missing.

**Step 3: Implement UI (frontend-design)**
- Add a dedicated settings card in Data Management.
- Build a distinctive but coherent settings page (headline card, compact parameter controls, strong visual hierarchy).
- Wire save/reset actions to `MacdIndicatorService`.

**Step 4: Re-run screen tests**
- Run: `flutter test test/screens/data_management_screen_test.dart`
- Expected: pass.

---

### Task 5: Hook weekly-sync flow prewarm and finish verification

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write failing weekly prewarm test**
- Add test verifying weekly sync flow still works and triggers local MACD prewarm call path.

**Step 2: Run failing weekly test**
- Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "周K"`
- Expected: fail before prewarm integration.

**Step 3: Implement minimal weekly prewarm call**
- In weekly sync success path, call MACD service weekly prewarm using local repository data range.
- Preserve existing progress and snack bar UX.

**Step 4: Re-run focused + broader tests**
- Run:
  - `flutter test test/data/storage/macd_cache_store_test.dart`
  - `flutter test test/services/macd_indicator_service_test.dart`
  - `flutter test test/providers/market_data_provider_test.dart`
  - `flutter test test/screens/data_management_screen_test.dart`

**Step 5: Final regression sanity**
- Run: `flutter test`
- Expected: all pass or only pre-existing unrelated failures.

