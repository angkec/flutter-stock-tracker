# Minute Kline 7 Trading Days Design

**Goal:** Change minute-kline range and validation to use the most recent 7 trading days (including today but allowing incomplete today), while keeping the real-network full-stock E2E behavior intact.

**Scope:** Data-layer real E2E test only.

## Architecture

The minute-kline range should be derived from trading dates discovered during the daily-kline stage. This keeps the range aligned with real trading days rather than calendar days. If trading dates are unavailable, fall back to recent weekdays to keep the minute range non-empty.

## Data Flow

1. Daily stage loads bars per stock and records trading dates into `minuteTradingDates`.
2. Before minute stage, compute the most recent 7 trading dates from `minuteTradingDates`.
   - If fewer than 7 trading dates exist, use all available.
   - If none exist, fall back to recent weekdays.
3. Use the earliest of those 7 trading dates as minute range start.
4. Use today 23:59:59 as minute range end.
5. Minute validation uses the same 7 trading dates but excludes today (allow incomplete).

## Behavior Changes

- Replace the calendar-day minute range (30 days) with a 7-trading-day range.
- Update report config label from `minute range days` to `minute trading days`.
- Preserve today-excluded validation and 90% pass thresholds.

## Error Handling

No change to allowed vs fatal error classification. Fatal errors still subject to 90% OK rule. The fallback to weekdays avoids empty-range failures.

## Testing

Add or adjust a small pure-function test to verify selection of last 7 trading dates and fallback behavior. Do not add network dependencies. E2E remains real-network full stock.
