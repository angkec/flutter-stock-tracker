import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_config_store.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/industry_detail_screen.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_ema_breadth_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _DummyRepository implements DataRepository {
  final _statusController = StreamController<DataStatus>.broadcast();
  final _updatedController = StreamController<DataUpdatedEvent>.broadcast();

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _updatedController.stream;

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async => {};

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) async {}

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) async => 0;

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _updatedController.close();
  }

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async => FetchResult(
    totalStocks: 0,
    successCount: 0,
    failureCount: 0,
    errors: const {},
    totalRecords: 0,
    duration: Duration.zero,
  );

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) async => const MissingDatesResult(
    missingDates: [],
    incompleteDates: [],
    completeDates: [],
  );

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) async => {};

  @override
  Future<int> getCurrentVersion() async => 1;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async => {};

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async => {};

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async => [];

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async => FetchResult(
    totalStocks: 0,
    successCount: 0,
    failureCount: 0,
    errors: const {},
    totalRecords: 0,
    duration: Duration.zero,
  );
}

class _FakeRatioSortRepository extends _DummyRepository {
  final Map<String, List<KLine>> _barsByCode;

  _FakeRatioSortRepository(this._barsByCode);

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final result = <String, List<KLine>>{};
    for (final code in stockCodes) {
      final bars = _barsByCode[code] ?? const <KLine>[];
      result[code] = bars
          .where((bar) => dateRange.contains(bar.datetime))
          .toList();
    }
    return result;
  }
}

class _FakeMarketDataProvider extends MarketDataProvider {
  final List<StockMonitorData> _testData;

  _FakeMarketDataProvider({required List<StockMonitorData> data})
    : _testData = data,
      super(
        pool: TdxPool(poolSize: 1),
        stockService: StockService(TdxPool(poolSize: 1)),
        industryService: IndustryService(),
      );

  @override
  List<StockMonitorData> get allData => _testData;

  @override
  Future<void> refresh({
    bool silent = false,
    bool forceMinuteRefetch = false,
    bool forceDailyRefetch = false,
  }) async {}
}

class _FakeTrendService extends IndustryTrendService {
  @override
  IndustryTrendData? getTrend(String industry) =>
      IndustryTrendData(industry: industry, points: const []);

  @override
  Map<String, DailyRatioPoint> calculateTodayTrend(
    List<StockMonitorData> stocks,
  ) {
    return {
      '半导体': DailyRatioPoint(
        date: DateTime(2026, 2, 6),
        ratioAbovePercent: 50,
        totalStocks: 2,
        ratioAboveCount: 1,
      ),
    };
  }
}

class _FakeIndustryBuildUpService extends IndustryBuildUpService {
  final Map<String, List<IndustryBuildupDailyRecord>> _historyByIndustry;
  bool _loaded = false;
  bool _loading = false;
  int loadCallCount = 0;

  _FakeIndustryBuildUpService({
    required Map<String, List<IndustryBuildupDailyRecord>> historyByIndustry,
  }) : _historyByIndustry = historyByIndustry,
       super(
         repository: _DummyRepository(),
         industryService: IndustryService(),
       );

  @override
  bool hasIndustryHistory(String industry) => _loaded;

  @override
  bool isIndustryHistoryLoading(String industry) => _loading;

  @override
  List<IndustryBuildupDailyRecord> getIndustryHistory(String industry) {
    if (!_loaded) {
      return const [];
    }
    return List.unmodifiable(_historyByIndustry[industry] ?? const []);
  }

  @override
  Future<void> loadIndustryHistory(
    String industry, {
    bool force = false,
  }) async {
    _loading = true;
    loadCallCount += 1;
    notifyListeners();

    _loaded = true;
    _loading = false;
    notifyListeners();
  }
}

class _FakeIndustryEmaBreadthService extends IndustryEmaBreadthService {
  _FakeIndustryEmaBreadthService(this._seriesByIndustry)
    : super(
        industryService: IndustryService(),
        dailyCacheStore: DailyKlineCacheStore(),
        emaCacheStore: EmaCacheStore(),
      );

  final Map<String, IndustryEmaBreadthSeries> _seriesByIndustry;

  @override
  Future<IndustryEmaBreadthSeries?> getCachedSeries(String industry) async {
    return _seriesByIndustry[industry];
  }
}

class _FakeIndustryEmaBreadthConfigStore extends IndustryEmaBreadthConfigStore {
  _FakeIndustryEmaBreadthConfigStore(this._config);

