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
import 'package:stock_rtwatcher/screens/industry_ema_breadth_settings_screen.dart';
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

class _FakeMarketDataProvider extends MarketDataProvider {
  _FakeMarketDataProvider({required List<StockMonitorData> data})
    : _data = data,
      super(
        pool: TdxPool(poolSize: 1),
        stockService: StockService(TdxPool(poolSize: 1)),
        industryService: IndustryService(),
      );

  final List<StockMonitorData> _data;

  @override
  List<StockMonitorData> get allData => _data;

  @override
  Future<void> refresh({
    bool silent = false,
    bool forceMinuteRefetch = false,
    bool forceDailyRefetch = false,
  }) async {}
}

class _FakeIndustryTrendService extends IndustryTrendService {
  @override
  IndustryTrendData? getTrend(String industry) {
    return IndustryTrendData(industry: industry, points: const []);
  }

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
  _FakeIndustryBuildUpService(this._historyByIndustry)
    : super(repository: _DummyRepository(), industryService: IndustryService());

  final Map<String, List<IndustryBuildupDailyRecord>> _historyByIndustry;

  @override
  bool hasIndustryHistory(String industry) => true;

  @override
  bool isIndustryHistoryLoading(String industry) => false;

  @override
  List<IndustryBuildupDailyRecord> getIndustryHistory(String industry) {
    return List.unmodifiable(_historyByIndustry[industry] ?? const []);
  }

  @override
  Future<void> loadIndustryHistory(
    String industry, {
    bool force = false,
  }) async {}
}

class _FakeIndustryEmaBreadthConfigStore extends IndustryEmaBreadthConfigStore {
  _FakeIndustryEmaBreadthConfigStore(this._config);

  IndustryEmaBreadthConfig _config;

  @override
  Future<IndustryEmaBreadthConfig> load({
    IndustryEmaBreadthConfig? defaults,
  }) async {
    return _config;
  }

  @override
  Future<void> save(IndustryEmaBreadthConfig config) async {
    _config = config;
  }
}

class _FlowTrackingIndustryEmaBreadthService extends IndustryEmaBreadthService {
  _FlowTrackingIndustryEmaBreadthService()
    : super(
        industryService: IndustryService(),
        dailyCacheStore: DailyKlineCacheStore(),
        emaCacheStore: EmaCacheStore(),
      );

  int recomputeCount = 0;
  int cachedReadCount = 0;
  bool failOnUnexpectedRecompute = false;
  final Map<String, IndustryEmaBreadthSeries> _cache =
      <String, IndustryEmaBreadthSeries>{};

  @override
  Future<Map<String, IndustryEmaBreadthSeries>> recomputeAllIndustries({
    required DateTime startDate,
    required DateTime endDate,
    void Function(int current, int total, String stage)? onProgress,
  }) async {
    if (failOnUnexpectedRecompute) {
      throw StateError('detail page must not trigger recomputeAllIndustries');
    }
    onProgress?.call(0, 1, '准备重算行业EMA广度...');
    recomputeCount++;
    _cache['半导体'] = IndustryEmaBreadthSeries(
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
    );
    onProgress?.call(1, 1, '重算完成');
    return _cache;
  }

  @override
  Future<IndustryEmaBreadthSeries?> getCachedSeries(String industry) async {
    cachedReadCount++;
    return _cache[industry];
  }
}

IndustryBuildupDailyRecord _record(DateTime date) {
  return IndustryBuildupDailyRecord(
    date: date,
    industry: '半导体',
    zRel: 1.4,
    breadth: 0.42,
    q: 0.72,
    rawScore: 0.56,
    scoreEma: 0.53,
    xI: 0.1,
    xM: 0.05,
    passedCount: 10,
    memberCount: 20,
    rank: 1,
    updatedAt: DateTime(2026, 2, 6, 15),
  );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required _FakeMarketDataProvider marketProvider,
  required _FlowTrackingIndustryEmaBreadthService breadthService,
  required _FakeIndustryEmaBreadthConfigStore configStore,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MarketDataProvider>.value(value: marketProvider),
      ],
      child: MaterialApp(
        home: IndustryEmaBreadthSettingsScreen(
          configStoreForTest: configStore,
          serviceForTest: breadthService,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required DataRepository repository,
  required _FakeMarketDataProvider marketProvider,
  required IndustryTrendService trendService,
  required IndustryBuildUpService buildUpService,
  required _FakeIndustryEmaBreadthConfigStore configStore,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DataRepository>.value(value: repository),
        ChangeNotifierProvider<MarketDataProvider>.value(value: marketProvider),
        ChangeNotifierProvider<IndustryTrendService>.value(value: trendService),
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
}

void main() {
  testWidgets(
    'manual recompute persists breadth cache and detail reads it without recompute',
    (tester) async {
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
      final breadthService = _FlowTrackingIndustryEmaBreadthService();
      marketProvider.setIndustryEmaBreadthService(breadthService);
      final buildUpService = _FakeIndustryBuildUpService({
        '半导体': <IndustryBuildupDailyRecord>[_record(DateTime(2026, 2, 6))],
      });
      final trendService = _FakeIndustryTrendService();
      final configStore = _FakeIndustryEmaBreadthConfigStore(
        const IndustryEmaBreadthConfig(upperThreshold: 68, lowerThreshold: 32),
      );

      await _pumpSettings(
        tester,
        marketProvider: marketProvider,
        breadthService: breadthService,
        configStore: configStore,
      );

      await tester.tap(find.byKey(const ValueKey('industry_ema_recompute')));
      await tester.pumpAndSettle();

      expect(breadthService.recomputeCount, 1);
      expect(breadthService.getCachedSeries('半导体'), completion(isNotNull));

      breadthService.failOnUnexpectedRecompute = true;

      await _pumpDetail(
        tester,
        repository: repository,
        marketProvider: marketProvider,
        trendService: trendService,
        buildUpService: buildUpService,
        configStore: configStore,
      );

      await tester.drag(find.byType(NestedScrollView), const Offset(0, -320));
      await tester.pumpAndSettle();

      expect(breadthService.recomputeCount, 1);
      expect(breadthService.cachedReadCount, greaterThanOrEqualTo(2));
      expect(
        find.byKey(const ValueKey('industry_detail_ema_breadth_card')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Above 13 / Valid 21 / Missing 3'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('industry_ema_breadth_custom_paint')),
        findsOneWidget,
      );
    },
  );
}
