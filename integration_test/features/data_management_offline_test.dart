import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/testing/progress_watchdog.dart';

import '../support/data_management_driver.dart';
import '../support/data_management_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Data Management Offline', () {
    testWidgets('offline fixture opens data management page', (tester) async {
      await launchDataManagementWithFixture(tester);
      final driver = DataManagementDriver(tester);

      expect(find.text('数据管理'), findsOneWidget);
      await driver.ensureCardVisible('历史分钟K线');
      expect(find.text('历史分钟K线'), findsWidgets);
      expect(find.text('周K数据'), findsWidgets);
    });

    testWidgets('historical minute fetch completes with visible progress', (
      tester,
    ) async {
      final context = await launchDataManagementWithFixture(tester);
      final driver = DataManagementDriver(tester);

      await driver.tapHistoricalFetchMissing();
      await driver.expectProgressDialogVisible();
      await driver.waitForProgressDialogClosedWithWatchdog(
        context.createWatchdog(),
      );

      await driver.expectSnackBarContains('历史数据已更新');
    });

    testWidgets('weekly fetch completes and prewarms weekly MACD', (
      tester,
    ) async {
      final context = await launchDataManagementWithFixture(tester);
      final driver = DataManagementDriver(tester);

      await driver.tapWeeklyFetchMissing();
      await driver.expectProgressDialogVisible();
      await driver.waitForProgressDialogClosedWithWatchdog(
        context.createWatchdog(),
      );

      await driver.expectSnackBarContains('周K数据已更新');
      expect(context.macdService.prewarmCalls, greaterThan(0));
      expect(
        context.macdService.prewarmDataTypes,
        containsAll([KLineDataType.weekly]),
      );
    });

    testWidgets('daily force refetch completes with staged progress', (
      tester,
    ) async {
      final context = await launchDataManagementWithFixture(tester);
      final driver = DataManagementDriver(tester);

      await driver.tapDailyForceRefetch();
      await driver.expectProgressDialogVisible();
      await driver.waitForProgressDialogClosedWithWatchdog(
        context.createWatchdog(),
      );

      await driver.expectSnackBarContains('日K数据已强制重新拉取');
      expect(context.marketProvider.dailyForceRefetchCount, 1);
    });

    testWidgets('new trading day intraday partial path remains computable', (
      tester,
    ) async {
      final context = await launchDataManagementWithFixture(
        tester,
        preset: DataManagementFixturePreset.newTradingDayIntradayPartial,
      );
      final driver = DataManagementDriver(tester);

      await driver.tapDailyForceRefetch();
      await driver.expectProgressDialogVisible();
      await driver.waitForProgressDialogTextContains('日内增量计算');
      await driver.waitForProgressDialogClosedWithWatchdog(
        context.createWatchdog(),
      );

      await driver.expectSnackBarContains('日K数据已强制重新拉取');
      expect(
        context.marketProvider.lastDailyForceRefetchStages.any(
          (stage) => stage.contains('日内增量计算'),
        ),
        isTrue,
      );
    });

    testWidgets('post-close final snapshot path performs override recompute', (
      tester,
    ) async {
      final context = await launchDataManagementWithFixture(
        tester,
        preset: DataManagementFixturePreset.newTradingDayFinalOverride,
      );
      final driver = DataManagementDriver(tester);

      await driver.tapDailyForceRefetch();
      await driver.expectProgressDialogVisible();
      await driver.waitForProgressDialogTextContains('终盘覆盖增量重算');
      await driver.waitForProgressDialogClosedWithWatchdog(
        context.createWatchdog(),
      );

      await driver.expectSnackBarContains('日K数据已强制重新拉取');
      expect(
        context.marketProvider.lastDailyForceRefetchStages.any(
          (stage) => stage.contains('终盘覆盖增量重算'),
        ),
        isTrue,
      );
    });

    testWidgets('recheck freshness completes and shows result message', (
      tester,
    ) async {
      final context = await launchDataManagementWithFixture(tester);
      final driver = DataManagementDriver(tester);

      await driver.tapHistoricalRecheck();
      await driver.waitForProgressDialogClosedWithWatchdog(
        context.createWatchdog(),
      );

      await driver.expectSnackBarContains('数据完整性检测');
    });

    testWidgets(
      'weekly MACD recompute should avoid force-recompute startup stall',
      (tester) async {
        final context = await launchDataManagementWithFixture(tester);
        final driver = DataManagementDriver(tester);
        context.macdService.weeklyForceRecomputeInitialDelay = const Duration(
          seconds: 6,
        );

        await driver.tapWeeklyMacdSettings();
        await driver.tapWeeklyMacdRecompute();
        await driver.expectMacdRecomputeDialogVisible('周线');
        await driver.waitForMacdRecomputeDialogTextContains('速率');
        await driver.waitForMacdRecomputeDialogTextContains('预计剩余');
        await driver.waitForMacdRecomputeDialogClosedWithWatchdog(
          context.createWatchdog(),
          scopeLabel: '周线',
        );

        await driver.expectSnackBarContains('周线 MACD重算完成');
        expect(context.macdService.prewarmCalls, greaterThan(0));
        expect(context.macdService.prewarmDataTypes.last, KLineDataType.weekly);
        expect(context.macdService.prewarmForceRecomputeValues.last, isFalse);
        expect(context.macdService.prewarmFetchBatchSizes.last, 120);
        expect(context.macdService.prewarmPersistConcurrencyValues.last, 8);
      },
    );

    testWidgets('fails when no business progress for over 5 seconds', (
      tester,
    ) async {
      final context = await launchDataManagementWithFixture(
        tester,
        preset: DataManagementFixturePreset.stalledProgress,
      );
      final driver = DataManagementDriver(tester);

      await driver.tapHistoricalFetchMissing();
      await driver.expectProgressDialogVisible();

      Object? caught;
      try {
        await driver.waitForProgressDialogClosedWithWatchdog(
          context.createWatchdog(),
        );
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<ProgressStalledException>());

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'failed historical fetch closes dialog and keeps action usable',
      (tester) async {
        final context = await launchDataManagementWithFixture(
          tester,
          preset: DataManagementFixturePreset.failedFetch,
        );
        final driver = DataManagementDriver(tester);

        await driver.tapHistoricalFetchMissing();
        await driver.expectProgressDialogVisible();
        await driver.waitForProgressDialogClosedWithWatchdog(
          context.createWatchdog(),
        );

        await driver.expectSnackBarContains('历史数据拉取失败');
        expect(await driver.isHistoricalPrimaryActionEnabled(), isTrue);
      },
    );
  });
}
