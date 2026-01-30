// Integration tests for watchlist management
// Based on watchlist.feature scenarios

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../step/common_steps.dart';
import '../step/watchlist_steps.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Watchlist Management', () {
    setUp(() {
      // Clear SharedPreferences before each test
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Empty watchlist shows hint', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And the watchlist is cleared
      await theWatchlistIsCleared(tester);
      // Then I should see the empty watchlist hint
      await shouldShowEmptyWatchlistHint(tester);
      // And I should see the add hint text
      await shouldShowAddHintText(tester);
    });

    testWidgets('Add valid stock code to watchlist', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And the watchlist is cleared
      await theWatchlistIsCleared(tester);
      // When I enter a stock code
      await iEnterStockCode(tester, '600519');
      // And I tap the add button
      await iTapAddButton(tester);
      // Then I should see the added snackbar
      await shouldShowAddedSnackbar(tester, '600519');
      // And the watchlist should contain the stock
      await watchlistShouldContainStock(tester, '600519');
    });

    testWidgets('Add invalid stock code', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And the watchlist is cleared
      await theWatchlistIsCleared(tester);
      // When I enter an invalid stock code
      await iEnterStockCode(tester, 'invalid');
      // And I tap the add button
      await iTapAddButton(tester);
      // Then I should see the invalid code snackbar
      await shouldShowInvalidCodeSnackbar(tester);
    });

    testWidgets('Add duplicate stock code', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And the watchlist is cleared
      await theWatchlistIsCleared(tester);
      // When I enter a stock code
      await iEnterStockCode(tester, '600519');
      // And I tap the add button
      await iTapAddButton(tester);
      // And I enter the same stock code again
      await iEnterStockCode(tester, '600519');
      // And I tap the add button
      await iTapAddButton(tester);
      // Then I should see the already exists snackbar
      await shouldShowAlreadyExistsSnackbar(tester);
    });

    testWidgets('Long press to delete stock', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And the watchlist contains a stock
      await watchlistContains(tester, '600519');
      // When I long press the stock
      await iLongPressStock(tester, '600519');
      // Then I should see the removed snackbar
      await shouldShowRemovedSnackbar(tester, '600519');
      // And the watchlist should not contain the stock
      await watchlistShouldNotContainStock(tester, '600519');
    });

    testWidgets('Watchlist data persists', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And the watchlist is cleared
      await theWatchlistIsCleared(tester);
      // When I enter a stock code
      await iEnterStockCode(tester, '600519');
      // And I tap the add button
      await iTapAddButton(tester);
      // And I restart the app
      await iRestartTheApp(tester);
      // Then the watchlist should contain the stock
      await watchlistShouldContainStock(tester, '600519');
    });
  });
}
