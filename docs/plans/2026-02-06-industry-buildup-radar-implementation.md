# Industry Buildup Radar Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a new `建仓雷达` industry sub-tab that computes and displays daily post-market buildup signals (`Z_rel`, `breadth`, `Q`) from minute K-lines, with SQLite persistence and manual recompute progress.

**Architecture:** Keep data access in `DataRepository`, add a dedicated `IndustryBuildUpService` in the analysis layer, and persist computed daily industry results in a new SQLite table. UI reads latest board + 20-day `Z_rel` sparkline and exposes manual recompute button with stage-aware progress text.

**Tech Stack:** Flutter/Dart, Provider, sqflite (`sqflite_common_ffi` in tests), existing chart widgets.

---

### Task 1: Add Storage Schema + Persistence Layer

**Files:**
- Modify: `lib/data/storage/database_schema.dart`
- Modify: `lib/data/storage/market_database.dart`
- Create: `lib/data/storage/industry_buildup_storage.dart`
- Test: `test/data/storage/market_database_test.dart`
- Test: `test/data/storage/industry_buildup_storage_test.dart`

**Step 1: Write failing tests**
- Add version-3 schema expectations in `market_database_test.dart`.
- Add storage CRUD/query tests in `industry_buildup_storage_test.dart`:
  - upsert and query latest date
  - latest board ordered by rank
  - industry 20-day trend returns time-ascending values

**Step 2: Run tests to verify RED**
- Run:
  - `flutter test test/data/storage/market_database_test.dart`
  - `flutter test test/data/storage/industry_buildup_storage_test.dart`

**Step 3: Implement minimal storage**
- Add `industry_buildup_daily` table + indexes in schema.
- Upgrade DB `version` to 3 and add `onUpgrade` migration for v3.
- Implement `IndustryBuildUpStorage` with transactional upsert and query APIs.

**Step 4: Run tests to verify GREEN**
- Re-run the two storage test files.

**Step 5: Commit**
- `git add ...`
- `git commit -m "feat(data): add sqlite storage for industry buildup radar"`

### Task 2: Add Domain Model + BuildUp Service

**Files:**
- Create: `lib/models/industry_buildup.dart`
- Create: `lib/services/industry_buildup_service.dart`
- Test: `test/services/industry_buildup_service_test.dart`

**Step 1: Write failing tests**
- Add tests for service behavior:
  - recompute writes latest board records
  - progress state updates during recompute
  - data update event marks result stale
  - stale state does not auto-recompute

**Step 2: Run test to verify RED**
- `flutter test test/services/industry_buildup_service_test.dart`

**Step 3: Implement minimal service**
- Add model classes for daily records and board items.
- Implement recompute pipeline:
  - prepare -> preprocess -> aggregate -> score -> persist
- Implement progress fields:
  - `stageLabel`, `progressCurrent`, `progressTotal`, `isCalculating`
- Implement stale/error metadata and repository update subscription.

**Step 4: Run test to verify GREEN**
- `flutter test test/services/industry_buildup_service_test.dart`

**Step 5: Commit**
- `git add ...`
- `git commit -m "feat(service): implement industry buildup computation pipeline"`

### Task 3: Register Provider + Wire Lifecycle

**Files:**
- Modify: `lib/main.dart`
- Test: `test/services/industry_buildup_service_test.dart` (add lifecycle assertion if needed)

**Step 1: Write failing test (if needed)**
- Add/adjust a service test for stale marking via `dataUpdatedStream` and dispose safety.

**Step 2: Verify RED**
- `flutter test test/services/industry_buildup_service_test.dart`

**Step 3: Implement provider wiring**
- Register `IndustryBuildUpService` with dependencies:
  - `DataRepository`
  - `IndustryService`
- Ensure `load()` runs on startup.

**Step 4: Verify GREEN**
- `flutter test test/services/industry_buildup_service_test.dart`

**Step 5: Commit**
- `git add ...`
- `git commit -m "feat(app): register industry buildup service provider"`

### Task 4: Add BuildUp UI Tab + Manual Recompute Progress Button

**Files:**
- Create: `lib/widgets/industry_buildup_list.dart`
- Modify: `lib/screens/industry_screen.dart`
- Test: `test/widgets/industry_buildup_list_test.dart` (optional if existing infra allows)

**Step 1: Write failing UI test (or service-backed widget assertions)**
- Verify new third tab exists.
- Verify recompute button text format during running is `阶段名 current/total`.
- Verify stale banner shown without auto-recompute.

**Step 2: Verify RED**
- Run targeted widget test file if added.

**Step 3: Implement UI**
- Expand tab count from 2 to 3.
- Add `建仓雷达` tab content:
  - top status row (date/stale/error)
  - manual recompute button
  - board rows with `Z_rel`, `breadth`, `Q`, and `Z_rel` sparkline
- Keep existing industry stats/rank tabs unchanged.

**Step 4: Verify GREEN**
- Re-run UI test file (if present).
- Run targeted service/storage tests to ensure no regression.

**Step 5: Commit**
- `git add ...`
- `git commit -m "feat(ui): add industry buildup radar tab with recompute progress"`

### Task 5: Targeted Verification + Cleanup

**Files:**
- All modified/new files from Tasks 1-4.

**Step 1: Run targeted verification suite**
- `flutter test test/data/storage/market_database_test.dart`
- `flutter test test/data/storage/industry_buildup_storage_test.dart`
- `flutter test test/services/industry_buildup_service_test.dart`
- `flutter test test/services/historical_kline_service_test.dart` (guard core repo interface usage)

**Step 2: Optional lint for changed files**
- `flutter analyze` (if runtime permits; otherwise report skipped scope)

**Step 3: Final review checklist**
- `建仓雷达` tab exists and is selectable.
- Recompute button shows `阶段名 current/total`.
- stale only warns; no auto recompute.
- latest board sorted by `Z_rel` desc.
- 20-day trend line displayed.
- SQLite table populated and queryable.

**Step 4: Commit final polish**
- `git add ...`
- `git commit -m "test: add coverage for industry buildup radar"`
