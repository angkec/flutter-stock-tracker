import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/main.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';

/// 应用已启动
Future<void> theAppIsRunning(WidgetTester tester) async {
  // 清空 SharedPreferences 确保测试隔离
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// 自选股列表已清空
Future<void> theWatchlistIsCleared(WidgetTester tester) async {
  final context = tester.element(find.byType(MaterialApp).first);
  final service = Provider.of<WatchlistService>(context, listen: false);
  final codes = List<String>.from(service.watchlist);
  for (final code in codes) {
    await service.removeStock(code);
  }
  await tester.pumpAndSettle();
}

/// 我重启应用
Future<void> iRestartTheApp(WidgetTester tester) async {
  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// 当前在自选页
Future<void> iAmOnWatchlistPage(WidgetTester tester) async {
  // 默认启动就在自选页，验证一下
  expect(find.text('自选'), findsWidgets);
}
