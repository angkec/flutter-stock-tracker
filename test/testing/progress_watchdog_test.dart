import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/testing/progress_watchdog.dart';

void main() {
  test('throws when no progress for over threshold', () {
    var currentNow = DateTime(2026, 2, 15, 10, 0, 0);
    final watchdog = ProgressWatchdog(
      stallThreshold: const Duration(seconds: 5),
      now: () => currentNow,
    );

    watchdog.markProgress('1/4 拉取K线数据 1/100');
    currentNow = DateTime(2026, 2, 15, 10, 0, 6);

    expect(
      () => watchdog.assertNotStalled(),
      throwsA(isA<ProgressStalledException>()),
    );
  });

  test('does not throw while progress keeps changing', () {
    var currentNow = DateTime(2026, 2, 15, 10, 0, 0);
    final watchdog = ProgressWatchdog(
      stallThreshold: const Duration(seconds: 5),
      now: () => currentNow,
    );

    watchdog.markProgress('1/4 拉取K线数据 1/100');
    currentNow = DateTime(2026, 2, 15, 10, 0, 3);
    watchdog.markProgress('1/4 拉取K线数据 2/100');

    watchdog.assertNotStalled();
  });

  test('does not throw before first progress signal', () {
    final watchdog = ProgressWatchdog(
      stallThreshold: const Duration(seconds: 5),
      now: () => DateTime(2026, 2, 15, 10, 0, 6),
    );

    watchdog.assertNotStalled();
  });
}
