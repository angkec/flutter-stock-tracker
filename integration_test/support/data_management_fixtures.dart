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
import 'package:stock_rtwatcher/models/adx_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/audit/services/audit_export_service.dart';
import 'package:stock_rtwatcher/audit/services/audit_operation_runner.dart';
import 'package:stock_rtwatcher/audit/services/audit_service.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/data_management_screen.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

import 'package:stock_rtwatcher/testing/progress_watchdog.dart';

enum DataManagementFixturePreset {
  normal,
  stalledProgress,
  failedFetch,
  newTradingDayIntradayPartial,
  newTradingDayFinalOverride,
}

class DataManagementFixtureContext {
  DataManagementFixtureContext({
    required this.repository,
    required this.marketProvider,
    required this.macdService,
    required this.adxService,
    required this.auditService,
  });

  final FakeDataRepository repository;
  final FakeMarketDataProvider marketProvider;
  final FakeMacdIndicatorService macdService;
  final FakeAdxIndicatorService adxService;
  final AuditService auditService;

  ProgressWatchdog createWatchdog({
    Duration stallThreshold = const Duration(seconds: 5),
  }) {
    return ProgressWatchdog(stallThreshold: stallThreshold, now: DateTime.now);
  }
}

Future<DataManagementFixtureContext> launchDataManagementWithFixture(
  WidgetTester tester, {
  DataManagementFixturePreset preset = DataManagementFixturePreset.normal,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final stocks = _buildStockData();
  final repository = FakeDataRepository(preset: preset);
  final marketProvider = FakeMarketDataProvider(data: stocks, preset: preset);
  final macdService = FakeMacdIndicatorService(repository: repository);
  final adxService = FakeAdxIndicatorService(repository: repository);
  final auditSink = MemoryAuditSink();
  final auditService = AuditService.forTest(
    runner: AuditOperationRunner(sink: auditSink, nowProvider: DateTime.now),
    readLatest: () async => auditSink.latestSummary,
    exporter: AuditExportService(
      auditRootProvider: () async => throw UnimplementedError(),
      outputDirectoryProvider: () async => throw UnimplementedError(),
    ),
  );

  final app = MultiProvider(
    providers: [
      Provider<DataRepository>.value(value: repository),
      ChangeNotifierProvider<MarketDataProvider>.value(value: marketProvider),
      ChangeNotifierProvider<HistoricalKlineService>(
        create: (context) => HistoricalKlineService(repository: repository),
      ),
      ChangeNotifierProvider<IndustryTrendService>(
        create: (_) => FakeIndustryTrendService(),
      ),
      ChangeNotifierProvider<IndustryRankService>(
        create: (_) => FakeIndustryRankService(),
      ),
      ChangeNotifierProvider<MacdIndicatorService>.value(value: macdService),
      ChangeNotifierProvider<AdxIndicatorService>.value(value: adxService),
      ChangeNotifierProvider<AuditService>.value(value: auditService),
    ],
    child: const MaterialApp(home: DataManagementScreen()),
  );

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();

  return DataManagementFixtureContext(
    repository: repository,
    marketProvider: marketProvider,
    macdService: macdService,
    adxService: adxService,
    auditService: auditService,
  );
}

class FakeDataRepository implements DataRepository {
  FakeDataRepository({required DataManagementFixturePreset preset})
    : _preset = preset;

  final DataManagementFixturePreset _preset;

  final StreamController<DataStatus> _statusController =
      StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _updatedController =
      StreamController<DataUpdatedEvent>.broadcast();

  int fetchMissingDataCallCount = 0;
  int refetchDataCallCount = 0;

  List<DateTime> tradingDates = _recentTradingDates();

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _updatedController.stream;

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    return {for (final code in stockCodes) code: const Fresh()};
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) async {
    return 12;
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) async {}

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
  }) async {
    fetchMissingDataCallCount++;

    if (_preset == DataManagementFixturePreset.failedFetch &&
        dataType == KLineDataType.oneMinute) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      throw StateError('mock historical fetch failed');
    }

    if (_preset == DataManagementFixturePreset.stalledProgress &&
        dataType == KLineDataType.oneMinute) {
      _statusController.add(
        const DataFetching(current: 1, total: 5, currentStock: '000001'),
      );
      onProgress?.call(1, 5);
      await Future<void>.delayed(const Duration(seconds: 8));
      return _successResult(totalStocks: stockCodes.length, totalRecords: 120);
    }

    if (dataType == KLineDataType.weekly) {
      await _emitWeeklyProgress(stockCodes.length, onProgress: onProgress);
      return _successResult(totalStocks: stockCodes.length, totalRecords: 240);
    }

    await _emitHistoricalProgress(stockCodes.length, onProgress: onProgress);
    return _successResult(totalStocks: stockCodes.length, totalRecords: 360);
  }

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) async {
    return const MissingDatesResult(
      missingDates: <DateTime>[],
      incompleteDates: <DateTime>[],
      completeDates: <DateTime>[],
    );
  }

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) async {
    final result = <String, MissingDatesResult>{};
    for (var i = 0; i < stockCodes.length; i++) {
      onProgress?.call(i + 1, stockCodes.length);
      if (i < 3) {
        result[stockCodes[i]] = MissingDatesResult(
          missingDates: <DateTime>[DateTime(2026, 2, 10)],
          incompleteDates: const <DateTime>[],
          completeDates: const <DateTime>[],
        );
      } else {
        result[stockCodes[i]] = const MissingDatesResult(
          missingDates: <DateTime>[],
          incompleteDates: <DateTime>[],
          completeDates: <DateTime>[],
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return result;
  }

  @override
  Future<int> getCurrentVersion() async => 1;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    if (dataType == KLineDataType.weekly) {
      return {
        for (final code in stockCodes)
          code: _buildWeeklyBars(
            count: code == stockCodes.first ? 80 : 110,
            anchor: DateTime(2026, 2, 14),
          ),
      };
    }

    return {
      for (final code in stockCodes)
        code: _buildMinuteBarsForDate(DateTime(2026, 2, 14), count: 240),
    };
  }

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async {
    return <String, Quote>{};
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
    return tradingDates;
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    refetchDataCallCount++;
    if (dataType == KLineDataType.weekly) {
      await _emitWeeklyProgress(stockCodes.length, onProgress: onProgress);
      return _successResult(totalStocks: stockCodes.length, totalRecords: 180);
    }

    await _emitHistoricalProgress(stockCodes.length, onProgress: onProgress);
    return _successResult(totalStocks: stockCodes.length, totalRecords: 180);
  }

  Future<void> _emitHistoricalProgress(
    int totalStocks, {
    ProgressCallback? onProgress,
  }) async {
    for (var i = 1; i <= 3; i++) {
      _statusController.add(
        DataFetching(current: i, total: 3, currentStock: '00000$i'),
      );
      onProgress?.call(i, 3);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    for (var i = 1; i <= 3; i++) {
      _statusController.add(
        DataFetching(current: i, total: 3, currentStock: '__WRITE__'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _emitWeeklyProgress(
    int totalStocks, {
    ProgressCallback? onProgress,
  }) async {
    for (var i = 1; i <= 2; i++) {
      _statusController.add(
        DataFetching(current: i, total: 2, currentStock: '__PRECHECK__'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    for (var i = 1; i <= 3; i++) {
      _statusController.add(
        DataFetching(current: i, total: 3, currentStock: '60000$i'),
      );
      onProgress?.call(i, 3);
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }

    for (var i = 1; i <= 3; i++) {
      _statusController.add(
        DataFetching(current: i, total: 3, currentStock: '__WRITE__'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 230));
    }
  }

  FetchResult _successResult({
    required int totalStocks,
    required int totalRecords,
  }) {
    return FetchResult(
      totalStocks: totalStocks,
      successCount: totalStocks,
      failureCount: 0,
      errors: const <String, String>{},
      totalRecords: totalRecords,
      duration: const Duration(seconds: 1),
    );
  }
}

class FakeMarketDataProvider extends MarketDataProvider {
  FakeMarketDataProvider({
    required List<StockMonitorData> data,
    required DataManagementFixturePreset preset,
  }) : _preset = preset,
       _data = data,
       super(
         pool: TdxPool(poolSize: 1),
         stockService: StockService(TdxPool(poolSize: 1)),
         industryService: IndustryService(),
       );

  final List<StockMonitorData> _data;
  final DataManagementFixturePreset _preset;

  int dailyIncrementalSyncCount = 0;
  int dailyForceFullSyncCount = 0;
  int minuteForceRefetchCount = 0;
  int industryForceRefetchCount = 0;
  final List<String> lastDailyIncrementalStages = <String>[];
  final List<String> lastDailyForceFullStages = <String>[];

  @override
  List<StockMonitorData> get allData => _data;

  @override
  bool get isLoading => false;

  @override
  DateTime? get dataDate => DateTime(2026, 2, 14);

  @override
  String? get updateTime => '2026-02-15 10:00:00';

  @override
  int get dailyBarsCacheCount => 120;

  @override
  String get dailyBarsCacheSize => '20 MB';

  @override
  int get minuteDataCacheCount => 120;

  @override
  String get minuteDataCacheSize => '45 MB';

  @override
  bool get industryDataLoaded => true;

  @override
  String? get industryDataCacheSize => '3 MB';

  @override
  String get totalCacheSizeFormatted => '68 MB';

  @override
  Future<void> refresh({
    bool silent = false,
    bool forceMinuteRefetch = false,
    bool forceDailyRefetch = false,
  }) async {
    if (forceMinuteRefetch) {
      minuteForceRefetchCount++;
    }
    if (forceDailyRefetch) {
      dailyForceFullSyncCount++;
    }
  }

  @override
  Future<void> syncDailyBarsIncremental({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    dailyIncrementalSyncCount++;
    lastDailyIncrementalStages.clear();

    const events = <({String stage, int current, int total})>[
      (stage: '1/4 拉取日K数据...', current: 1, total: 3),
      (stage: '2/4 写入日K文件...', current: 1, total: 3),
      (stage: '2/4 写入日K文件...', current: 3, total: 3),
      (stage: '3/4 计算指标...', current: 1, total: 1),
      (stage: '4/4 保存缓存元数据...', current: 1, total: 1),
    ];

    await _emitDailyStages(
      events: events,
      stageCollector: lastDailyIncrementalStages,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> syncDailyBarsForceFull({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    dailyForceFullSyncCount++;
    lastDailyForceFullStages.clear();

    final events = switch (_preset) {
      DataManagementFixturePreset.newTradingDayIntradayPartial =>
        <({String stage, int current, int total})>[
          (stage: '1/4 拉取日K数据...', current: 1, total: 3),
          (stage: '2/4 写入日K文件...', current: 1, total: 3),
          (stage: '2/4 写入日K文件...', current: 3, total: 3),
          (stage: '3/4 日内增量计算...', current: 1, total: 1),
          (stage: '4/4 保存缓存元数据...', current: 1, total: 1),
        ],
      DataManagementFixturePreset.newTradingDayFinalOverride =>
        <({String stage, int current, int total})>[
          (stage: '1/4 拉取日K数据...', current: 1, total: 3),
          (stage: '2/4 写入日K文件...', current: 1, total: 3),
          (stage: '2/4 写入日K文件...', current: 3, total: 3),
          (stage: '3/4 终盘覆盖增量重算...', current: 1, total: 1),
          (stage: '4/4 保存缓存元数据...', current: 1, total: 1),
        ],
      _ => <({String stage, int current, int total})>[
        (stage: '1/4 准备日K拉取', current: 1, total: 4),
        (stage: '2/4 写入日K文件', current: 20, total: 100),
        (stage: '2/4 写入日K文件', current: 60, total: 100),
        (stage: '2/4 写入日K文件', current: 100, total: 100),
        (stage: '3/4 更新版本', current: 1, total: 1),
        (stage: '4/4 完成', current: 1, total: 1),
      ],
    };

    await _emitDailyStages(
      events: events,
      stageCollector: lastDailyForceFullStages,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> forceRefetchDailyBars({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) {
    return syncDailyBarsForceFull(
      onProgress: onProgress,
      indicatorTargetStockCodes: indicatorTargetStockCodes,
    );
  }

  Future<void> _emitDailyStages({
    required List<({String stage, int current, int total})> events,
    required List<String> stageCollector,
    required void Function(String stage, int current, int total)? onProgress,
  }) async {
    for (final event in events) {
      stageCollector.add(event.stage);
      onProgress?.call(event.stage, event.current, event.total);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Future<void> forceReloadIndustryData() async {
    industryForceRefetchCount++;
  }
}

class FakeIndustryTrendService extends IndustryTrendService {
  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

class FakeIndustryRankService extends IndustryRankService {
  @override
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

class FakeMacdIndicatorService extends MacdIndicatorService {
  FakeMacdIndicatorService({required super.repository});

  int prewarmCalls = 0;
  final List<KLineDataType> prewarmDataTypes = <KLineDataType>[];
  final List<bool> prewarmForceRecomputeValues = <bool>[];
  final List<int?> prewarmFetchBatchSizes = <int?>[];
  final List<int?> prewarmPersistConcurrencyValues = <int?>[];
  Duration weeklyForceRecomputeInitialDelay = Duration.zero;
  Duration progressStepDelay = const Duration(milliseconds: 200);

  @override
  MacdConfig configFor(KLineDataType dataType) {
    return MacdIndicatorService.defaultConfigFor(dataType);
  }

  @override
  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmCalls++;
    prewarmDataTypes.add(dataType);
    prewarmForceRecomputeValues.add(forceRecompute);
    prewarmFetchBatchSizes.add(fetchBatchSize);
    prewarmPersistConcurrencyValues.add(maxConcurrentPersistWrites);

    if (forceRecompute &&
        dataType == KLineDataType.weekly &&
        weeklyForceRecomputeInitialDelay > Duration.zero) {
      await Future<void>.delayed(weeklyForceRecomputeInitialDelay);
    }

    for (var i = 1; i <= stockCodes.length; i++) {
      onProgress?.call(i, stockCodes.length);
      await Future<void>.delayed(progressStepDelay);
    }
  }
}

class FakeAdxIndicatorService extends AdxIndicatorService {
  FakeAdxIndicatorService({required super.repository});

  int prewarmCalls = 0;
  final List<KLineDataType> prewarmDataTypes = <KLineDataType>[];
  final List<bool> prewarmForceRecomputeValues = <bool>[];
  final List<int?> prewarmFetchBatchSizes = <int?>[];
  final List<int?> prewarmPersistConcurrencyValues = <int?>[];
  Duration progressStepDelay = const Duration(milliseconds: 200);

  @override
  AdxConfig configFor(KLineDataType dataType) {
    return AdxIndicatorService.defaultConfigFor(dataType);
  }

  @override
  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmCalls++;
    prewarmDataTypes.add(dataType);
    prewarmForceRecomputeValues.add(forceRecompute);
    prewarmFetchBatchSizes.add(fetchBatchSize);
    prewarmPersistConcurrencyValues.add(maxConcurrentPersistWrites);

    for (var i = 1; i <= stockCodes.length; i++) {
      onProgress?.call(i, stockCodes.length);
      await Future<void>.delayed(progressStepDelay);
    }
  }
}

List<StockMonitorData> _buildStockData() {
  return List<StockMonitorData>.generate(6, (index) {
    final code = index.isEven ? '60000$index' : '00000$index';
    return StockMonitorData(
      stock: Stock(
        code: code,
        name: 'Stock $index',
        market: index.isEven ? 1 : 0,
      ),
      ratio: 1.2,
      changePercent: 0.8,
      industry: '测试行业',
    );
  });
}

List<DateTime> _recentTradingDates() {
  final now = DateTime(2026, 2, 15);
  return List<DateTime>.generate(14, (index) {
    return now.subtract(Duration(days: index + 1));
  });
}

List<KLine> _buildWeeklyBars({required int count, required DateTime anchor}) {
  return List<KLine>.generate(count, (index) {
    final date = anchor.subtract(Duration(days: (count - index) * 7));
    return KLine(
      datetime: date,
      open: 10,
      close: 10.2,
      high: 10.4,
      low: 9.8,
      volume: 1000,
      amount: 12000,
    );
  });
}

List<KLine> _buildMinuteBarsForDate(DateTime day, {required int count}) {
  final start = DateTime(day.year, day.month, day.day, 9, 30);
  return List<KLine>.generate(count, (index) {
    final dt = start.add(Duration(minutes: index));
    return KLine(
      datetime: dt,
      open: 10,
      close: 10.1,
      high: 10.2,
      low: 9.9,
      volume: (800 + index).toDouble(),
      amount: 9000 + index * 10,
    );
  });
}
