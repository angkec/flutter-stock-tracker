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

      await _runOperation(
        tester,
        action: () =>
            driver.tapHistoricalFetchMissing(allowForceFallback: true),
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      await _runOperation(
        tester,
        action: driver.tapWeeklyFetchMissing,
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      await _runOperation(
        tester,
        action: driver.tapDailyForceRefetch,
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      await _runOperation(
        tester,
        action: driver.tapHistoricalRecheck,
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      await _runOperation(
        tester,
        action: driver.tapWeeklyForceRefetch,
        driver: driver,
        watchdog: ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
      );

      await driver.tapWeeklyMacdSettings();
      await driver.tapWeeklyMacdRecompute();
      await driver.waitForMacdRecomputeCompletionWithWatchdog(
        ProgressWatchdog(
          stallThreshold: const Duration(seconds: 5),
          now: DateTime.now,
        ),
        scopeLabel: '周线',
        hardTimeout: const Duration(minutes: 20),
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
