# Data Layer E2E Stage Prompts + 90% Threshold Design

Date: 2026-02-18

## Summary
Add console prompts for each stage (daily/weekly/minute) with start/end and duration, and update pass/fail logic to treat each validation type as passing when ≥90% of stocks are OK. Fatal fetch errors are no longer immediate failures; they are evaluated with the same 90% rule per stage.

## Goals
- Print console prompts for stage start and end with per-stage duration.
- Use 90% pass threshold per validation type:
  - Daily short bars
  - Weekly short bars
  - Minute missing days
  - Minute incomplete days
  - Daily fetch fatal errors
  - Weekly fetch fatal errors
  - Minute fetch fatal errors

## Non-Goals
- No changes to fetch behavior or validation rules.
- No change to report destinations.

## Approach
1. Add a lightweight console prompt helper for stage start/end.
2. Track per-stage durations (existing) and emit prompts on entry/exit.
3. Replace failure summary construction with threshold checks:
   - A category fails only if its OK rate < 90% (failedCount > 10% of total).
   - Fatal errors are evaluated as a separate category per stage.
4. Keep report formatting intact; only summary and console output change.

## Pass/Fail Logic
Let `total` be the stage total stocks. For each category:
- `failedCount = number of stocks failing the category`
- `okRate = (total - failedCount) / total`
- Pass if `okRate >= 0.90`

## Console Prompts (Examples)
- `[E2E] Stage daily start`
- `[E2E] Stage daily done, duration=12m34s`

## Risks
- Near-midnight runs may have slightly different anchor dates; unchanged from current behavior.
- Concurrency ordering affects first-seen lists; unchanged by these changes.
