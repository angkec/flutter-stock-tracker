import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/main.dart';

/// 应用已启动
Future<void> theAppIsRunning(WidgetTester tester) async {
  // 清空 SharedPreferences 确保测试隔离
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// 自选股列表已清空
Future<void> theWatchlistIsCleared(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'watchlist': <String>[]});
  // 不需要重启，因为在 theAppIsRunning 中会加载
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
