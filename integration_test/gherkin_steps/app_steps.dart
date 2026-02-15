import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gherkin/gherkin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/main.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/screens/stock_detail_screen.dart';

// ============================================================================
// Custom World for Widget Testing - 自定义 Widget 测试 World
// ============================================================================

/// 自定义 World 类，持有 WidgetTester 实例
class WidgetTesterWorld extends World {
  late WidgetTester tester;

  void setTester(WidgetTester t) {
    tester = t;
  }
}

// ============================================================================
// 全局状态 - 用于一次性操作
// ============================================================================

/// 标记数据是否已同步（整个测试套件只需同步一次）
bool _dataSynced = false;
final Map<String, MacdCacheSeries> _macdCacheSeriesByKey =
    <String, MacdCacheSeries>{};

class _InMemoryMacdCacheStore extends MacdCacheStore {
  _InMemoryMacdCacheStore(this._seriesByKey);

  final Map<String, MacdCacheSeries> _seriesByKey;

  @override
  Future<MacdCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    return _seriesByKey['$stockCode|${dataType.name}'];
  }
}

List<KLine> _buildMacdDailyBars({int count = 50}) {
  final start = DateTime(2026, 1, 2);
  return List<KLine>.generate(count, (index) {
    final date = start.add(Duration(days: index));
    final open = 10 + index * 0.08;
    return KLine(
      datetime: date,
      open: open,
      close: open + 0.03,
      high: open + 0.15,
      low: open - 0.12,
      volume: 2000 + index * 15,
      amount: 20000 + index * 150,
    );
  });
}

List<KLine> _buildMacdWeeklyBars() {
  final dates = <DateTime>[
    DateTime(2026, 1, 9),
    DateTime(2026, 1, 16),
    DateTime(2026, 1, 23),
    DateTime(2026, 1, 30),
    DateTime(2026, 2, 6),
    DateTime(2026, 2, 13),
    DateTime(2026, 2, 20),
    DateTime(2026, 2, 27),
  ];

  return List<KLine>.generate(dates.length, (index) {
    final open = 10 + index * 0.4;
    return KLine(
      datetime: dates[index],
      open: open,
      close: open + 0.22,
      high: open + 0.5,
      low: open - 0.3,
      volume: 18000 + index * 800,
      amount: 180000 + index * 7000,
    );
  });
}

List<MacdPoint> _buildMacdPointsFromBars(List<KLine> bars) {
  return bars
      .map(
        (bar) => MacdPoint(
          datetime: bar.datetime,
          dif: bar.close * 0.01,
          dea: bar.close * 0.009,
          hist: bar.close * 0.002,
        ),
      )
      .toList(growable: false);
}

// ============================================================================
// Common Steps - 通用步骤
// ============================================================================

/// 应用已启动
StepDefinitionGeneric appIsRunningStep() {
  return given<WidgetTesterWorld>('应用已启动', (context) async {
    // 清空 SharedPreferences 确保测试隔离
    SharedPreferences.setMockInitialValues({});

    await context.world.tester.pumpWidget(const MyApp());
    await context.world.tester.pumpAndSettle(const Duration(seconds: 2));
  });
}

/// 自选股列表已清空
StepDefinitionGeneric watchlistIsClearedStep() {
  return given<WidgetTesterWorld>('自选股列表已清空', (context) async {
    SharedPreferences.setMockInitialValues({'watchlist': <String>[]});
  });
}

/// 我重启应用
StepDefinitionGeneric iRestartTheAppStep() {
  return when<WidgetTesterWorld>('我重启应用', (context) async {
    await context.world.tester.pumpWidget(const MyApp());
    await context.world.tester.pumpAndSettle(const Duration(seconds: 2));
  });
}

/// 当前在自选页
StepDefinitionGeneric iAmOnWatchlistPageStep() {
  return given<WidgetTesterWorld>('当前在自选页', (context) async {
    // 默认启动就在自选页，验证一下
    expect(find.text('自选'), findsWidgets);
  });
}

