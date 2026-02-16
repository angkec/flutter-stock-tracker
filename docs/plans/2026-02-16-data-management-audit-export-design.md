# Data Management Audit Export + Diagnostic Console Design (2026-02-16)

## 1. Goal

Provide an on-device, exportable audit mechanism for Data Management workflows so bugs, missed data/calculation issues, and future latency bottlenecks can be surfaced and acted on with evidence.

V1 priorities:

1. Reliability-first strict PASS/FAIL verdict for each audited run.
2. Persist structured audit facts on-device (not ephemeral debug text).
3. Add simple "Latest Audit" UI in Data Management with clear PASS/FAIL and reasons.
4. Allow one-tap export of latest audit artifacts.
5. Log latency and stage timing as evidence, but do not fail based on latency in V1.

## 2. Scope

### In Scope (V1)

Data Management entry points only:

1. Historical minute K fetch (`fetchMissingData` / `refetchData` path from Data Management screen).
2. Daily force refetch.
3. Weekly fetch missing.
4. Weekly force refetch.
5. Weekly MACD recompute path.

### Out of Scope (V1)

1. Main market refresh flow outside Data Management.
2. Remote telemetry backend upload.
3. Latency-based fail verdicts.
4. Heavy dashboard analytics.

## 3. Options Considered

### Option A: Parse Existing Logs

- Pros: minimal code changes.
- Cons: brittle (string-coupled), low trust, hard to evolve.

### Option B: Summary-Only Audit Rows

- Pros: compact and simple.
- Cons: weak root-cause diagnostics; loses stage-level evidence.

### Option C: Event-Sourced Audit Trail (Chosen)

- Pros: reliable, structured, exportable, root-cause friendly.
- Cons: requires explicit instrumentation at operation boundaries.

Chosen: **Option C**.

## 4. Architecture Overview

Introduce a dedicated audit subsystem with append-only event persistence.

Core components:

1. `AuditOperationRunner`
   - Wraps each Data Management operation lifecycle.
   - Creates `runId`, records start/finish, and emits normalized events.

2. `AuditRecorder`
   - Appends structured `AuditEvent` entries to JSONL files.
   - Handles file rotation and retention.

3. `AuditVerdictEngine`
   - Computes strict PASS/FAIL for a run from factual events.
   - Produces reason codes and summary counters.

4. `LatestAuditIndexStore`
   - Small index file for instant "Latest Audit" UI read.
   - Avoids scanning all JSONL files during screen build.

5. `AuditExportService`
   - Exports latest run or recent files for sharing.

## 5. Data Model

### 5.1 AuditRun Summary

Fields:

- `run_id` (UUID/string)
- `operation_type` (`historical_fetch_missing`, `daily_force_refetch`, `weekly_fetch_missing`, `weekly_force_refetch`, `weekly_macd_recompute`)
- `started_at`, `completed_at`
- `verdict` (`pass` or `fail`)
- `reason_codes` (`List<String>`)
- `app_version`
- `stock_count`
- `date_range` (optional normalized window)
- counters:
  - `error_count`
  - `missing_count`
  - `incomplete_count`
  - `unknown_state_count`
  - `updated_stock_count`
  - `total_records`
- metrics:
  - `elapsed_ms`
  - `stage_durations_ms` (`Map<String, int>`)

### 5.2 AuditEvent (JSONL line)

Common fields:

- `ts` (ISO8601)
- `run_id`
- `operation_type`
- `event_type`
- `payload` (typed map)

Event types:

1. `run_started`
2. `stage_started`
3. `stage_progress`
4. `stage_completed`
5. `fetch_result`
6. `verification_result`
7. `completeness_state`
8. `indicator_recompute_result`
9. `error_raised`
10. `run_completed`

Notes:

- Payload keys are stable and documented; no parsing of UI text.
- Numeric metrics remain numeric for later aggregation.

## 6. Strict Reliability Verdict Rules (V1)

A run is `FAIL` if any condition holds:

1. Any fetch or compute stage reports error/exception.
2. Post-fetch verification indicates missing dates/stocks.
3. Post-fetch verification indicates incomplete dates/stocks where complete data is expected.
4. Completeness/finalization state is `unknown` in reliability-critical flow.
5. Invariant breach:
   - data changed but recompute scope/result is empty unexpectedly,
   - or stage completion is inconsistent with observed updates.

