# Minute Kline 7 Trading Days Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Change minute-kline range and validation to use the most recent 7 trading days (including today but allowing incomplete today), while keeping the real-network full-stock E2E behavior intact.

**Architecture:** Derive minute range from trading dates discovered during daily stage. Pick last 7 trading dates as the minute window; if none exist, fall back to recent weekdays. Update the report label accordingly.

**Tech Stack:** Dart, Flutter test, existing data-layer integration test.

---

### Task 1: Add helper for recent trading dates

**Files:**
- Modify: `test/integration/data_layer_real_e2e_test.dart`
- Test: `test/integration/data_layer_real_e2e_test.dart`

**Step 1: Write the failing test**

Add a pure-function test that verifies selecting the most recent 7 trading dates (sorted, last N) and fallback when input is empty.

```dart
  test('selectRecentTradingDates returns last N sorted dates', () {
    final dates = <DateTime>[
      DateTime(2024, 1, 2),
      DateTime(2024, 1, 1),
      DateTime(2024, 1, 5),
      DateTime(2024, 1, 4),
      DateTime(2024, 1, 3),
      DateTime(2024, 1, 8),
      DateTime(2024, 1, 7),
      DateTime(2024, 1, 6),
    ];

    final picked = _selectRecentTradingDates(dates, 7, fallbackEnd: DateTime(2024, 1, 8));

    expect(picked, [
      DateTime(2024, 1, 2),
      DateTime(2024, 1, 3),
      DateTime(2024, 1, 4),
      DateTime(2024, 1, 5),
      DateTime(2024, 1, 6),
      DateTime(2024, 1, 7),
      DateTime(2024, 1, 8),
    ]);
  });

  test('selectRecentTradingDates falls back to weekdays', () {
    final picked = _selectRecentTradingDates(const [], 3, fallbackEnd: DateTime(2024, 1, 8));

    expect(picked, [
      DateTime(2024, 1, 4),
      DateTime(2024, 1, 5),
      DateTime(2024, 1, 8),
    ]);
  });
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/integration/data_layer_real_e2e_test.dart --plain-name "selectRecentTradingDates" -r compact`
Expected: FAIL with "_selectRecentTradingDates not defined" or similar.

**Step 3: Write minimal implementation**

Add helper:

```dart
List<DateTime> _selectRecentTradingDates(
  Iterable<DateTime> dates,
  int count, {
  required DateTime fallbackEnd,
}) {
  final normalized = dates.map(_dateOnly).toSet().toList()..sort();
  if (normalized.isNotEmpty) {
    final startIndex = max(0, normalized.length - count);
    return normalized.sublist(startIndex);
  }
  final fallbackStart = fallbackEnd.subtract(Duration(days: count + 7));
  final weekdays = _weekdayDates(_dateOnly(fallbackStart), _dateOnly(fallbackEnd));
  if (weekdays.length <= count) return weekdays;
  return weekdays.sublist(weekdays.length - count);
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/integration/data_layer_real_e2e_test.dart --plain-name "selectRecentTradingDates" -r compact`
Expected: PASS.

**Step 5: Commit**

```bash
git add test/integration/data_layer_real_e2e_test.dart
git commit -m "test: add trading date selection helper"
```

### Task 2: Switch minute range to 7 trading days

**Files:**
- Modify: `test/integration/data_layer_real_e2e_test.dart`

**Step 1: Write failing test**

No new test; behavior covered by helper test and E2E run when desired.

**Step 2: Implement change**

- Replace `_minuteRangeDays` with `_minuteTradingDays = 7`.
- Compute `minuteTradingDatesRecent = _selectRecentTradingDates(minuteTradingDates, _minuteTradingDays, fallbackEnd: anchorDay)`.
- Set `minuteRange` start to `minuteTradingDatesRecent.first` when present; otherwise fallback output is already non-empty.
- Replace validation `tradingDates` with `minuteTradingDatesRecent`, excluding today.
- Update report line from `minute range days` to `minute trading days`.

**Step 3: Run focused tests**

Run: `flutter test test/integration/data_layer_real_e2e_test.dart --plain-name "data layer real e2e" -r compact`
Expected: PASS (real network; can be long).

**Step 4: Commit**

```bash
git add test/integration/data_layer_real_e2e_test.dart
git commit -m "test: use recent 7 trading days for minute range"
```

---

Plan complete and saved to `docs/plans/2026-02-18-minute-kline-7-trading-days-plan.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, fast iteration
2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Which approach?