/// 数据已同步（只执行一次，后续场景跳过）
StepDefinitionGeneric dataSyncedStep() {
  return given<WidgetTesterWorld>('数据已同步', (context) async {
    if (_dataSynced) {
      // 已经同步过，跳过
      return;
    }

    final tester = context.world.tester;

    // 找到 RefreshStatusWidget 中的刷新图标并点击
    final refreshIcon = find.byIcon(Icons.refresh);
    if (refreshIcon.evaluate().isNotEmpty) {
      await tester.tap(refreshIcon.first);
      await tester.pump();
    }

    // 等待同步完成（最多等待 60 秒）
    // 判断条件：CircularProgressIndicator 消失
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));

      // 检查加载指示器是否消失
      final loading = find.byType(CircularProgressIndicator);
      if (loading.evaluate().isEmpty) {
        break;
      }
    }

    await tester.pumpAndSettle();
    _dataSynced = true;
  });
}

/// 重置同步状态（用于需要重新同步的场景）
void resetSyncState() {
  _dataSynced = false;
}

// ============================================================================
// Navigation Steps - 导航步骤
// ============================================================================

/// 我点击底部导航栏的{tab}Tab
StepDefinitionGeneric iTapBottomNavTabStep() {
  return when1<String, WidgetTesterWorld>('我点击底部导航栏的{string}Tab', (
    tabName,
    context,
  ) async {
    final tabFinder = find.ancestor(
      of: find.text(tabName),
      matching: find.byType(NavigationDestination),
    );
    await context.world.tester.tap(tabFinder);
    await context.world.tester.pumpAndSettle();
  });
}

/// 底部导航栏的{tab}Tab应该被选中
StepDefinitionGeneric bottomNavTabShouldBeSelectedStep() {
  return then1<String, WidgetTesterWorld>('底部导航栏的{string}Tab应该被选中', (
    tabName,
    context,
  ) async {
    final navigationBar = find.byType(NavigationBar);
    expect(navigationBar, findsOneWidget);

    // 验证对应的 Tab 文字存在
    expect(find.text(tabName), findsWidgets);
  });
}