  final IndustryEmaBreadthConfig _config;

  @override
  Future<IndustryEmaBreadthConfig> load({
    IndustryEmaBreadthConfig? defaults,
  }) async {
    return _config;
  }
}

IndustryBuildupDailyRecord _record(
  DateTime date, {
  required int rank,
  double rawScore = 0,
  double scoreEma = 0,
  int rankChange = 0,
  String rankArrow = '→',
}) {
  return IndustryBuildupDailyRecord(
    date: date,
    industry: '半导体',
    zRel: 1.0 + rank,
    breadth: 0.4,
    q: 0.8,
    rawScore: rawScore,
    scoreEma: scoreEma,
    xI: 0.1,
    xM: 0.05,
    passedCount: 10,
    memberCount: 20,
    rank: rank,
    rankChange: rankChange,
    rankArrow: rankArrow,
    updatedAt: DateTime(2026, 2, 6, 15),
  );
}

void main() {
  testWidgets('行业详情页显示建仓雷达历史并触发加载', (tester) async {
    final repository = _DummyRepository();
    final marketProvider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600001', name: '测试A', market: 1),
          ratio: 1.2,
          changePercent: 2.5,
          industry: '半导体',
        ),
        StockMonitorData(
          stock: Stock(code: '600002', name: '测试B', market: 1),
          ratio: 0.8,
          changePercent: -1.0,
          industry: '半导体',
        ),
      ],
    );
    final trendService = _FakeTrendService();
    final buildUpService = _FakeIndustryBuildUpService(
      historyByIndustry: {
        '半导体': [
          _record(
            DateTime(2026, 2, 6),
            rank: 1,
            rawScore: 0.62,
            scoreEma: 0.55,
            rankChange: 1,
            rankArrow: '↑',
          ),
          _record(
            DateTime(2026, 2, 5),
            rank: 2,
            rawScore: 0.48,
            scoreEma: 0.46,
          ),
          _record(
            DateTime(2026, 2, 4),
            rank: 3,
            rawScore: 0.32,
            scoreEma: 0.34,
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataRepository>.value(value: repository),
          ChangeNotifierProvider<MarketDataProvider>.value(
            value: marketProvider,
          ),
          ChangeNotifierProvider<IndustryTrendService>.value(
            value: trendService,
          ),
          ChangeNotifierProvider<IndustryBuildUpService>.value(
            value: buildUpService,
          ),
        ],
        child: const MaterialApp(home: IndustryDetailScreen(industry: '半导体')),
      ),
    );

    await tester.pumpAndSettle();

    expect(buildUpService.loadCallCount, 1);
    expect(find.text('建仓雷达历史'), findsOneWidget);
    expect(find.text('行业配置期'), findsWidgets);
    expect(find.textContaining('当日详情 2026-02-06'), findsOneWidget);
    expect(find.textContaining('雷达排名趋势'), findsOneWidget);
    expect(find.textContaining('当前排名 #1'), findsOneWidget);
  });

  testWidgets('雷达排名趋势图支持手指选择日期并刷新当日详情', (tester) async {
    final repository = _DummyRepository();
    final marketProvider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600001', name: '测试A', market: 1),
          ratio: 1.2,
          changePercent: 2.5,
          industry: '半导体',
        ),
      ],
    );
    final trendService = _FakeTrendService();
    final buildUpService = _FakeIndustryBuildUpService(
      historyByIndustry: {
        '半导体': [
          _record(
            DateTime(2026, 2, 6),
            rank: 1,
            rawScore: 0.62,
            scoreEma: 0.55,
            rankChange: 1,
            rankArrow: '↑',
          ),
          _record(
            DateTime(2026, 2, 5),
            rank: 2,
            rawScore: 0.48,
            scoreEma: 0.46,
          ),
          _record(
            DateTime(2026, 2, 4),
            rank: 3,
            rawScore: 0.32,
            scoreEma: 0.34,
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataRepository>.value(value: repository),
          ChangeNotifierProvider<MarketDataProvider>.value(
            value: marketProvider,
          ),
          ChangeNotifierProvider<IndustryTrendService>.value(
            value: trendService,
          ),
          ChangeNotifierProvider<IndustryBuildUpService>.value(
            value: buildUpService,
          ),
        ],
        child: const MaterialApp(home: IndustryDetailScreen(industry: '半导体')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('当日详情 2026-02-06'), findsOneWidget);

    final chartFinder = find.byKey(
      const ValueKey('industry_detail_radar_rank_chart'),
    );
    expect(chartFinder, findsOneWidget);
    final rect = tester.getRect(chartFinder);
    await tester.dragFrom(
      Offset(rect.right - 4, rect.center.dy),
      Offset(-rect.width + 8, 0),
    );
    await tester.pump();

    expect(find.textContaining('当日详情 2026-02-04'), findsOneWidget);
  });

  testWidgets('成分股列表可按指定日期量比排序', (tester) async {
    final targetDate = DateTime(2026, 2, 5);
    final repository = _FakeRatioSortRepository({
      '600001': _buildBarsForRatio(targetDate, ratio: 0.6),
      '600002': _buildBarsForRatio(targetDate, ratio: 2.0),
    });
    final marketProvider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600001', name: '测试A', market: 1),
          ratio: 1.8,
          changePercent: 2.5,
          industry: '半导体',
        ),
        StockMonitorData(
          stock: Stock(code: '600002', name: '测试B', market: 1),
          ratio: 1.2,
          changePercent: -1.0,
          industry: '半导体',
        ),
      ],
    );
    final trendService = _FakeTrendService();
    final buildUpService = _FakeIndustryBuildUpService(
      historyByIndustry: {
        '半导体': [
          _record(DateTime(2026, 2, 6), rank: 1),
          _record(DateTime(2026, 2, 5), rank: 2),
        ],
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataRepository>.value(value: repository),
          ChangeNotifierProvider<MarketDataProvider>.value(
            value: marketProvider,
          ),
          ChangeNotifierProvider<IndustryTrendService>.value(
            value: trendService,
          ),
          ChangeNotifierProvider<IndustryBuildUpService>.value(
            value: buildUpService,
          ),
        ],
        child: const MaterialApp(home: IndustryDetailScreen(industry: '半导体')),
      ),
    );

    await tester.pumpAndSettle();

    // Scroll more since header now includes EMA breadth card (~230px taller)
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -550));
    await tester.pumpAndSettle();

    expect(
      _topYOfText(tester, '600001'),
      lessThan(_topYOfText(tester, '600002')),
    );

    final sortMenu = find.byKey(
      const ValueKey('industry_detail_ratio_sort_day_menu'),
    );
    await tester.ensureVisible(sortMenu);
    tester.state<PopupMenuButtonState<DateTime?>>(sortMenu).showButtonMenu();
    await tester.pumpAndSettle();
    final dayOption = find.text('02-05').last;
    expect(dayOption, findsOneWidget);
    await tester.tap(dayOption);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(find.textContaining('排序: 02-05'), findsOneWidget);
    expect(
      _topYOfText(tester, '600002'),
      lessThan(_topYOfText(tester, '600001')),
    );
    expect(_topYOfText(tester, '2.00'), lessThan(_topYOfText(tester, '0.60')));
  });

  testWidgets('行业详情页展示 EMA 广度缓存图和阈值线', (tester) async {
    final repository = _DummyRepository();
    final marketProvider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600001', name: '测试A', market: 1),
          ratio: 1.2,
          changePercent: 2.5,
          industry: '半导体',
        ),
      ],
    );
    final breadthService = _FakeIndustryEmaBreadthService({
      '半导体': IndustryEmaBreadthSeries(
        industry: '半导体',
        points: [
          IndustryEmaBreadthPoint(
            date: DateTime(2026, 2, 5),
            percent: 58,
            aboveCount: 12,
            validCount: 20,
            missingCount: 4,
          ),
          IndustryEmaBreadthPoint(
            date: DateTime(2026, 2, 6),
            percent: 64,
            aboveCount: 13,
            validCount: 21,
            missingCount: 3,
          ),
        ],
      ),
    });
    marketProvider.setIndustryEmaBreadthService(breadthService);
    final trendService = _FakeTrendService();
    final buildUpService = _FakeIndustryBuildUpService(
      historyByIndustry: {
        '半导体': [_record(DateTime(2026, 2, 6), rank: 1)],
      },
    );
    final configStore = _FakeIndustryEmaBreadthConfigStore(
      const IndustryEmaBreadthConfig(upperThreshold: 68, lowerThreshold: 32),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataRepository>.value(value: repository),
          ChangeNotifierProvider<MarketDataProvider>.value(
            value: marketProvider,
          ),
          ChangeNotifierProvider<IndustryTrendService>.value(
            value: trendService,
          ),
          ChangeNotifierProvider<IndustryBuildUpService>.value(
            value: buildUpService,
          ),
        ],
        child: MaterialApp(
          home: IndustryDetailScreen(
            industry: '半导体',
            emaBreadthConfigStoreForTest: configStore,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // EMA breadth card is now in the sliver header, should be visible without scrolling
    expect(
      find.byKey(const ValueKey('industry_detail_ema_breadth_card')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Above 13 / Valid 21 / Missing 3'),
      findsOneWidget,
    );
    expect(find.text('Upper 68%'), findsOneWidget);
    expect(find.text('Lower 32%'), findsOneWidget);
    // Selection hint should be visible (from EMA breadth chart)
    expect(find.text('手指滑动或点击图表可选择日期'), findsNWidgets(2));
  });

  testWidgets('EMA 广度图支持选择日期并显示选中详情', (tester) async {
    final repository = _DummyRepository();
    final marketProvider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600001', name: '测试A', market: 1),
          ratio: 1.2,
          changePercent: 2.5,
          industry: '半导体',
        ),
      ],
    );
    final breadthService = _FakeIndustryEmaBreadthService({
      '半导体': IndustryEmaBreadthSeries(
        industry: '半导体',
        points: [
          IndustryEmaBreadthPoint(
            date: DateTime(2026, 2, 5),
            percent: 58,
            aboveCount: 12,
            validCount: 20,
            missingCount: 4,
          ),
          IndustryEmaBreadthPoint(
            date: DateTime(2026, 2, 6),
            percent: 64,
            aboveCount: 13,
            validCount: 21,
            missingCount: 3,
          ),
          IndustryEmaBreadthPoint(
            date: DateTime(2026, 2, 7),
            percent: 72,
            aboveCount: 15,
            validCount: 22,
            missingCount: 2,
          ),
        ],
      ),
    });
    marketProvider.setIndustryEmaBreadthService(breadthService);
    final trendService = _FakeTrendService();
    final buildUpService = _FakeIndustryBuildUpService(
      historyByIndustry: {
        '半导体': [_record(DateTime(2026, 2, 7), rank: 1)],
      },
    );
    final configStore = _FakeIndustryEmaBreadthConfigStore(
      IndustryEmaBreadthConfig.defaultConfig,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataRepository>.value(value: repository),
          ChangeNotifierProvider<MarketDataProvider>.value(
            value: marketProvider,
          ),
          ChangeNotifierProvider<IndustryTrendService>.value(
            value: trendService,
          ),
          ChangeNotifierProvider<IndustryBuildUpService>.value(
            value: buildUpService,
          ),
        ],
        child: MaterialApp(
          home: IndustryDetailScreen(
            industry: '半导体',
            emaBreadthConfigStoreForTest: configStore,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Find the chart and tap to select
    final chartFinder = find.byKey(
      const ValueKey('industry_ema_breadth_custom_paint'),
    );
    expect(chartFinder, findsOneWidget);

    final chartRect = tester.getRect(chartFinder);
    // Tap on left side to select first point
    await tester.tapAt(Offset(chartRect.left + 20, chartRect.center.dy));
    await tester.pump();

    // Should show selected detail
    expect(
      find.byKey(const ValueKey('industry_ema_breadth_selected_detail')),
      findsOneWidget,
    );
    expect(find.textContaining('选中 2026-02-05'), findsOneWidget);
  });
}

List<KLine> _buildBarsForRatio(DateTime day, {required double ratio}) {
  final bars = <KLine>[];
  const downVolumePerBar = 1000.0;
  final upVolumePerBar = downVolumePerBar * ratio;
  var price = 10.0;

  for (var i = 0; i < 5; i++) {
    final open = price;
    final close = open * 0.995;
    bars.add(
      KLine(
        datetime: DateTime(
          day.year,
          day.month,
          day.day,
          9,
          30,
        ).add(Duration(minutes: i)),
        open: open,
        close: close,
        high: open,
        low: close,
        volume: downVolumePerBar,
        amount: downVolumePerBar * open,
      ),
    );
    price = close;
  }

  for (var i = 5; i < 10; i++) {
    final open = price;
    final close = open * 1.005;
    bars.add(
      KLine(
        datetime: DateTime(
          day.year,
          day.month,
          day.day,
          9,
          30,
        ).add(Duration(minutes: i)),
        open: open,
        close: close,
        high: close,
        low: open,
        volume: upVolumePerBar,
        amount: upVolumePerBar * open,
      ),
    );
    price = close;
  }
  return bars;
}

double _topYOfText(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  return tester.getTopLeft(finder).dy;
}
