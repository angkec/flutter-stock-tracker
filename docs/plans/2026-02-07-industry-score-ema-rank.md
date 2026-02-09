# Industry Score EMA Rank Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add configurable industry composite scoring from (z, q, breadth), 20-day EMA trend ranking, and rank-change signals, then expose it in daily board, 20-day trend view, and industry detail.

**Architecture:** Introduce a pure `IndustryScoreEngine` for breadth gate/raw score/EMA/rank calculations, persist computed fields in `industry_buildup_daily`, reuse `IndustryBuildUpService` as the single source of truth, and extend existing build-up widgets/screens to render score/rank trends.

**Tech Stack:** Dart, Flutter, sqflite, Provider, flutter_test.

---

### Task 1: Add failing tests for score engine behavior

**Files:**
- Create: `test/services/industry_score_engine_test.dart`

**Step 1: Write failing tests**

Cover:
- breadthGate clip behavior (`< minGate`, in-range, `> maxGate`)
- rawScore handling for null/NaN input consistency (0 strategy)
- EMA continuity with missing-day gaps in record stream
- rank/rankChange/rankArrow correctness and tie-break stability by industry name
- 3 industries x 5 days mock dataset demo expectation

**Step 2: Run tests and verify RED**

Run: `flutter test test/services/industry_score_engine_test.dart`
Expected: FAIL because engine does not exist yet.

---

### Task 2: Implement score engine and model fields

**Files:**
- Create: `lib/services/industry_score_engine.dart`
- Modify: `lib/models/industry_buildup.dart`

**Step 1: Add score config + score fields**

Add configurable params with defaults:
- `b0=0.25`
- `b1=0.50`
- `minGate=0.50`
- `maxGate=1.00`
- `alpha=0.30`

Extend `IndustryBuildupDailyRecord` with:
- `zPos`
- `breadthGate`
- `rawScore`
- `scoreEma`
- `rankChange`
- `rankArrow`

**Step 2: Implement `IndustryScoreEngine`**

Implement:
- breadth gate clip
- log score `ln(1+max(z,0))*q*breadthGate`
- NaN/null-safe strategy (fallback 0)
- per-industry EMA
- per-day ranking by `scoreEma desc`, tie-break by industry asc
- rank change and arrow generation

**Step 3: Run focused tests and verify GREEN**

Run: `flutter test test/services/industry_score_engine_test.dart`
Expected: PASS.

---

### Task 3: Integrate engine into build-up pipeline and persistence

**Files:**
- Modify: `lib/services/industry_buildup_service.dart`
- Modify: `lib/data/storage/database_schema.dart`
- Modify: `lib/data/storage/market_database.dart`
- Modify: `lib/data/storage/industry_buildup_storage.dart`
- Modify: `test/data/storage/market_database_test.dart`
- Modify: `test/data/storage/industry_buildup_storage_test.dart`
- Modify: `test/services/industry_buildup_service_test.dart`

**Step 1: Replace z-only ranking stage with score-engine output**

In recalc pipeline, build base day records then call engine once to enrich + rank.

**Step 2: Persist new score/rank-trend columns**

Add migration to next DB version and storage mappings.

**Step 3: Add/adjust storage-service tests**

Verify columns and roundtrip of new fields.

**Step 4: Run focused tests**

Run:
- `flutter test test/data/storage/market_database_test.dart`
- `flutter test test/data/storage/industry_buildup_storage_test.dart`
- `flutter test test/services/industry_buildup_service_test.dart`

---

### Task 4: UI integration for daily ranking + 20-day trend + detail trend block

**Files:**
- Modify: `lib/widgets/industry_buildup_list.dart`
- Modify: `lib/screens/industry_detail_screen.dart`
- Modify: `test/widgets/industry_buildup_list_test.dart`
- Modify: `test/screens/industry_detail_screen_test.dart`

**Step 1: Daily ranking list**

Default sort by `scoreEma` (trend strongest), add toggle to sort by `rawScore` (today spike), row shows:
- industry
- `scoreEma`
- `rawScore`
- `z/q/breadth`
- `rankArrow + abs(rankChange)`

**Step 2: 20-day trend view component (all industries)**

Add Top-N block based on latest `scoreEma`, render at least:
- scoreEma sparkline
- latest rank + 20-day min/max rank

**Step 3: Industry detail trend section**

Show per-day list with:
- day
- z/q/breadth
- rawScore
- scoreEma
- rank/rankChange/arrow
- optional summary line (score trend and rank X→Y)

**Step 4: Widget tests**

Update/extend widget tests for new text and sorting mode.

---

### Task 5: Full verification before completion

**Files:**
- None

**Step 1: Run impacted test suite**

Run:
- `flutter test test/services/industry_score_engine_test.dart`
- `flutter test test/services/industry_buildup_service_test.dart`
- `flutter test test/data/storage/market_database_test.dart`
- `flutter test test/data/storage/industry_buildup_storage_test.dart`
- `flutter test test/widgets/industry_buildup_list_test.dart`
- `flutter test test/screens/industry_detail_screen_test.dart`

**Step 2: (Optional) broader confidence run**

Run: `flutter test`

**Step 3: Prepare response**

Include:
- changed files
- test evidence
- 3-industry x 5-day mock output sample
