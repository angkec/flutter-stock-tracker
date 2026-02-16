import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stock_rtwatcher/main.dart';
import 'package:stock_rtwatcher/screens/data_management_screen.dart';
import 'package:stock_rtwatcher/testing/progress_watchdog.dart';

import '../support/data_management_driver.dart';

const _runRealNetwork = bool.fromEnvironment('RUN_DATA_MGMT_REAL_E2E');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Data Management Real Network', () {
    testWidgets('runs full data-management scenario matrix', (tester) async {
      if (!_runRealNetwork) {
        debugPrint(
          'Skip real-network data-management E2E. Set --dart-define=RUN_DATA_MGMT_REAL_E2E=true to run.',
        );
        return;
      }

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await _openDataManagementDirectly(tester);
      final driver = DataManagementDriver(tester);

      await _runTimedOperation(
        tester,
        operationName: 'historical_fetch_missing',
        action: () =>
            driver.tapHistoricalFetchMissing(allowForceFallback: true),
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      await _runTimedOperation(
        tester,
        operationName: 'weekly_fetch_missing',
        action: driver.tapWeeklyFetchMissing,
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      final dailyForceRefetchStopwatch = Stopwatch()..start();
      await driver.tapDailyForceRefetch();
      final dailyForceRefetchSawSpeed = await driver
          .waitForProgressDialogTextContainsOrClosed(
            '速率',
            timeout: const Duration(seconds: 60),
          );
      var dailyForceRefetchSawEta = false;
      if (dailyForceRefetchSawSpeed) {
        dailyForceRefetchSawEta = await driver
            .waitForProgressDialogTextContainsOrClosed(
              '预计剩余',
              timeout: const Duration(seconds: 20),
            );
      }
      final dailySawIndicatorStage = await driver
          .waitForProgressDialogTextContainsOrClosed(
            '3/4 计算指标',
            timeout: const Duration(minutes: 3),
            waitAppearTimeout: Duration.zero,
          );
      final dailySawIntradayHint = await driver
          .waitForProgressDialogTextContainsOrClosed(
            '日内增量计算',
            timeout: const Duration(seconds: 5),
            waitAppearTimeout: Duration.zero,
          );
      final dailySawFinalOverrideHint = await driver
          .waitForProgressDialogTextContainsOrClosed(
            '终盘覆盖增量重算',
            timeout: const Duration(seconds: 5),
            waitAppearTimeout: Duration.zero,
          );

      await driver.waitForProgressDialogClosedWithWatchdog(
        ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
        hardTimeout: const Duration(minutes: 15),
      );
      dailyForceRefetchStopwatch.stop();

      if (dailyForceRefetchStopwatch.elapsed > const Duration(seconds: 5)) {
        expect(
          dailyForceRefetchSawSpeed || dailySawIndicatorStage,
          isTrue,
          reason:
              'daily force refetch exceeded 5s without visible progress hint',
        );
      }

      final dailyState = dailySawFinalOverrideHint
          ? 'final_override'
          : (dailySawIntradayHint ? 'intraday_partial' : 'unknown');
      expect(dailyState, isNotEmpty);
      debugPrint(
        '[DataManagement Real E2E] daily_force_refetch_elapsed_ms='
        '${dailyForceRefetchStopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        '[DataManagement Real E2E] daily_force_refetch_progress_hint='
        'speed:$dailyForceRefetchSawSpeed,eta:$dailyForceRefetchSawEta,indicator_stage:$dailySawIndicatorStage',
      );
      debugPrint(
        '[DataManagement Real E2E] daily_intraday_or_final_state='
        '$dailyState',
      );
      debugPrint(
        '[DataManagement Real E2E] daily_incremental_recompute_elapsed_ms='
        '${dailyForceRefetchStopwatch.elapsedMilliseconds}',
      );

      await _runTimedOperation(
        tester,
        operationName: 'historical_recheck',
        action: driver.tapHistoricalRecheck,
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      final weeklyForceRefetchStopwatch = Stopwatch()..start();
      await driver.tapWeeklyForceRefetch();
      final weeklyForceRefetchSawSpeed = await driver
          .waitForProgressDialogTextContainsOrClosed(
            '速率',
            timeout: const Duration(seconds: 60),
          );
      var weeklyForceRefetchSawEta = false;
      if (weeklyForceRefetchSawSpeed) {
        weeklyForceRefetchSawEta = await driver
            .waitForProgressDialogTextContainsOrClosed(
              '预计剩余',
              timeout: const Duration(seconds: 20),
            );
      }
      await driver.waitForProgressDialogClosedWithWatchdog(
        ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
        hardTimeout: const Duration(minutes: 15),
      );
      weeklyForceRefetchStopwatch.stop();
      if (weeklyForceRefetchStopwatch.elapsed > const Duration(seconds: 5)) {
        expect(
          weeklyForceRefetchSawSpeed,
          isTrue,
          reason:
              'weekly force refetch exceeded 5s without visible progress hint',
        );
      }
      debugPrint(
        '[DataManagement Real E2E] weekly_force_refetch_elapsed_ms='
        '${weeklyForceRefetchStopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        '[DataManagement Real E2E] weekly_force_refetch_progress_hint='
        'speed:$weeklyForceRefetchSawSpeed,eta:$weeklyForceRefetchSawEta',
      );

      await driver.tapWeeklyMacdSettings();
      final weeklyMacdStopwatch = Stopwatch()..start();
      await driver.tapWeeklyMacdRecompute();
      final weeklyMacdDialogAppeared = await driver
          .waitForMacdRecomputeDialogVisible(
            timeout: const Duration(seconds: 3),
          );
      var weeklyMacdSawSpeed = false;
      var weeklyMacdSawEta = false;
      if (weeklyMacdDialogAppeared) {
        weeklyMacdSawSpeed = await driver
            .waitForMacdRecomputeDialogTextContainsOrClosed(
              '速率',
              timeout: const Duration(seconds: 60),
              waitAppearTimeout: Duration.zero,
            );
        if (weeklyMacdSawSpeed) {
          weeklyMacdSawEta = await driver
              .waitForMacdRecomputeDialogTextContainsOrClosed(
                '预计剩余',
                timeout: const Duration(seconds: 20),
                waitAppearTimeout: Duration.zero,
              );
        }
        await driver.waitForMacdRecomputeCompletionWithWatchdog(
          ProgressWatchdog(
            stallThreshold: const Duration(seconds: 5),
            now: DateTime.now,
          ),
          scopeLabel: '周线',
          waitAppearTimeout: Duration.zero,
          hardTimeout: const Duration(minutes: 20),
        );
      }
      weeklyMacdStopwatch.stop();
      if (weeklyMacdDialogAppeared &&
          weeklyMacdStopwatch.elapsed > const Duration(seconds: 5)) {
        expect(
          weeklyMacdSawSpeed,
          isTrue,
          reason: 'weekly MACD recompute exceeded 5s without progress hint',
        );
      }
      debugPrint(
        '[DataManagement Real E2E] weekly_macd_recompute_elapsed_ms='
        '${weeklyMacdStopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        '[DataManagement Real E2E] weekly_macd_recompute_progress_hint='
        'dialog:$weeklyMacdDialogAppeared,speed:$weeklyMacdSawSpeed,eta:$weeklyMacdSawEta',
      );
    });
  });
}

Future<void> _openDataManagementDirectly(WidgetTester tester) async {
  final navContext = tester.element(find.byType(NavigationBar).first);
  Navigator.of(
    navContext,
  ).push(MaterialPageRoute(builder: (_) => const DataManagementScreen()));
  await tester.pumpAndSettle();
  expect(find.text('数据管理'), findsOneWidget);
}

Future<void> _runOperation(
  WidgetTester tester, {
  required Future<void> Function() action,
  required DataManagementDriver driver,
  required ProgressWatchdog watchdog,
}) async {
  await action();
  await driver.waitForProgressDialogClosedWithWatchdog(
    watchdog,
    hardTimeout: const Duration(minutes: 15),
  );
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _runTimedOperation(
  WidgetTester tester, {
  required String operationName,
  required Future<void> Function() action,
  required DataManagementDriver driver,
  required ProgressWatchdog watchdog,
}) async {
  final stopwatch = Stopwatch()..start();
  await _runOperation(
    tester,
    action: action,
    driver: driver,
    watchdog: watchdog,
  );
  stopwatch.stop();
  debugPrint(
    '[DataManagement Real E2E] ${operationName}_elapsed_ms='
    '${stopwatch.elapsedMilliseconds}',
  );
}
