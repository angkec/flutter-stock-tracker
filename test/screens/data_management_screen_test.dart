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
import 'package:stock_rtwatcher/audit/services/audit_export_service.dart';
import 'package:stock_rtwatcher/audit/services/audit_operation_runner.dart';
import 'package:stock_rtwatcher/audit/services/audit_service.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/data_management_screen.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/power_system_indicator_service.dart';
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
  Map<String, MissingDatesResult>? missingMinuteDatesAfterFetch;
  int findMissingMinuteDatesBatchCallCount = 0;
  int fetchMissingDataCallCount = 0;
  int refetchDataCallCount = 0;
  final List<KLineDataType> fetchMissingDataTypes = <KLineDataType>[];
  final List<KLineDataType> refetchDataTypes = <KLineDataType>[];
  List<DataFetching> statusEventsDuringFetch = const <DataFetching>[];
  List<DataUpdatedEvent> dataUpdatedEventsDuringFetch =
      const <DataUpdatedEvent>[];
  Duration fetchMissingDataDelay = Duration.zero;
  Object? fetchMissingDataError;

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
    fetchMissingDataCallCount++;
    fetchMissingDataTypes.add(dataType);
    onProgress?.call(stockCodes.length, stockCodes.length);

    for (final status in statusEventsDuringFetch) {
      _statusController.add(status);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (final event in dataUpdatedEventsDuringFetch) {
      _updatedController.add(event);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (fetchMissingDataDelay > Duration.zero) {
      await Future<void>.delayed(fetchMissingDataDelay);
    }
    if (fetchMissingDataError != null) {
      throw fetchMissingDataError!;
    }

    if (missingMinuteDatesAfterFetch != null) {
      missingMinuteDatesByStock = missingMinuteDatesAfterFetch!;
    }

    return fetchMissingDataResult;
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    refetchDataCallCount++;
    refetchDataTypes.add(dataType);
    onProgress?.call(stockCodes.length, stockCodes.length);
    for (final event in dataUpdatedEventsDuringFetch) {
      _updatedController.add(event);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return fetchMissingDataResult;
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
  int recalculateCallCount = 0;
  int? lastDataVersion;

  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {
    recalculateCallCount++;
    lastDataVersion = dataVersion;
  }
}

class _FakeIndustryRankService extends IndustryRankService {
  int recalculateCallCount = 0;
  int? lastDataVersion;

  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {
    recalculateCallCount++;
    lastDataVersion = dataVersion;
  }
}

class _FakeMarketDataProvider extends MarketDataProvider {
  final List<StockMonitorData> _testData;
  int forceMinuteRefetchCount = 0;
  int forceDailyRefetchCount = 0;
  int incrementalDailySyncCount = 0;
  int forceIndustryRefetchCount = 0;
  List<({String stage, int current, int total})> dailyProgressEvents = const [];
  Duration dailyProgressEventInterval = const Duration(milliseconds: 10);
  Duration dailyRefetchDelay = Duration.zero;

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
  }) async {
    if (forceMinuteRefetch) {
      forceMinuteRefetchCount++;
    }
    if (forceDailyRefetch) {
      forceDailyRefetchCount++;
    }
  }

  @override
  Future<void> forceRefetchDailyBars({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    await syncDailyBarsForceFull(
      onProgress: onProgress,
      indicatorTargetStockCodes: indicatorTargetStockCodes,
    );
  }

  @override
  Future<void> syncDailyBarsIncremental({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    incrementalDailySyncCount++;
    for (final event in dailyProgressEvents) {
      onProgress?.call(event.stage, event.current, event.total);
      await Future<void>.delayed(dailyProgressEventInterval);
    }
    if (dailyRefetchDelay > Duration.zero) {
      await Future<void>.delayed(dailyRefetchDelay);
    }
  }

  @override
  Future<void> syncDailyBarsForceFull({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    forceDailyRefetchCount++;
    for (final event in dailyProgressEvents) {
      onProgress?.call(event.stage, event.current, event.total);
      await Future<void>.delayed(dailyProgressEventInterval);
    }
    if (dailyRefetchDelay > Duration.zero) {
      await Future<void>.delayed(dailyRefetchDelay);
    }
  }

  @override
  Future<void> forceReloadIndustryData() async {
    forceIndustryRefetchCount++;
  }
}

class _FakeMacdIndicatorService extends MacdIndicatorService {
  _FakeMacdIndicatorService({required super.repository});

  int prewarmFromRepositoryCount = 0;
  final List<KLineDataType> prewarmDataTypes = <KLineDataType>[];
  final List<bool> prewarmForceRecomputeValues = <bool>[];
  final List<bool> prewarmIgnoreSnapshotValues = <bool>[];
  final List<List<String>> prewarmStockCodeBatches = <List<String>>[];
  final List<int?> prewarmFetchBatchSizes = <int?>[];
  final List<int?> prewarmPersistConcurrencyValues = <int?>[];
  int prewarmProgressSteps = 1;
  Duration prewarmProgressStepDelay = Duration.zero;

  @override
  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    bool ignoreSnapshot = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmFromRepositoryCount++;
    prewarmDataTypes.add(dataType);
    prewarmForceRecomputeValues.add(forceRecompute);
    prewarmIgnoreSnapshotValues.add(ignoreSnapshot);
    prewarmStockCodeBatches.add(List<String>.from(stockCodes, growable: false));
    prewarmFetchBatchSizes.add(fetchBatchSize);
    prewarmPersistConcurrencyValues.add(maxConcurrentPersistWrites);
    final safeTotal = stockCodes.isEmpty ? 1 : stockCodes.length;
    final safeSteps = prewarmProgressSteps <= 0 ? 1 : prewarmProgressSteps;
    for (var step = 1; step <= safeSteps; step++) {
      final current = ((safeTotal * step) / safeSteps).ceil().clamp(
        1,
        safeTotal,
      );
      onProgress?.call(current, safeTotal);
      if (prewarmProgressStepDelay > Duration.zero) {
        await Future<void>.delayed(prewarmProgressStepDelay);
      }
    }
  }
}

class _FakeAdxIndicatorService extends AdxIndicatorService {
  _FakeAdxIndicatorService({required super.repository});

  int prewarmFromRepositoryCount = 0;
  final List<KLineDataType> prewarmDataTypes = <KLineDataType>[];
  final List<bool> prewarmForceRecomputeValues = <bool>[];
  final List<List<String>> prewarmStockCodeBatches = <List<String>>[];
  final List<int?> prewarmFetchBatchSizes = <int?>[];
  final List<int?> prewarmPersistConcurrencyValues = <int?>[];
  int prewarmProgressSteps = 1;
  Duration prewarmProgressStepDelay = Duration.zero;

  @override
  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    bool ignoreSnapshot = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmFromRepositoryCount++;
    prewarmDataTypes.add(dataType);
    prewarmForceRecomputeValues.add(forceRecompute);
    prewarmStockCodeBatches.add(List<String>.from(stockCodes, growable: false));
    prewarmFetchBatchSizes.add(fetchBatchSize);
    prewarmPersistConcurrencyValues.add(maxConcurrentPersistWrites);
    final safeTotal = stockCodes.isEmpty ? 1 : stockCodes.length;
    final safeSteps = prewarmProgressSteps <= 0 ? 1 : prewarmProgressSteps;
    for (var step = 1; step <= safeSteps; step++) {
      final current = ((safeTotal * step) / safeSteps).ceil().clamp(
        1,
        safeTotal,
      );
      onProgress?.call(current, safeTotal);
      if (prewarmProgressStepDelay > Duration.zero) {
        await Future<void>.delayed(prewarmProgressStepDelay);
      }
    }
  }
}

class _FakeEmaIndicatorService extends EmaIndicatorService {
  _FakeEmaIndicatorService({required super.repository});

  int prewarmFromRepositoryCount = 0;
  final List<KLineDataType> prewarmDataTypes = <KLineDataType>[];
  final List<bool> prewarmForceRecomputeValues = <bool>[];
  final List<List<String>> prewarmStockCodeBatches = <List<String>>[];
  final List<int?> prewarmFetchBatchSizes = <int?>[];
  final List<int?> prewarmPersistConcurrencyValues = <int?>[];
  int prewarmProgressSteps = 1;
  Duration prewarmProgressStepDelay = Duration.zero;

  @override
  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    bool ignoreSnapshot = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmFromRepositoryCount++;
    prewarmDataTypes.add(dataType);
    prewarmForceRecomputeValues.add(forceRecompute);
    prewarmStockCodeBatches.add(List<String>.from(stockCodes, growable: false));
    prewarmFetchBatchSizes.add(fetchBatchSize);
    prewarmPersistConcurrencyValues.add(maxConcurrentPersistWrites);
    final safeTotal = stockCodes.isEmpty ? 1 : stockCodes.length;
    final safeSteps = prewarmProgressSteps <= 0 ? 1 : prewarmProgressSteps;
    for (var step = 1; step <= safeSteps; step++) {
      final current = ((safeTotal * step) / safeSteps).ceil().clamp(
        1,
        safeTotal,
      );
      onProgress?.call(current, safeTotal);
      if (prewarmProgressStepDelay > Duration.zero) {
        await Future<void>.delayed(prewarmProgressStepDelay);
      }
    }
  }
}

