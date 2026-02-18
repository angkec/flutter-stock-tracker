# Data Layer E2E Report Enhancement Design

Date: 2026-02-18

## Summary
Improve the data-layer real-network E2E report to include per-stage and per-validation-type failure percentages plus a limited, first-seen sample of failed stock IDs. This is a report-only enhancement; it does not change fetch, validation, or failure classification behavior.

## Goals
- Add percentage of failed stocks for each validation category.
- Show a limited (10) first-seen list of stock IDs per category.
- Keep report layout familiar and minimally invasive.

## Non-Goals
- No changes to fetch strategy, validation rules, or pass/fail logic.
- No changes to test gating or execution behavior.
- No additional data artifacts beyond the existing report.

## Approach
1. Track first-seen order for each validation category:
   - daily short bars
   - weekly short bars
   - minute missing days
   - minute incomplete days
2. Compute percent failures per stage and validation type:
   - percent = (failedCount / stageTotal) * 100
   - use stageTotals already tracked in the test
3. Extend the report lines in “Validation Results”:
   - Include count, percent, and sample IDs (first-seen order, up to 10).

## Report Format Example
- daily short: 294 (5.6%) ids: 000001, 000002, ...
- weekly short: 272 (5.2%) ids: ...
- minute missing: 5298 (100.0%) ids: ...
- minute incomplete: 0 (0.0%) ids: none

## Error Handling
- If stageTotal is 0, percent is 0.0% to avoid division by zero.
- If no failures, sample IDs show “none”.

## Testing
- Add a small unit test for the report-line formatter to validate:
  - percent formatting
  - sample size limit
  - first-seen ordering
- Keep the main real-network test unchanged; only report formatting is updated.
