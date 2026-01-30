// Integration tests for basic navigation
// Based on navigation.feature scenarios

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../step/common_steps.dart';
import '../step/navigation_steps.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Basic Navigation', () {
    testWidgets('App starts with watchlist tab selected', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // Then the watchlist tab in bottom nav should be selected
      await bottomNavTabShouldBeSelected(tester, '自选');
      // And the page should show the watchlist area
      await pageShouldShowWatchlistArea(tester);
    });

    testWidgets('Switch to market tab', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // When I tap the market tab in bottom nav
      await iTapBottomNavTab(tester, '全市场');
      // Then the market tab should be selected
      await bottomNavTabShouldBeSelected(tester, '全市场');
      // And the page should show the market area
      await pageShouldShowMarketArea(tester);
    });

    testWidgets('Switch to industry tab', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // When I tap the industry tab in bottom nav
      await iTapBottomNavTab(tester, '行业');
      // Then the industry tab should be selected
      await bottomNavTabShouldBeSelected(tester, '行业');
      // And the page should show the industry area
      await pageShouldShowIndustryArea(tester);
    });

    testWidgets('Switch to breakout tab', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // When I tap the breakout tab in bottom nav
      await iTapBottomNavTab(tester, '回踩');
      // Then the breakout tab should be selected
      await bottomNavTabShouldBeSelected(tester, '回踩');
      // And the page should show the breakout area
      await pageShouldShowBreakoutArea(tester);
    });

    testWidgets('Switch to holdings tab within watchlist page', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And I am on the watchlist page
      await iAmOnWatchlistPage(tester);
      // When I tap the holdings tab
      await iTapHoldingsTab(tester);
      // Then I should see the holdings area
      await shouldShowHoldingsArea(tester);
      // And I should see the import button
      await shouldShowImportButton(tester);
    });

    testWidgets('Switch back to watchlist tab within watchlist page', (tester) async {
      // Given the app is running
      await theAppIsRunning(tester);
      // And I am on the watchlist page
      await iAmOnWatchlistPage(tester);
      // When I tap the holdings tab
      await iTapHoldingsTab(tester);
      // And I tap the watchlist tab
      await iTapWatchlistTab(tester);
      // Then I should see the watchlist area
      await shouldShowWatchlistArea(tester);
      // And I should see the add stock input
      await shouldShowAddStockInput(tester);
    });
  });
}
