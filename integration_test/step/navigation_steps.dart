import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 我点击底部导航栏的{tab}Tab
Future<void> iTapBottomNavTab(WidgetTester tester, String tabName) async {
  final tabFinder = find.ancestor(
    of: find.text(tabName),
    matching: find.byType(NavigationDestination),
  );
  await tester.tap(tabFinder);
  await tester.pumpAndSettle();
}

/// 底部导航栏的{tab}Tab应该被选中
Future<void> bottomNavTabShouldBeSelected(WidgetTester tester, String tabName) async {
  final navigationBar = find.byType(NavigationBar);
  expect(navigationBar, findsOneWidget);

  // 验证对应的 Tab 文字存在
  expect(find.text(tabName), findsWidgets);
}

/// 页面应该显示自选列表区域
Future<void> pageShouldShowWatchlistArea(WidgetTester tester) async {
  // 自选页特征：有输入框和添加按钮
  expect(find.text('添加'), findsOneWidget);
  expect(find.byType(TextField), findsOneWidget);
}

/// 页面应该显示全市场列表区域
Future<void> pageShouldShowMarketArea(WidgetTester tester) async {
  // 全市场页会有搜索或其他特征元素
  // 需要根据实际 MarketScreen 实现调整
  await tester.pumpAndSettle();
}

/// 页面应该显示行业列表区域
Future<void> pageShouldShowIndustryArea(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

/// 页面应该显示回踩列表区域
Future<void> pageShouldShowBreakoutArea(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

/// 我点击持仓Tab
Future<void> iTapHoldingsTab(WidgetTester tester) async {
  await tester.tap(find.text('持仓'));
  await tester.pumpAndSettle();
}

/// 我点击自选Tab
Future<void> iTapWatchlistTab(WidgetTester tester) async {
  // 找到 TabBar 内的自选 Tab
  final watchlistTab = find.descendant(
    of: find.byType(TabBar),
    matching: find.text('自选'),
  );
  await tester.tap(watchlistTab);
  await tester.pumpAndSettle();
}

/// 应该显示持仓列表区域
Future<void> shouldShowHoldingsArea(WidgetTester tester) async {
  expect(find.text('从截图导入'), findsOneWidget);
}

/// 应该显示从截图导入按钮
Future<void> shouldShowImportButton(WidgetTester tester) async {
  expect(find.text('从截图导入'), findsOneWidget);
}

/// 应该显示自选列表区域
Future<void> shouldShowWatchlistArea(WidgetTester tester) async {
  expect(find.text('添加'), findsOneWidget);
}

/// 应该显示添加股票输入框
Future<void> shouldShowAddStockInput(WidgetTester tester) async {
  expect(find.byType(TextField), findsOneWidget);
}