A run is `PASS` only when all strict checks pass.

Latency handling in V1:

- Always recorded (`elapsed_ms`, stage timing, throughput samples).
- Never used as PASS/FAIL criteria in V1.

## 7. Storage and Retention

Path (app documents):

- `audit/audit-YYYY-MM-DD.jsonl`
- `audit/latest_run_index.json`

Retention:

1. Rotate by day and max file size.
2. Keep recent N days (configurable, default 14).
3. Best-effort cleanup; cleanup failures are non-fatal.

Durability:

1. Append-only writes with flush after line write.
2. Partial final line tolerated during crash; parser skips malformed tail line.

## 8. Integration Points

Primary integration file:

- `lib/screens/data_management_screen.dart`

Instrumentation strategy:

1. Each audited button action starts an `AuditOperationRunner`.
2. Existing stage transitions and progress callbacks map to `stage_*` events.
3. Repository/provider outcomes (`FetchResult`, verification outputs, recompute results) map to factual events.
4. Catch blocks emit `error_raised`.
5. Finally blocks emit `run_completed` with verdict from `AuditVerdictEngine`.

Secondary integration points:

1. `lib/providers/market_data_provider.dart`:
   - daily force refetch stage timings and indicator scope facts.
2. Optional helper hooks in repository responses for verification counters.

## 9. Diagnostic Console UI (Frontend Direction)

Location:

- Top area in Data Management page as a dedicated card/panel.

Visual direction:

- **Diagnostic Console** (high signal, operations-focused).
- Hard edges, high-contrast separators, restrained industrial palette.
- Reliability state is dominant; metrics are secondary.

Panel structure:

1. Left `verdict rail`
   - `PASS` (green) / `FAIL` (red)
   - subtle pulse if latest run failed recently.
2. Center summary
   - operation + completion time
   - `Reliability Check: PASS/FAIL`
   - reason chips (`unknown_state`, `missing_after_fetch`, etc.)
   - compact metric row (`errors`, `missing`, `incomplete`, `unknown`, `elapsed_ms`)
3. Right actions
   - `View Details`
   - `Export Latest Audit`
   - overflow: `Export Last 7 Days`

Detail sheet:

1. Ordered reason list (highest severity first).
2. Stage timeline with key checkpoints.
3. Evidence counters and timing (timing is informational only).

## 10. Export Behavior

Actions:

1. Export latest run:
   - include run summary JSON + source JSONL lines for that run.
2. Export last 7 days:
   - include all retained JSONL files within window + latest index.

Output:

- Timestamped package/file name for easy bug report attachment.
- User-facing success/failure toast with output path or share result.

## 11. Error Handling

Principles:

1. Audit must not block core data operation success path.
2. Recorder failures degrade gracefully:
   - operation still runs,
   - emit best-effort in-memory warning,
   - UI can show `audit_write_warning` reason when summary cannot persist.
3. Export failures are explicit to user but do not alter core data state.

## 12. Testing Plan

### Unit Tests

1. Verdict engine:
   - PASS happy path.
   - FAIL on each strict rule trigger.
2. Recorder:
   - append/read roundtrip.
   - malformed tail line tolerance.
   - retention cleanup.
3. Latest index store:
   - update/read consistency.
4. Export service:
   - latest-run package contents.
   - date-window filtering.

### Widget Tests

1. Diagnostic Console card:
   - PASS/FAIL rendering.
   - reason chips visibility.
   - metric row display.
2. Details sheet:
   - reason ordering and stage list.

### Integration Tests

1. Data Management audited operation emits run and updates latest status.
2. Fail scenario produces FAIL verdict with expected reason code.
3. Export button creates expected artifact.

## 13. Rollout Plan

1. Implement audit core (models, recorder, verdict engine, export).
2. Integrate daily force refetch path first.
3. Integrate remaining Data Management operations.
4. Add Diagnostic Console UI + details sheet + export actions.
5. Add tests and verification.

## 14. Acceptance Criteria

1. Every V1 in-scope Data Management run generates a structured audit record.
2. Latest Audit card shows deterministic PASS/FAIL from strict reliability rules.
3. FAIL runs expose machine-readable reason codes.
4. Export latest audit works on-device and includes run evidence.
5. Latency and stage timings are recorded for each run but do not affect verdict.

