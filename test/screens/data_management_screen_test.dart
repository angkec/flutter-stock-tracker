import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/data_management_screen.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _FakeDataRepository implements DataRepository {
  final StreamController<DataStatus> _statusController =
      StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _updatedController =
      StreamController<DataUpdatedEvent>.broadcast();

  List<DateTime> tradingDates = <DateTime>[];
  Map<String, List<KLine>> klinesByStock = <String, List<KLine>>{};
  FetchResult fetchMissingDataResult = FetchResult(
    totalStocks: 0,
    successCount: 0,
    failureCount: 0,
    errors: const {},
    totalRecords: 0,
    duration: Duration.zero,
  );
  Map<String, MissingDatesResult> missingMinuteDatesByStock = const {};
  int findMissingMinuteDatesBatchCallCount = 0;
  List<DataFetching> statusEventsDuringFetch = const <DataFetching>[];
  Duration fetchMissingDataDelay = Duration.zero;

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
    return {
      for (final code in stockCodes)
        code: (klinesByStock[code] ?? <KLine>[]).where((bar) {
          return dateRange.contains(bar.datetime);
        }).toList(),
    };
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
  Future<int> getCurrentVersion() async => 1;

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    onProgress?.call(stockCodes.length, stockCodes.length);

    for (final status in statusEventsDuringFetch) {
      _statusController.add(status);
      await Future<void>.delayed(Duration.zero);
    }

    if (fetchMissingDataDelay > Duration.zero) {
      await Future<void>.delayed(fetchMissingDataDelay);
    }

    return fetchMissingDataResult;
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
  }) async {
    findMissingMinuteDatesBatchCallCount++;
    onProgress?.call(stockCodes.length, stockCodes.length);
    return {
      for (final code in stockCodes)
        code:
            missingMinuteDatesByStock[code] ??
            const MissingDatesResult(
              missingDates: <DateTime>[],
              incompleteDates: <DateTime>[],
              completeDates: <DateTime>[],
            ),
    };
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
    return tradingDates;
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) {
    return Future.value(0);
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _updatedController.close();
  }
}

class _FakeIndustryTrendService extends IndustryTrendService {
  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {}
}

class _FakeIndustryRankService extends IndustryRankService {
  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {}
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

List<KLine> _buildBarsForDate(DateTime day, int count) {
  final start = DateTime(day.year, day.month, day.day, 9, 30);
  return List.generate(count, (index) {
    final dt = start.add(Duration(minutes: index));
    return KLine(
      datetime: dt,
      open: 10,
      close: 10.1,
      high: 10.2,
      low: 9.9,
      volume: 1000,
      amount: 10000,
    );
  });
}

List<StockMonitorData> _buildStocks(int count) {
  return List.generate(count, (index) {
    final code = (600000 + index).toString();
    return StockMonitorData(
      stock: Stock(code: code, name: '股票$code', market: 1),
      ratio: 1.0,
      changePercent: 0.0,
    );
  });
}

void main() {
  const toggleChannelName =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  Future<void> pumpDataManagement(
    WidgetTester tester, {
    required DataRepository repository,
    required MarketDataProvider marketDataProvider,
    required HistoricalKlineService klineService,
    required IndustryTrendService trendService,
    required IndustryRankService rankService,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataRepository>.value(value: repository),
          ChangeNotifierProvider<MarketDataProvider>.value(
            value: marketDataProvider,
          ),
          ChangeNotifierProvider<HistoricalKlineService>.value(
            value: klineService,
          ),
          ChangeNotifierProvider<IndustryTrendService>.value(
            value: trendService,
          ),
          ChangeNotifierProvider<IndustryRankService>.value(value: rankService),
        ],
        child: const MaterialApp(home: DataManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(toggleChannelName, (ByteData? _) async {
          return const StandardMessageCodec().encodeMessage(<Object?>[]);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(toggleChannelName, null);
  });

  testWidgets('交易日覆盖率不足时显示最后交易日完整而非样本不足', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    final today = DateTime.now();
    final lastTradingDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    repository.tradingDates = <DateTime>[]; // 强制走覆盖率不足分支
    repository.klinesByStock = {
      '600000': _buildBarsForDate(lastTradingDay, 220),
    };

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    expect(find.textContaining('最后交易日'), findsOneWidget);
    expect(find.textContaining('数据完整'), findsOneWidget);
    expect(find.textContaining('交易日样本不足'), findsNothing);
    expect(find.text('拉取缺失'), findsNothing);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('交易日覆盖率不足且最后交易日不完整时仍提示拉取缺失', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    final today = DateTime.now();
    final lastTradingDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    repository.tradingDates = <DateTime>[];
    repository.klinesByStock = {
      '600000': _buildBarsForDate(lastTradingDay, 120),
    };

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    expect(find.textContaining('最后交易日'), findsOneWidget);
    expect(find.textContaining('不完整'), findsOneWidget);
    expect(find.text('拉取缺失'), findsOneWidget);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('交易日覆盖率不足时抽样需覆盖全量避免误报完整', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(data: _buildStocks(40));

    final today = DateTime.now();
    final lastTradingDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));

    repository.tradingDates = <DateTime>[];
    repository.klinesByStock = {
      for (var i = 0; i < 20; i++)
        (600000 + i).toString(): _buildBarsForDate(lastTradingDay, 220),
    };

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    expect(find.textContaining('交易日基线不足'), findsOneWidget);
    expect(find.textContaining('数据完整'), findsNothing);
    expect(find.textContaining('缺失20只'), findsOneWidget);
    expect(find.text('拉取缺失'), findsOneWidget);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('交易日基线不足且无最近交易日时拉取缺失不应直接失败', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    repository.tradingDates = <DateTime>[];
    repository.klinesByStock = <String, List<KLine>>{};
    repository.fetchMissingDataResult = FetchResult(
      totalStocks: 1,
      successCount: 1,
      failureCount: 0,
      errors: const {},
      totalRecords: 0,
      duration: const Duration(milliseconds: 1),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    expect(find.text('拉取缺失'), findsOneWidget);

    await tester.tap(find.text('拉取缺失'));
    await tester.pumpAndSettle();

    expect(repository.findMissingMinuteDatesBatchCallCount, 1);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('复检通过后成功提示不应包含交易日暂不可验证警告', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    repository.tradingDates = <DateTime>[];
    repository.klinesByStock = <String, List<KLine>>{};
    repository.fetchMissingDataResult = FetchResult(
      totalStocks: 1,
      successCount: 1,
      failureCount: 0,
      errors: const {},
      totalRecords: 0,
      duration: const Duration(milliseconds: 1),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await tester.tap(find.text('拉取缺失'));
    await tester.pumpAndSettle();

    expect(repository.findMissingMinuteDatesBatchCallCount, 1);
    expect(find.textContaining('最近分钟K交易日暂不可验证'), findsNothing);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('拉取缺失时应显示写入阶段进度', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    repository.fetchMissingDataResult = FetchResult(
      totalStocks: 1,
      successCount: 1,
      failureCount: 0,
      errors: const {},
      totalRecords: 12,
      duration: const Duration(milliseconds: 200),
    );
    repository.statusEventsDuringFetch = const <DataFetching>[
      DataFetching(current: 1, total: 3, currentStock: '600000'),
      DataFetching(current: 1, total: 2, currentStock: '__WRITE__'),
    ];
    repository.fetchMissingDataDelay = const Duration(milliseconds: 200);

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await tester.tap(find.text('拉取缺失'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('2/4 写入K线数据'), findsOneWidget);
    expect(find.textContaining('1 / 2'), findsOneWidget);

    await tester.pumpAndSettle();

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });
}