class _FakePowerSystemIndicatorService extends PowerSystemIndicatorService {
  _FakePowerSystemIndicatorService({
    required super.repository,
    required super.emaService,
    required super.macdService,
  });

  int prewarmFromRepositoryCount = 0;
  final List<KLineDataType> prewarmDataTypes = <KLineDataType>[];
  final List<List<String>> prewarmStockCodeBatches = <List<String>>[];

  @override
  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    bool ignoreSnapshot = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmFromRepositoryCount++;
    prewarmDataTypes.add(dataType);
    prewarmStockCodeBatches.add(List<String>.from(stockCodes, growable: false));
    onProgress?.call(stockCodes.length, stockCodes.length);
  }
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
    MacdIndicatorService? macdService,
    AdxIndicatorService? adxService,
    EmaIndicatorService? emaService,
    PowerSystemIndicatorService? powerSystemService,
    AuditService? auditService,
  }) async {
    final effectiveMacdService =
        macdService ?? _FakeMacdIndicatorService(repository: repository);
    final effectiveAdxService =
        adxService ?? _FakeAdxIndicatorService(repository: repository);
    final effectiveEmaService =
        emaService ?? _FakeEmaIndicatorService(repository: repository);
    final effectivePowerSystemService =
        powerSystemService ??
        _FakePowerSystemIndicatorService(
          repository: repository,
          emaService: effectiveEmaService,
          macdService: effectiveMacdService,
        );
    final effectiveAuditService =
        auditService ??
        (() {
          final sink = MemoryAuditSink();
          return AuditService.forTest(
            runner: AuditOperationRunner(sink: sink, nowProvider: DateTime.now),
            readLatest: () async => sink.latestSummary,
            exporter: AuditExportService(
              auditRootProvider: () async => throw UnimplementedError(),
              outputDirectoryProvider: () async => throw UnimplementedError(),
            ),
          );
        })();
    await effectiveMacdService.load();
    await effectiveAdxService.load();
    await effectiveEmaService.load();

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
          ChangeNotifierProvider<MacdIndicatorService>.value(
            value: effectiveMacdService,
          ),
          ChangeNotifierProvider<AdxIndicatorService>.value(
            value: effectiveAdxService,
          ),
          ChangeNotifierProvider<EmaIndicatorService>.value(
            value: effectiveEmaService,
          ),
          ChangeNotifierProvider<PowerSystemIndicatorService>.value(
            value: effectivePowerSystemService,
          ),
          ChangeNotifierProvider<AuditService>.value(
            value: effectiveAuditService,
          ),
        ],
        child: const MaterialApp(home: DataManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToText(WidgetTester tester, String text) async {
    final listView = find.byType(ListView);
    final target = find.text(text);
    for (var i = 0; i < 14; i++) {
      if (target.evaluate().isNotEmpty) {
        await tester.ensureVisible(target.first);
        await tester.pumpAndSettle();
        return;
      }
      await tester.drag(listView, const Offset(0, -320));
      await tester.pumpAndSettle();
    }

    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
    }
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
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );

    expect(find.textContaining('最后交易日'), findsOneWidget);
    expect(find.textContaining('数据完整'), findsWidgets);
    expect(find.textContaining('交易日样本不足'), findsNothing);
    expect(
      find.descendant(of: historicalCard, matching: find.text('拉取缺失')),
      findsNothing,
    );

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
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );

    expect(find.textContaining('最后交易日'), findsOneWidget);
    expect(find.textContaining('不完整'), findsOneWidget);
    expect(
      find.descendant(of: historicalCard, matching: find.text('拉取缺失')),
      findsOneWidget,
    );

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
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );

    expect(find.textContaining('交易日基线不足'), findsOneWidget);
    expect(find.textContaining('数据完整'), findsNothing);
    expect(find.textContaining('缺失20只'), findsOneWidget);
    expect(
      find.descendant(of: historicalCard, matching: find.text('拉取缺失')),
      findsOneWidget,
    );

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
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalFetchButton = find.descendant(
      of: historicalCard,
      matching: find.text('拉取缺失'),
    );

    expect(historicalFetchButton, findsOneWidget);
    await tester.ensureVisible(historicalFetchButton);
    await tester.tap(historicalFetchButton.hitTestable().first);
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
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalFetchButton = find.descendant(
      of: historicalCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(historicalFetchButton);
    await tester.tap(historicalFetchButton.hitTestable().first);
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
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalFetchButton = find.descendant(
      of: historicalCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(historicalFetchButton);
    await tester.tap(historicalFetchButton.hitTestable().first);
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

  testWidgets('历史分钟K拉取缺失无新增记录时应跳过行业重算', (tester) async {
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

    final now = DateTime.now();
    repository.tradingDates = List<DateTime>.generate(12, (index) {
      var day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: index + 1));
      while (day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday) {
        day = day.subtract(const Duration(days: 1));
      }
      return day;
    });
    repository.missingMinuteDatesByStock = {
      '600000': MissingDatesResult(
        missingDates: <DateTime>[now.subtract(const Duration(days: 2))],
        incompleteDates: const <DateTime>[],
        completeDates: const <DateTime>[],
      ),
    };
    repository.missingMinuteDatesAfterFetch =
        const <String, MissingDatesResult>{
          '600000': MissingDatesResult(
            missingDates: <DateTime>[],
            incompleteDates: <DateTime>[],
            completeDates: <DateTime>[],
          ),
        };
    repository.fetchMissingDataResult = FetchResult(
      totalStocks: 1,
      successCount: 1,
      failureCount: 0,
      errors: const {},
      totalRecords: 0,
      duration: const Duration(milliseconds: 20),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalFetchButton = find.descendant(
      of: historicalCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(historicalFetchButton);
    await tester.tap(historicalFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(trendService.recalculateCallCount, 0);
    expect(rankService.recalculateCallCount, 0);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('历史分钟K拉取缺失有新增记录时应触发行业重算', (tester) async {
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
      duration: const Duration(milliseconds: 20),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalFetchButton = find.descendant(
      of: historicalCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(historicalFetchButton);
    await tester.tap(historicalFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(trendService.recalculateCallCount, 1);
    expect(rankService.recalculateCallCount, 1);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('业务进度超过5秒无变化时应展示可预期等待提示', (tester) async {
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
      duration: const Duration(seconds: 10),
    );
    repository.fetchMissingDataDelay = const Duration(seconds: 10);

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );
    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalFetchButton = find.descendant(
      of: historicalCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(historicalFetchButton);
    await tester.tap(historicalFetchButton.hitTestable().first);
    await tester.pump();

    expect(find.text('拉取历史数据'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('已等待'), findsOneWidget);
    expect(find.textContaining('正在处理，请稍候'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('日K强制拉取应显示分阶段进度', (tester) async {
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

    provider.dailyProgressEvents =
        const <({String stage, int current, int total})>[
          (stage: '1/4 拉取日K数据...', current: 1, total: 3),
          (stage: '2/4 写入日K文件...', current: 1, total: 3),
          (stage: '3/4 计算指标...', current: 2, total: 3),
          (stage: '4/4 保存缓存元数据...', current: 1, total: 1),
        ];
    provider.dailyProgressEventInterval = const Duration(milliseconds: 120);
    provider.dailyRefetchDelay = const Duration(milliseconds: 200);

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '日K数据');
    final dailyCard = find.ancestor(
      of: find.text('日K数据'),
      matching: find.byType(Card),
    );
    final dailyForceButton = find.descendant(
      of: dailyCard,
      matching: find.text('强制全量拉取'),
    );

    await tester.ensureVisible(dailyForceButton);
    await tester.tap(dailyForceButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('确定').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('拉取历史数据'), findsOneWidget);
    expect(find.textContaining('1/4 拉取日K数据...'), findsOneWidget);
    expect(find.text('1 / 3 (33.3%)'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 140));
    expect(find.textContaining('2/4 写入日K文件...'), findsOneWidget);
    expect(find.textContaining('速率'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('日K数据卡片应同时显示增量拉取与强制全量拉取动作', (tester) async {
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

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '日K数据');
    final dailyCard = find.ancestor(
      of: find.text('日K数据'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: dailyCard, matching: find.text('增量拉取')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dailyCard, matching: find.text('强制全量拉取')),
      findsOneWidget,
    );

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets(
    'daily force refetch should write FAIL latest audit when completeness is unknown',
    (tester) async {
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
      provider.dailyProgressEvents =
          const <({String stage, int current, int total})>[
            (stage: '1/4 拉取日K数据...', current: 1, total: 3),
            (stage: '日内增量计算', current: 2, total: 3),
            (stage: '4/4 保存缓存元数据...', current: 1, total: 1),
          ];

      await pumpDataManagement(
        tester,
        repository: repository,
        marketDataProvider: provider,
        klineService: klineService,
        trendService: trendService,
        rankService: rankService,
      );

      await scrollToText(tester, '日K数据');
      final dailyCard = find.ancestor(
        of: find.text('日K数据'),
        matching: find.byType(Card),
      );
      final dailyForceButton = find.descendant(
        of: dailyCard,
        matching: find.text('强制全量拉取'),
      );
      await tester.tap(dailyForceButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();

      expect(find.text('Latest Audit'), findsOneWidget);
      expect(find.text('FAIL'), findsWidgets);
      expect(find.text('unknown_state'), findsWidgets);

      provider.dispose();
      klineService.dispose();
      trendService.dispose();
      rankService.dispose();
      await repository.dispose();
    },
  );

  testWidgets('failed historical fetch should produce FAIL latest audit', (
    tester,
  ) async {
    final repository = _FakeDataRepository();
    repository.fetchMissingDataError = StateError('mock historical failure');
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
    final sink = MemoryAuditSink();
    final auditService = AuditService.forTest(
      runner: AuditOperationRunner(sink: sink, nowProvider: DateTime.now),
      readLatest: () async => sink.latestSummary,
      exporter: AuditExportService(
        auditRootProvider: () async => throw UnimplementedError(),
        outputDirectoryProvider: () async => throw UnimplementedError(),
      ),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      auditService: auditService,
    );

    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalFetchButton = find.descendant(
      of: historicalCard,
      matching: find.text('拉取缺失'),
    );
    await tester.tap(historicalFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(sink.latestSummary, isNotNull);
    expect(sink.latestSummary!.verdict.name, 'fail');
    expect(sink.latestSummary!.reasonCodes, contains('runtime_error'));

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('五类数据强制重拉按钮可触发对应动作', (tester) async {
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
      totalRecords: 1,
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

    expect(find.text('强制拉取'), findsAtLeastNWidgets(2));

    await scrollToText(tester, '日K数据');
    final dailyCard = find.ancestor(
      of: find.text('日K数据'),
      matching: find.byType(Card),
    );
    final dailyForceButton = find.descendant(
      of: dailyCard,
      matching: find.text('强制全量拉取'),
    );
    await tester.ensureVisible(dailyForceButton);
    await tester.tap(dailyForceButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(provider.forceDailyRefetchCount, 1);

    await scrollToText(tester, '分时数据');
    final minuteCard = find.ancestor(
      of: find.text('分时数据'),
      matching: find.byType(Card),
    );
    final minuteForceButton = find.descendant(
      of: minuteCard,
      matching: find.text('强制拉取'),
    );
    await tester.ensureVisible(minuteForceButton);
    await tester.tap(minuteForceButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(provider.forceMinuteRefetchCount, 1);

    await scrollToText(tester, '行业数据');
    final industryCard = find.ancestor(
      of: find.text('行业数据'),
      matching: find.byType(Card),
    );
    final industryForceButton = find.descendant(
      of: industryCard,
      matching: find.text('强制拉取'),
    );
    await tester.ensureVisible(industryForceButton);
    await tester.tap(industryForceButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(provider.forceIndustryRefetchCount, 1);

    await scrollToText(tester, '历史分钟K线');
    final historicalCard = find.ancestor(
      of: find.text('历史分钟K线'),
      matching: find.byType(Card),
    );
    final historicalForceButton = find.descendant(
      of: historicalCard,
      matching: find.text('强制重拉'),
    );
    expect(historicalForceButton, findsOneWidget);
    await tester.ensureVisible(historicalForceButton);
    await tester.tap(historicalForceButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(repository.refetchDataCallCount, 1);
    expect(repository.fetchMissingDataCallCount, 0);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('周K数据管理行支持拉取缺失', (tester) async {
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
      totalRecords: 100,
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

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );

    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(repository.fetchMissingDataCallCount, 1);
    expect(repository.fetchMissingDataTypes, contains(KLineDataType.weekly));

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('周K拉取时应显示阶段耗时信息', (tester) async {
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
      totalRecords: 100,
      duration: const Duration(milliseconds: 200),
    );
    repository.statusEventsDuringFetch = const <DataFetching>[
      DataFetching(current: 1, total: 1, currentStock: '__PRECHECK__'),
      DataFetching(current: 1, total: 1, currentStock: '600000'),
      DataFetching(current: 1, total: 1, currentStock: '__WRITE__'),
    ];
    repository.fetchMissingDataDelay = const Duration(milliseconds: 250);

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.textContaining('阶段耗时'), findsOneWidget);
    expect(find.textContaining('阶段进度'), findsOneWidget);
    expect(find.textContaining('拉取 1/1'), findsOneWidget);

    await tester.pumpAndSettle();

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('周K拉取时应显示写入阶段进度', (tester) async {
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
      totalRecords: 100,
      duration: const Duration(milliseconds: 200),
    );
    repository.statusEventsDuringFetch = const <DataFetching>[
      DataFetching(current: 1, total: 1, currentStock: '__PRECHECK__'),
      DataFetching(current: 1, total: 1, currentStock: '__WRITE__'),
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

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.textContaining('写入周K数据...'), findsOneWidget);

    await tester.pumpAndSettle();

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('周K数据管理行支持强制重拉', (tester) async {
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

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );

    final weeklyForceButton = find.descendant(
      of: weeklyCard,
      matching: find.text('强制重拉'),
    );
    await tester.ensureVisible(weeklyForceButton);
    await tester.tap(weeklyForceButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.text('确认强制拉取'), findsOneWidget);
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();

    expect(repository.refetchDataCallCount, 1);
    expect(repository.refetchDataTypes, contains(KLineDataType.weekly));

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('数据管理页不再显示清空按钮', (tester) async {
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

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );
    await scrollToText(tester, '刷新数据');

    expect(find.text('清空'), findsNothing);
    expect(find.text('清空所有缓存'), findsNothing);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('数据管理页应提供日线和周线MACD参数入口并可分别打开页面', (tester) async {
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

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '日线MACD参数设置');
    expect(find.text('日线MACD参数设置'), findsOneWidget);
    expect(find.text('周线MACD参数设置'), findsOneWidget);

    await tester.tap(find.text('日线MACD参数设置'));
    await tester.pumpAndSettle();
    expect(find.text('日线MACD设置'), findsOneWidget);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('数据管理页应提供日线和周线ADX参数入口并可分别打开页面', (tester) async {
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

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '日线ADX参数设置');
    expect(find.text('日线ADX参数设置'), findsOneWidget);
    expect(find.text('周线ADX参数设置'), findsOneWidget);

    await tester.tap(find.text('日线ADX参数设置'));
    await tester.pumpAndSettle();
    expect(find.text('日线ADX设置'), findsOneWidget);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('日线MACD设置页应支持触发日线重算', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
    );

    await scrollToText(tester, '日线MACD参数设置');
    await tester.tap(find.text('日线MACD参数设置').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('日线MACD设置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('重算日线MACD'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    final dailyRecomputeButton = find.byKey(
      const ValueKey('macd_recompute_daily'),
    );
    expect(dailyRecomputeButton, findsOneWidget);
    await tester.ensureVisible(dailyRecomputeButton);
    await tester.tap(dailyRecomputeButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(macdService.prewarmDataTypes, contains(KLineDataType.daily));
    expect(macdService.prewarmForceRecomputeValues, <bool>[false]);
    expect(macdService.prewarmIgnoreSnapshotValues, <bool>[true]);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    await repository.dispose();
  });

  testWidgets('周线MACD设置页应支持触发周线重算', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
    macdService.prewarmProgressSteps = 3;
    macdService.prewarmProgressStepDelay = const Duration(milliseconds: 150);
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
    );

    await scrollToText(tester, '周线MACD参数设置');
    await tester.tap(find.text('周线MACD参数设置').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('周线MACD设置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('重算周线MACD'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    final weeklyRecomputeButton = find.byKey(
      const ValueKey('macd_recompute_weekly'),
    );
    expect(weeklyRecomputeButton, findsOneWidget);
    await tester.ensureVisible(weeklyRecomputeButton);
    await tester.tap(weeklyRecomputeButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('重算周线 MACD'), findsOneWidget);
    expect(find.textContaining('速率'), findsOneWidget);
    expect(find.textContaining('预计剩余'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(macdService.prewarmDataTypes, contains(KLineDataType.weekly));
    expect(macdService.prewarmForceRecomputeValues, contains(false));
    expect(macdService.prewarmIgnoreSnapshotValues, contains(true));

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    await repository.dispose();
  });

  testWidgets('日线ADX设置页应支持触发日线重算', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final adxService = _FakeAdxIndicatorService(repository: repository);
    await adxService.load();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      adxService: adxService,
    );

    await scrollToText(tester, '日线ADX参数设置');
    await tester.tap(find.text('日线ADX参数设置').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('日线ADX设置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('重算日线 ADX'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    final dailyRecomputeButton = find.byKey(
      const ValueKey('adx_recompute_daily'),
    );
    expect(dailyRecomputeButton, findsOneWidget);
    await tester.ensureVisible(dailyRecomputeButton);
    await tester.tap(dailyRecomputeButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(provider.forceDailyRefetchCount, 0);
    expect(adxService.prewarmDataTypes, contains(KLineDataType.daily));
    expect(adxService.prewarmForceRecomputeValues, <bool>[true]);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    adxService.dispose();
    await repository.dispose();
  });

  testWidgets('周线ADX设置页应支持触发周线重算', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final adxService = _FakeAdxIndicatorService(repository: repository);
    await adxService.load();
    adxService.prewarmProgressSteps = 3;
    adxService.prewarmProgressStepDelay = const Duration(milliseconds: 150);
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      adxService: adxService,
    );

    await scrollToText(tester, '周线ADX参数设置');
    await tester.tap(find.text('周线ADX参数设置').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('周线ADX设置'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('重算周线 ADX'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    final weeklyRecomputeButton = find.byKey(
      const ValueKey('adx_recompute_weekly'),
    );
    expect(weeklyRecomputeButton, findsOneWidget);
    await tester.ensureVisible(weeklyRecomputeButton);
    await tester.tap(weeklyRecomputeButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('重算周线 ADX'), findsOneWidget);
    expect(find.textContaining('速率'), findsOneWidget);
    expect(find.textContaining('预计剩余'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(adxService.prewarmDataTypes, contains(KLineDataType.weekly));
    expect(adxService.prewarmForceRecomputeValues, contains(true));

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    adxService.dispose();
    await repository.dispose();
  });

  testWidgets('周K拉取缺失后应触发周线MACD预热', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
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
      totalRecords: 20,
      duration: const Duration(milliseconds: 1),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(macdService.prewarmFromRepositoryCount, 1);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    await repository.dispose();
  });

  testWidgets('周K拉取缺失后应触发周线ADX预热', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
    final adxService = _FakeAdxIndicatorService(repository: repository);
    await adxService.load();
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
      totalRecords: 20,
      duration: const Duration(milliseconds: 1),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
      adxService: adxService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(adxService.prewarmFromRepositoryCount, 1);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    adxService.dispose();
    await repository.dispose();
  });

  testWidgets('周K预热应优先处理本次实际更新股票', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
    final provider = _FakeMarketDataProvider(data: _buildStocks(3));

    final now = DateTime.now();
    repository.fetchMissingDataResult = FetchResult(
      totalStocks: 3,
      successCount: 3,
      failureCount: 0,
      errors: const {},
      totalRecords: 40,
      duration: const Duration(milliseconds: 120),
    );
    repository.dataUpdatedEventsDuringFetch = <DataUpdatedEvent>[
      DataUpdatedEvent(
        stockCodes: const <String>['600000'],
        dateRange: DateRange(now.subtract(const Duration(days: 30)), now),
        dataType: KLineDataType.weekly,
        dataVersion: 2,
      ),
    ];

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(macdService.prewarmFromRepositoryCount, 1);
    expect(macdService.prewarmStockCodeBatches, hasLength(1));
    expect(macdService.prewarmStockCodeBatches.single, const <String>[
      '600000',
    ]);
    expect(macdService.prewarmFetchBatchSizes.single, 120);
    expect(macdService.prewarmPersistConcurrencyValues.single, 8);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    await repository.dispose();
  });

  testWidgets('周K预热阶段应展示速率与预计剩余时间', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
    final provider = _FakeMarketDataProvider(data: _buildStocks(3));

    final now = DateTime.now();
    repository.fetchMissingDataResult = FetchResult(
      totalStocks: 3,
      successCount: 3,
      failureCount: 0,
      errors: const {},
      totalRecords: 40,
      duration: const Duration(milliseconds: 120),
    );
    repository.dataUpdatedEventsDuringFetch = <DataUpdatedEvent>[
      DataUpdatedEvent(
        stockCodes: const <String>['600000', '600001', '600002'],
        dateRange: DateRange(now.subtract(const Duration(days: 30)), now),
        dataType: KLineDataType.weekly,
        dataVersion: 2,
      ),
    ];
    macdService.prewarmProgressSteps = 3;
    macdService.prewarmProgressStepDelay = const Duration(milliseconds: 180);

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));

    expect(find.textContaining('更新周线MACD缓存'), findsOneWidget);
    expect(find.textContaining('速率'), findsWidgets);
    expect(find.textContaining('预计剩余'), findsWidgets);

    await tester.pumpAndSettle();

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    await repository.dispose();
  });

  testWidgets('周K拉取缺失无新增记录时应跳过周线MACD预热', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
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
      macdService: macdService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(macdService.prewarmFromRepositoryCount, 0);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    await repository.dispose();
  });

  testWidgets('周K拉取缺失无新增记录时应跳过周线ADX预热', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
    final adxService = _FakeAdxIndicatorService(repository: repository);
    await adxService.load();
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
      macdService: macdService,
      adxService: adxService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(adxService.prewarmFromRepositoryCount, 0);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    adxService.dispose();
    await repository.dispose();
  });

  testWidgets('周K拉取缺失后应触发周线EMA预热', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    await macdService.load();
    final emaService = _FakeEmaIndicatorService(repository: repository);
    await emaService.load();
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
      totalRecords: 20,
      duration: const Duration(milliseconds: 1),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
      emaService: emaService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(emaService.prewarmFromRepositoryCount, 1);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    emaService.dispose();
    await repository.dispose();
  });

  testWidgets('技术指标区域显示日线EMA设置入口', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(data: []);

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '日线EMA参数设置');
    expect(find.text('日线EMA参数设置'), findsOneWidget);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('技术指标区域显示周线EMA设置入口', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(data: []);

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '周线EMA参数设置');
    expect(find.text('周线EMA参数设置'), findsOneWidget);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets(
    'daily/weekly power system settings cards are shown in data management',
    (tester) async {
      final repository = _FakeDataRepository();
      final klineService = HistoricalKlineService(repository: repository);
      final trendService = _FakeIndustryTrendService();
      final rankService = _FakeIndustryRankService();
      final macdService = _FakeMacdIndicatorService(repository: repository);
      final emaService = _FakeEmaIndicatorService(repository: repository);
      await macdService.load();
      await emaService.load();
      final powerSystemService = _FakePowerSystemIndicatorService(
        repository: repository,
        emaService: emaService,
        macdService: macdService,
      );
      final provider = _FakeMarketDataProvider(data: _buildStocks(1));

      await pumpDataManagement(
        tester,
        repository: repository,
        marketDataProvider: provider,
        klineService: klineService,
        trendService: trendService,
        rankService: rankService,
        macdService: macdService,
        emaService: emaService,
        powerSystemService: powerSystemService,
      );

      await scrollToText(tester, '日线Power System设置');
      expect(find.text('日线Power System设置'), findsOneWidget);
      expect(find.text('周线Power System设置'), findsOneWidget);

      provider.dispose();
      klineService.dispose();
      trendService.dispose();
      rankService.dispose();
      macdService.dispose();
      emaService.dispose();
      powerSystemService.dispose();
      await repository.dispose();
    },
  );

  testWidgets('技术指标区域显示行业EMA广度设置入口', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final provider = _FakeMarketDataProvider(data: _buildStocks(1));

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
    );

    await scrollToText(tester, '行业EMA广度设置');
    expect(find.text('行业EMA广度设置'), findsOneWidget);

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    await repository.dispose();
  });

  testWidgets('weekly sync also prewarms power system cache', (tester) async {
    final repository = _FakeDataRepository();
    final klineService = HistoricalKlineService(repository: repository);
    final trendService = _FakeIndustryTrendService();
    final rankService = _FakeIndustryRankService();
    final macdService = _FakeMacdIndicatorService(repository: repository);
    final emaService = _FakeEmaIndicatorService(repository: repository);
    await macdService.load();
    await emaService.load();
    final powerSystemService = _FakePowerSystemIndicatorService(
      repository: repository,
      emaService: emaService,
      macdService: macdService,
    );
    final provider = _FakeMarketDataProvider(data: _buildStocks(2));

    repository.fetchMissingDataResult = FetchResult(
      totalStocks: 2,
      successCount: 2,
      failureCount: 0,
      errors: const {},
      totalRecords: 20,
      duration: const Duration(milliseconds: 1),
    );

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
      klineService: klineService,
      trendService: trendService,
      rankService: rankService,
      macdService: macdService,
      emaService: emaService,
      powerSystemService: powerSystemService,
    );

    await scrollToText(tester, '周K数据');
    final weeklyCard = find.ancestor(
      of: find.text('周K数据'),
      matching: find.byType(Card),
    );
    final weeklyFetchButton = find.descendant(
      of: weeklyCard,
      matching: find.text('拉取缺失'),
    );
    await tester.ensureVisible(weeklyFetchButton);
    await tester.tap(weeklyFetchButton.hitTestable().first);
    await tester.pumpAndSettle();

    expect(powerSystemService.prewarmFromRepositoryCount, 1);
    expect(powerSystemService.prewarmDataTypes, contains(KLineDataType.weekly));

    provider.dispose();
    klineService.dispose();
    trendService.dispose();
    rankService.dispose();
    macdService.dispose();
    emaService.dispose();
    powerSystemService.dispose();
    await repository.dispose();
  });
}