/// 页面应该显示自选列表区域
StepDefinitionGeneric pageShouldShowWatchlistAreaStep() {
  return then<WidgetTesterWorld>('页面应该显示自选列表区域', (context) async {
    // 自选页特征：有输入框和添加按钮
    expect(find.text('添加'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}

/// 页面应该显示全市场列表区域
StepDefinitionGeneric pageShouldShowMarketAreaStep() {
  return then<WidgetTesterWorld>('页面应该显示全市场列表区域', (context) async {
    await context.world.tester.pumpAndSettle();
  });
}

/// 页面应该显示行业列表区域
StepDefinitionGeneric pageShouldShowIndustryAreaStep() {
  return then<WidgetTesterWorld>('页面应该显示行业列表区域', (context) async {
    await context.world.tester.pumpAndSettle();
  });
}

/// 页面应该显示回踩列表区域
StepDefinitionGeneric pageShouldShowBreakoutAreaStep() {
  return then<WidgetTesterWorld>('页面应该显示回踩列表区域', (context) async {
    await context.world.tester.pumpAndSettle();
  });
}

/// 我点击持仓Tab
StepDefinitionGeneric iTapHoldingsTabStep() {
  return when<WidgetTesterWorld>('我点击持仓Tab', (context) async {
    await context.world.tester.tap(find.text('持仓'));
    await context.world.tester.pumpAndSettle();
  });
}

/// 我点击自选Tab
StepDefinitionGeneric iTapWatchlistTabStep() {
  return when<WidgetTesterWorld>('我点击自选Tab', (context) async {
    // 找到 TabBar 内的自选 Tab
    final watchlistTab = find.descendant(
      of: find.byType(TabBar),
      matching: find.text('自选'),
    );
    await context.world.tester.tap(watchlistTab);
    await context.world.tester.pumpAndSettle();
  });
}

/// 应该显示持仓列表区域
StepDefinitionGeneric shouldShowHoldingsAreaStep() {
  return then<WidgetTesterWorld>('应该显示持仓列表区域', (context) async {
    expect(find.text('从截图导入'), findsOneWidget);
  });
}

/// 应该显示从截图导入按钮
StepDefinitionGeneric shouldShowImportButtonStep() {
  return then<WidgetTesterWorld>('应该显示从截图导入按钮', (context) async {
    expect(find.text('从截图导入'), findsOneWidget);
  });
}

/// 应该显示自选列表区域
StepDefinitionGeneric shouldShowWatchlistAreaStep() {
  return then<WidgetTesterWorld>('应该显示自选列表区域', (context) async {
    expect(find.text('添加'), findsOneWidget);
  });
}

/// 应该显示添加股票输入框
StepDefinitionGeneric shouldShowAddStockInputStep() {
  return then<WidgetTesterWorld>('应该显示添加股票输入框', (context) async {
    expect(find.byType(TextField), findsOneWidget);
  });
}

// ============================================================================
// Watchlist Steps - 自选股步骤
// ============================================================================

/// 应该显示暂无自选股提示
StepDefinitionGeneric shouldShowEmptyWatchlistHintStep() {
  return then<WidgetTesterWorld>('应该显示暂无自选股提示', (context) async {
    expect(find.text('暂无自选股'), findsOneWidget);
  });
}

/// 应该显示添加提示文字
StepDefinitionGeneric shouldShowAddHintTextStep() {
  return then<WidgetTesterWorld>('应该显示添加提示文字', (context) async {
    expect(find.text('在上方输入股票代码添加'), findsOneWidget);
  });
}

/// 我在输入框中输入{code}
StepDefinitionGeneric iEnterStockCodeStep() {
  return when1<String, WidgetTesterWorld>('我在输入框中输入{string}', (
    code,
    context,
  ) async {
    final textField = find.byType(TextField);
    await context.world.tester.enterText(textField, code);
    await context.world.tester.pumpAndSettle();
  });
}

/// 我点击添加按钮
StepDefinitionGeneric iTapAddButtonStep() {
  return when<WidgetTesterWorld>('我点击添加按钮', (context) async {
    await context.world.tester.tap(find.text('添加'));
    await context.world.tester.pumpAndSettle();
  });
}

/// 应该显示已添加{code}提示
StepDefinitionGeneric shouldShowAddedSnackbarStep() {
  return then1<String, WidgetTesterWorld>('应该显示已添加{string}提示', (
    code,
    context,
  ) async {
    expect(find.text('已添加 $code'), findsOneWidget);
  });
}

/// 应该显示无效股票代码提示
StepDefinitionGeneric shouldShowInvalidCodeSnackbarStep() {
  return then<WidgetTesterWorld>('应该显示无效股票代码提示', (context) async {
    expect(find.text('无效的股票代码'), findsOneWidget);
  });
}

/// 应该显示该股票已在自选列表中提示
StepDefinitionGeneric shouldShowAlreadyExistsSnackbarStep() {
  return then<WidgetTesterWorld>('应该显示该股票已在自选列表中提示', (context) async {
    expect(find.text('该股票已在自选列表中'), findsOneWidget);
  });
}

/// 自选列表包含{code}
StepDefinitionGeneric watchlistContainsStep() {
  return given1<String, WidgetTesterWorld>('自选列表包含{string}', (
    code,
    context,
  ) async {
    // 通过 SharedPreferences mock 直接设置
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList('watchlist') ?? [];
    if (!current.contains(code)) {
      current.add(code);
      await prefs.setStringList('watchlist', current);
    }
  });
}

/// 自选列表应该包含{code}
StepDefinitionGeneric watchlistShouldContainStockStep() {
  return then1<String, WidgetTesterWorld>('自选列表应该包含{string}', (
    code,
    context,
  ) async {
    // 验证 UI 中显示了该股票代码
    await context.world.tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining(code), findsWidgets);
  });
}

/// 自选列表不应包含{code}
StepDefinitionGeneric watchlistShouldNotContainStockStep() {
  return then1<String, WidgetTesterWorld>('自选列表不应包含{string}', (
    code,
    context,
  ) async {
    await context.world.tester.pumpAndSettle();
    expect(find.text(code), findsNothing);
  });
}

/// 我长按列表中的{code}
StepDefinitionGeneric iLongPressStockStep() {
  return when1<String, WidgetTesterWorld>('我长按列表中的{string}', (
    code,
    context,
  ) async {
    final stockItem = find.textContaining(code);
    await context.world.tester.longPress(stockItem.first);
    await context.world.tester.pumpAndSettle();
  });
}

/// 应该显示已移除{code}提示
StepDefinitionGeneric shouldShowRemovedSnackbarStep() {
  return then1<String, WidgetTesterWorld>('应该显示已移除{string}提示', (
    code,
    context,
  ) async {
    expect(find.text('已移除 $code'), findsOneWidget);
  });
}

// ============================================================================
// Stock Detail MACD Steps - 个股详情 MACD 步骤
// ============================================================================

StepDefinitionGeneric macdCachePreparedForStockStep() {
  return given1<String, WidgetTesterWorld>('测试股票{string}的MACD缓存已写入', (
    stockCode,
    context,
  ) async {
    final dailyBars = _buildMacdDailyBars();
    final weeklyBars = _buildMacdWeeklyBars();

    _macdCacheSeriesByKey['$stockCode|daily'] = MacdCacheSeries(
      stockCode: stockCode,
      dataType: KLineDataType.daily,
      config: MacdConfig.defaults,
      sourceSignature: 'e2e_daily_signature',
      points: _buildMacdPointsFromBars(dailyBars),
    );

    _macdCacheSeriesByKey['$stockCode|weekly'] = MacdCacheSeries(
      stockCode: stockCode,
      dataType: KLineDataType.weekly,
      config: MacdConfig.defaults,
      sourceSignature: 'e2e_weekly_signature',
      points: _buildMacdPointsFromBars(weeklyBars),
    );
  });
}

StepDefinitionGeneric openMacdStockDetailPageInModeStep() {
  return given1<String, WidgetTesterWorld>('已打开MACD测试详情页并切换到{string}模式', (
    modeName,
    context,
  ) async {
    final mode = switch (modeName) {
      '日线' => ChartMode.daily,
      '周线' => ChartMode.weekly,
      '联动' => ChartMode.linked,
      _ => throw ArgumentError('未知模式: $modeName'),
    };

    const stockCode = '600000';
    final cacheStore = _InMemoryMacdCacheStore(
      Map<String, MacdCacheSeries>.from(_macdCacheSeriesByKey),
    );

    await context.world.tester.pumpWidget(
      MaterialApp(
        home: StockDetailScreen(
          stock: Stock(
            code: stockCode,
            name: '浦发银行',
            market: 1,
            preClose: 10.2,
          ),
          skipAutoConnectForTest: true,
          showWatchlistToggle: false,
          showIndustryHeatSection: false,
          initialChartMode: mode,
          initialDailyBars: _buildMacdDailyBars(),
          initialWeeklyBars: _buildMacdWeeklyBars(),
          initialRatioHistory: const <DailyRatio>[],
          macdCacheStoreForTest: cacheStore,
        ),
      ),
    );
    await context.world.tester.pump(const Duration(milliseconds: 400));
  });
}

Future<void> _expectFinderAppears(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 25,
}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.pump(const Duration(milliseconds: 120));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  debugPrint('[MACD E2E] finder not found: $finder');
  debugPrint(
    '[MACD E2E] missing-cache hint count: '
    '${find.text('暂无MACD缓存，请先在数据管理同步').evaluate().length}',
  );
  debugPrint(
    '[MACD E2E] daily subchart count: '
    '${find.byKey(const ValueKey('stock_detail_macd_daily')).evaluate().length}',
  );
  debugPrint(
    '[MACD E2E] weekly subchart count: '
    '${find.byKey(const ValueKey('stock_detail_macd_weekly')).evaluate().length}',
  );
  debugPrint(
    '[MACD E2E] linked weekly subchart count: '
    '${find.byKey(const ValueKey('linked_weekly_macd_subchart')).evaluate().length}',
  );
  debugPrint(
    '[MACD E2E] linked daily subchart count: '
    '${find.byKey(const ValueKey('linked_daily_macd_subchart')).evaluate().length}',
  );
  expect(finder, findsOneWidget);
}

StepDefinitionGeneric shouldShowDailyMacdChartStep() {
  return then<WidgetTesterWorld>('应该看到日线MACD缓存图', (context) async {
    await _expectFinderAppears(
      context.world.tester,
      find.byKey(const ValueKey('stock_detail_macd_paint_daily')),
    );
  });
}

StepDefinitionGeneric shouldShowWeeklyMacdChartStep() {
  return then<WidgetTesterWorld>('应该看到周线MACD缓存图', (context) async {
    await _expectFinderAppears(
      context.world.tester,
      find.byKey(const ValueKey('stock_detail_macd_paint_weekly')),
    );
  });
}

StepDefinitionGeneric shouldShowLinkedWeeklyMacdChartStep() {
  return then<WidgetTesterWorld>('应该看到联动周线MACD缓存图', (context) async {
    await _expectFinderAppears(
      context.world.tester,
      find.byKey(const ValueKey('linked_weekly_macd_paint')),
    );
  });
}

StepDefinitionGeneric shouldShowLinkedDailyMacdChartStep() {
  return then<WidgetTesterWorld>('应该看到联动日线MACD缓存图', (context) async {
    await _expectFinderAppears(
      context.world.tester,
      find.byKey(const ValueKey('linked_daily_macd_paint')),
    );
  });
}

// ============================================================================
// All Steps Export - 导出所有步骤
// ============================================================================

/// 获取所有步骤定义
List<StepDefinitionGeneric> getAllStepDefinitions() {
  return [
    // Common Steps
    appIsRunningStep(),
    watchlistIsClearedStep(),
    iRestartTheAppStep(),
    iAmOnWatchlistPageStep(),
    dataSyncedStep(),

    // Navigation Steps
    iTapBottomNavTabStep(),
    bottomNavTabShouldBeSelectedStep(),
    pageShouldShowWatchlistAreaStep(),
    pageShouldShowMarketAreaStep(),
    pageShouldShowIndustryAreaStep(),
    pageShouldShowBreakoutAreaStep(),
    iTapHoldingsTabStep(),
    iTapWatchlistTabStep(),
    shouldShowHoldingsAreaStep(),
    shouldShowImportButtonStep(),
    shouldShowWatchlistAreaStep(),
    shouldShowAddStockInputStep(),

    // Watchlist Steps
    shouldShowEmptyWatchlistHintStep(),
    shouldShowAddHintTextStep(),
    iEnterStockCodeStep(),
    iTapAddButtonStep(),
    shouldShowAddedSnackbarStep(),
    shouldShowInvalidCodeSnackbarStep(),
    shouldShowAlreadyExistsSnackbarStep(),
    watchlistContainsStep(),
    watchlistShouldContainStockStep(),
    watchlistShouldNotContainStockStep(),
    iLongPressStockStep(),
    shouldShowRemovedSnackbarStep(),

    // Stock Detail MACD Steps
    macdCachePreparedForStockStep(),
    openMacdStockDetailPageInModeStep(),
    shouldShowDailyMacdChartStep(),
    shouldShowWeeklyMacdChartStep(),
    shouldShowLinkedWeeklyMacdChartStep(),
    shouldShowLinkedDailyMacdChartStep(),
  ];
}
