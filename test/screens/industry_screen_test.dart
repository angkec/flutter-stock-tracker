import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/industry_screen.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _FakeDataRepository implements DataRepository {
  final StreamController<DataStatus> _statusController =
      StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _updatedController =
      StreamController<DataUpdatedEvent>.broadcast();

  int dataVersion;

  _FakeDataRepository({this.dataVersion = 42});

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _updatedController.stream;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final bars = [
      KLine(
        datetime: DateTime.now().subtract(const Duration(minutes: 1)),
        open: 10,
        close: 11,
        high: 11,
        low: 10,
        volume: 100,
        amount: 1000,
      ),
      KLine(
        datetime: DateTime.now(),
        open: 11,
        close: 10,
        high: 11,
        low: 10,
        volume: 80,
        amount: 800,
      ),
    ];
    return {for (final code in stockCodes) code: bars};
  }

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    return {for (final code in stockCodes) code: const Fresh()};
  }

  @override
  Future<Map<String, Quote>> getQuotes({required List<String> stockCodes}) {
    throw UnimplementedError();
  }

  @override
  Future<int> getCurrentVersion() async => dataVersion;

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
    final now = DateTime.now();
    return [
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
    ];
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _updatedController.close();
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
  Future<void> refresh({bool silent = false}) async {}
}

class _FakeIndustryTrendService extends IndustryTrendService {
  int recalculateCalls = 0;
  int? lastDataVersion;
  List<StockMonitorData>? lastStocks;

  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {
    recalculateCalls += 1;
    lastDataVersion = dataVersion;
    lastStocks = List<StockMonitorData>.from(stocks);
  }

  @override
  Map<String, DailyRatioPoint> calculateTodayTrend(
    List<StockMonitorData> stocks,
  ) {
    return <String, DailyRatioPoint>{};
  }

  @override
  int checkMissingDays({List<DateTime>? expectedTradingDays}) {
    return 0;
  }
}

class _FakeIndustryRankService extends IndustryRankService {
  int recalculateCalls = 0;
  int? lastDataVersion;
  List<StockMonitorData>? lastStocks;

  @override
  void calculateTodayRanks(List<StockMonitorData> stocks) {
    // no-op to avoid rebuild loop in widget tests.
  }

  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {
    recalculateCalls += 1;
    lastDataVersion = dataVersion;
    lastStocks = List<StockMonitorData>.from(stocks);
  }
}

void main() {
  testWidgets('行业页包含雷达排名子tab且在该tab隐藏重算按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final repository = _FakeDataRepository(dataVersion: 99);
    final marketProvider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 1.0,
          industry: '银行',
          upVolume: 120,
          downVolume: 100,
        ),
      ],
    );
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final historicalKlineService = HistoricalKlineService(
      repository: repository,
    );
    final buildupService = IndustryBuildUpService(
      repository: repository,
      industryService: IndustryService(),
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
          ChangeNotifierProvider<IndustryRankService>.value(value: rankService),
          ChangeNotifierProvider<IndustryBuildUpService>.value(
            value: buildupService,
          ),
          ChangeNotifierProvider<HistoricalKlineService>.value(
            value: historicalKlineService,
          ),
        ],
        child: const MaterialApp(home: IndustryScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('行业统计'), findsOneWidget);
    expect(find.text('排名趋势'), findsOneWidget);
    expect(find.text('建仓雷达'), findsOneWidget);
    expect(find.text('雷达排名'), findsOneWidget);

    await tester.tap(find.text('雷达排名'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.auto_graph), findsNothing);

    buildupService.dispose();
    marketProvider.dispose();
    historicalKlineService.dispose();
    await repository.dispose();
  });

  testWidgets('顶部显示重算按钮并触发行业趋势与排名重算', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final repository = _FakeDataRepository(dataVersion: 99);
    final marketProvider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 1.0,
          industry: '银行',
          upVolume: 120,
          downVolume: 100,
        ),
      ],
    );
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final historicalKlineService = HistoricalKlineService(
      repository: repository,
    );
    final buildupService = IndustryBuildUpService(
      repository: repository,
      industryService: IndustryService(),
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
          ChangeNotifierProvider<IndustryRankService>.value(value: rankService),
          ChangeNotifierProvider<IndustryBuildUpService>.value(
            value: buildupService,
          ),
          ChangeNotifierProvider<HistoricalKlineService>.value(
            value: historicalKlineService,
          ),
        ],
        child: const MaterialApp(home: IndustryScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.auto_graph), findsOneWidget);

    await tester.tap(find.byIcon(Icons.auto_graph));
    await tester.pumpAndSettle();

    expect(trendService.recalculateCalls, 1);
    expect(rankService.recalculateCalls, 1);
    expect(trendService.lastDataVersion, 99);
    expect(rankService.lastDataVersion, 99);
    expect(find.text('行业数据与排名已重算'), findsOneWidget);

    buildupService.dispose();
    marketProvider.dispose();
    historicalKlineService.dispose();
    await repository.dispose();
  });
}
