import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';

/// 应该显示暂无自选股提示
Future<void> shouldShowEmptyWatchlistHint(WidgetTester tester) async {
  expect(find.text('暂无自选股'), findsOneWidget);
}

/// 应该显示添加提示文字
Future<void> shouldShowAddHintText(WidgetTester tester) async {
  expect(find.text('在上方输入股票代码添加'), findsOneWidget);
}

/// 我在输入框中输入 {code}
Future<void> iEnterStockCode(WidgetTester tester, String code) async {
  final textField = find.byType(TextField);
  await tester.enterText(textField, code);
  await tester.pumpAndSettle();
}

/// 我点击添加按钮
Future<void> iTapAddButton(WidgetTester tester) async {
  await tester.tap(find.text('添加'));
  await tester.pumpAndSettle();
}

/// 应该显示已添加提示
Future<void> shouldShowAddedSnackbar(WidgetTester tester, String code) async {
  expect(find.text('已添加 $code'), findsOneWidget);
}

/// 应该显示无效股票代码提示
Future<void> shouldShowInvalidCodeSnackbar(WidgetTester tester) async {
  expect(find.text('无效的股票代码'), findsOneWidget);
}

/// 应该显示该股票已在自选列表中提示
Future<void> shouldShowAlreadyExistsSnackbar(WidgetTester tester) async {
  expect(find.text('该股票已在自选列表中'), findsOneWidget);
}

/// 自选列表包含 {code}
Future<void> watchlistContains(WidgetTester tester, String code) async {
  final context = tester.element(find.byType(MaterialApp).first);
  final service = Provider.of<WatchlistService>(context, listen: false);
  if (!service.contains(code)) {
    await service.addStock(code);
  }
  await tester.pumpAndSettle();
}

/// 自选列表应该包含该股票
Future<void> watchlistShouldContainStock(
  WidgetTester tester,
  String code,
) async {
  // 验证 UI 中显示了该股票代码
  // 注意：可能需要等待数据加载
  await tester.pumpAndSettle(const Duration(seconds: 1));
  expect(find.textContaining(code), findsWidgets);
}

/// 自选列表不应包含该股票
Future<void> watchlistShouldNotContainStock(
  WidgetTester tester,
  String code,
) async {
  await tester.pumpAndSettle();
  expect(find.text(code), findsNothing);
}

/// 我长按列表中的该股票
Future<void> iLongPressStock(WidgetTester tester, String code) async {
  final stockItem = find.textContaining(code);
  await tester.longPress(stockItem.first);
  await tester.pumpAndSettle();
}

/// 应该显示已移除提示
Future<void> shouldShowRemovedSnackbar(WidgetTester tester, String code) async {
  expect(find.text('已移除 $code'), findsOneWidget);
}
