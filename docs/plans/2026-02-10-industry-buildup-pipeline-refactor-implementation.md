# Industry BuildUp Pipeline Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor `IndustryBuildUpService` by extracting loader/computer/writer collaborators while preserving all observable behavior and test results.

**Architecture:** Keep `IndustryBuildUpService` as orchestrator for UI state and progress. Move data-loading logic to a loader, math/scoring logic to a computer, and persistence to a writer. Use constructor DI with default implementations so existing callers remain unchanged.

**Tech Stack:** Flutter, Dart, Provider/ChangeNotifier, existing repository/storage services, Flutter test.

---

### Task 1: Add a failing DI test for pipeline collaborators

**Files:**
- Modify: `test/services/industry_buildup_service_test.dart`

**Step 1: Write the failing test**
- Add a test that injects fake loader/computer/writer collaborators and asserts `recalculate(force: true)` uses those collaborators.

**Step 2: Run test to verify it fails**
- Run: `flutter test test/services/industry_buildup_service_test.dart --plain-name "recalculate uses injected pipeline collaborators"`
- Expected: FAIL because service constructor does not yet accept injected pipeline collaborators.

### Task 2: Extract pipeline models and loader

**Files:**
- Create: `lib/services/industry_buildup/industry_buildup_pipeline_models.dart`
- Create: `lib/services/industry_buildup/industry_buildup_loader.dart`

**Step 1: Write minimal implementation**
- Move stock/day feature and intermediate data structures into internal pipeline model types.
- Implement loader methods for industry-stock mapping, trading-date resolution (with minute fallback), preprocessing minute bars to day features.

**Step 2: Run focused tests**
- Run: `flutter test test/services/industry_buildup_service_test.dart --plain-name "recalculate falls back to minute bars when trading dates are unavailable"`

### Task 3: Extract computer and writer

**Files:**
- Create: `lib/services/industry_buildup/industry_buildup_computer.dart`
- Create: `lib/services/industry_buildup/industry_buildup_writer.dart`

**Step 1: Write minimal implementation**
- Move aggregation/scoring/ranking flow into computer preserving constants and formulas.
- Implement writer as thin adapter over `IndustryBuildUpStorage.upsertDailyResults`.

**Step 2: Run focused tests**
- Run: `flutter test test/services/industry_buildup_service_test.dart --plain-name "recalculate keeps latest trading day as result date on sparse weekend data"`

### Task 4: Wire `IndustryBuildUpService` to DI pipeline

**Files:**
- Modify: `lib/services/industry_buildup_service.dart`

**Step 1: Write minimal implementation**
- Add optional constructor params for loader/computer/writer with default instances.
- Replace in-method recalculate blocks with calls to collaborators.
- Keep progress labels, error message strings, stale/version gating, and post-write side effects unchanged.

**Step 2: Run target test**
- Run: `flutter test test/services/industry_buildup_service_test.dart --plain-name "recalculate uses injected pipeline collaborators"`

### Task 5: Verify regression safety

**Files:**
- No code changes expected

**Step 1: Run service test suite**
- Run: `flutter test test/services/industry_buildup_service_test.dart`

**Step 2: Run full test suite (if baseline permits)**
- Run: `flutter test`

**Step 3: Summarize results and any unrelated failures**
- Confirm all pre-existing behavior remains unchanged.
