import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/market_snapshot_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/daily_kline_read_service.dart';
import 'package:stock_rtwatcher/services/daily_kline_sync_service.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/china_trading_calendar_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _ReconnectableFakePool extends TdxPool {
  _ReconnectableFakePool({
    required this.dailyBarsByCode,
    this.throwOnBatchFetch = false,
  }) : super(poolSize: 1);

  final Map<String, List<KLine>> dailyBarsByCode;
  final bool throwOnBatchFetch;
  int ensureConnectedCalls = 0;
  int batchFetchCalls = 0;
  bool connected = false;
  int? lastRequestedCount;

  @override
  Future<bool> ensureConnected() async {
    ensureConnectedCalls++;
    connected = true;
    return true;
  }

  @override
  Future<void> batchGetSecurityBarsStreaming({
    required List<Stock> stocks,
    required int category,
    required int start,
    required int count,
    required void Function(int stockIndex, List<KLine> bars) onStockBars,
  }) async {
    batchFetchCalls++;
    if (!connected) {
      throw StateError('Not connected');
    }
    if (throwOnBatchFetch) {
      throw StateError('Unexpected network fetch');
    }
    lastRequestedCount = count;

    for (var index = 0; index < stocks.length; index++) {
      final stock = stocks[index];
      onStockBars(index, dailyBarsByCode[stock.code] ?? const <KLine>[]);
    }
  }
}

class _FailIfFetchedStockService extends StockService {
  _FailIfFetchedStockService(super.pool);

  int getAllStocksCalls = 0;
  int batchGetMonitorDataCalls = 0;

  @override
  Future<List<Stock>> getAllStocks() async {
    getAllStocksCalls++;
    throw StateError('Unexpected network fetch via getAllStocks');
  }

  @override
  Future<MonitorDataResult> batchGetMonitorData(
    List<Stock> stocks, {
    IndustryService? industryService,
    void Function(int current, int total)? onProgress,
    void Function(List<StockMonitorData> results)? onData,
    void Function(String code, List<KLine> bars)? onBarsData,
  }) async {
    batchGetMonitorDataCalls++;
    throw StateError('Unexpected network fetch via batchGetMonitorData');
  }
}

class _SpyTradingCalendarService extends ChinaTradingCalendarService {
  _SpyTradingCalendarService({
    this.throwOnLoad = false,
    this.throwOnRefresh = false,
    this.isTradingDayOverride,
    this.latestTradingDayOverride,
  }) : super(officialClosedDates: const <String>{});

  final bool throwOnLoad;
  final bool throwOnRefresh;
  final bool? isTradingDayOverride;
  final DateTime? latestTradingDayOverride;
  int loadCachedCalendarCalls = 0;
  int refreshRemoteCalendarCalls = 0;

  @override
  Future<bool> loadCachedCalendar() async {
    loadCachedCalendarCalls++;
    if (throwOnLoad) {
      throw StateError('load cached failed');
    }
    return true;
  }

  @override
  Future<bool> refreshRemoteCalendar() async {
    refreshRemoteCalendarCalls++;
    if (throwOnRefresh) {
      throw StateError('remote refresh failed');
    }
    return true;
  }

  @override
  bool isTradingDay(DateTime day, {Iterable<DateTime>? inferredTradingDates}) {
    final override = isTradingDayOverride;
    if (override != null) {
      return override;
    }
    return super.isTradingDay(day, inferredTradingDates: inferredTradingDates);
  }

  @override
  DateTime? latestTradingDayOnOrBefore(
    DateTime anchorDay, {
    Iterable<DateTime>? availableTradingDates,
    bool includeAnchor = false,
    int maxLookbackDays = 40,
  }) {
    final override = latestTradingDayOverride;
    if (override != null) {
      return override;
    }
    return super.latestTradingDayOnOrBefore(
      anchorDay,
      availableTradingDates: availableTradingDates,
      includeAnchor: includeAnchor,
      maxLookbackDays: maxLookbackDays,
    );
  }
}

class _FakeDataRepository implements DataRepository {
  int getKlinesCallCount = 0;

  @override
  Stream<DataStatus> get statusStream => const Stream.empty();

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => const Stream.empty();

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    getKlinesCallCount++;
    return {for (final code in stockCodes) code: const <KLine>[]};
  }

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) {
    throw UnimplementedError();
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
  Future<List<DateTime>> getTradingDates(DateRange dateRange) {
    throw UnimplementedError();
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}
}

class _NoopCheckpointStore extends DailyKlineCheckpointStore {
  @override
  Future<void> saveGlobal({
    required String dateKey,
    required DailyKlineSyncMode mode,
    required int successAtMs,
  }) async {}

  @override
  Future<DailyKlineGlobalCheckpoint?> loadGlobal() async => null;

  @override
  Future<void> savePerStockSuccessAtMs(Map<String, int> value) async {}

  @override
  Future<Map<String, int>> loadPerStockSuccessAtMs() async =>
      const <String, int>{};
}

class _NoopCacheStore extends DailyKlineCacheStore {
  _NoopCacheStore()
    : super(
        storage: KLineFileStorage()
          ..setBaseDirPathForTesting(Directory.systemTemp.path),
      );

  @override
  Future<void> saveAll(
    Map<String, List<KLine>> barsByStockCode, {
    void Function(int current, int total)? onProgress,
    int? maxConcurrentWrites,
  }) async {}
}

class _FakeDailyKlineReadService extends DailyKlineReadService {
  _FakeDailyKlineReadService() : super(cacheStore: _NoopCacheStore());

  int readCallCount = 0;
  int readWithReportCallCount = 0;
  Object? readError;
  DailyKlineReadReport? readReportOverride;
  final Map<String, List<KLine>> payloadByCode = <String, List<KLine>>{};

  @override
  Future<Map<String, List<KLine>>> readOrThrow({
    required List<String> stockCodes,
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    readCallCount++;
    final error = readError;
    if (error != null) {
      throw error;
    }
    return {
      for (final code in stockCodes)
        code: payloadByCode[code] ?? const <KLine>[],
    };
  }

  @override
  Future<DailyKlineReadResult> readWithReport({
    required List<String> stockCodes,
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    readWithReportCallCount++;
    final result = <String, List<KLine>>{};
    final missing = <String>[];
    final insufficient = <String>[];

    for (final code in stockCodes) {
      final bars = payloadByCode[code];
      if (bars == null || bars.isEmpty) {
        missing.add(code);
        continue;
      }
      if (bars.length < targetBars) {
        insufficient.add(code);
      }
      result[code] = bars;
    }

    final report =
        readReportOverride ??
        DailyKlineReadReport(
          totalStocks: stockCodes.length,
          missingStockCodes: missing,
          corruptedStockCodes: const <String>[],
          insufficientStockCodes: insufficient,
        );

    return DailyKlineReadResult(barsByStockCode: result, report: report);
  }
}

class _FakeDailyKlineSyncService extends DailyKlineSyncService {
  _FakeDailyKlineSyncService()
    : super(
        checkpointStore: _NoopCheckpointStore(),
        cacheStore: _NoopCacheStore(),
        fetcher:
            ({
              required List<Stock> stocks,
              required int count,
              required DailyKlineSyncMode mode,
              void Function(int current, int total)? onProgress,
            }) async {
              return const <String, List<KLine>>{};
            },
      );

  int syncCallCount = 0;
  DailyKlineSyncMode? lastMode;
  DailySyncCompletenessState completenessState =
      DailySyncCompletenessState.intradayPartial;
  List<String> successStockCodes = const <String>[];
  List<String> failureStockCodes = const <String>[];
  Map<String, String> failureReasons = const <String, String>{};

  @override
  Future<DailyKlineSyncResult> sync({
    required DailyKlineSyncMode mode,
    required List<Stock> stocks,
    required int targetBars,
    void Function(String stage, int current, int total)? onProgress,
  }) async {
    syncCallCount++;
    lastMode = mode;
    return DailyKlineSyncResult(
      successStockCodes: successStockCodes,
      failureStockCodes: failureStockCodes,
      failureReasons: failureReasons,
      completenessState: completenessState,
    );
  }
}

class _DelayedFalseBreakoutService extends BreakoutService {
  _DelayedFalseBreakoutService(this.delay);

  final Duration delay;
  int callCount = 0;

  @override
  Future<bool> isBreakoutPullback(
    List<KLine> dailyBars, {
    String? stockCode,
  }) async {
    callCount++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return false;
  }
}

class _RecordingBreakoutService extends BreakoutService {
  final List<String> touchedStockCodes = <String>[];

  @override
  Future<bool> isBreakoutPullback(
    List<KLine> dailyBars, {
    String? stockCode,
  }) async {
    if (stockCode != null) {
      touchedStockCodes.add(stockCode);
    }
    return false;
  }
}

class _AlwaysTrueBreakoutService extends BreakoutService {
  @override
  Future<bool> isBreakoutPullback(
    List<KLine> dailyBars, {
    String? stockCode,
  }) async {
    return true;
  }
}

class _RecordingMacdIndicatorService extends MacdIndicatorService {
  _RecordingMacdIndicatorService({required super.repository});

  final List<Set<String>> prewarmPayloadStockCodes = <Set<String>>[];

  @override
  Future<void> prewarmFromBars({
    required KLineDataType dataType,
    required Map<String, List<KLine>> barsByStockCode,
    bool forceRecompute = false,
    int? maxConcurrentTasks,
    int? maxConcurrentPersistWrites,
    int? persistBatchSize,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmPayloadStockCodes.add(barsByStockCode.keys.toSet());
    final total = barsByStockCode.isEmpty ? 1 : barsByStockCode.length;
    onProgress?.call(total, total);
  }
}

class _BlockingMacdPrewarmService extends MacdIndicatorService {
  _BlockingMacdPrewarmService({required super.repository});

  final Completer<void> started = Completer<void>();
  final Completer<void> unblock = Completer<void>();

  @override
  Future<void> prewarmFromBars({
    required KLineDataType dataType,
    required Map<String, List<KLine>> barsByStockCode,
    bool forceRecompute = false,
    int? maxConcurrentTasks,
    int? maxConcurrentPersistWrites,
    int? persistBatchSize,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await unblock.future;
    onProgress?.call(1, 1);
  }
}

class _BlockingAdxPrewarmService extends AdxIndicatorService {
  _BlockingAdxPrewarmService({required super.repository});

  final Completer<void> started = Completer<void>();
  final Completer<void> unblock = Completer<void>();

  @override
  Future<void> prewarmFromBars({
    required KLineDataType dataType,
    required Map<String, List<KLine>> barsByStockCode,
    bool forceRecompute = false,
    int? maxConcurrentTasks,
    int? maxConcurrentPersistWrites,
    int? persistBatchSize,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await unblock.future;
    onProgress?.call(1, 1);
  }
}

class _RecordingEmaIndicatorService extends EmaIndicatorService {
  _RecordingEmaIndicatorService({required super.repository});

  final List<Set<String>> prewarmPayloadStockCodes = <Set<String>>[];

  @override
  Future<void> prewarmFromBars({
    required KLineDataType dataType,
    required Map<String, List<KLine>> barsByStockCode,
    bool forceRecompute = false,
    int? maxConcurrentTasks,
    int? maxConcurrentPersistWrites,
    int? persistBatchSize,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmPayloadStockCodes.add(barsByStockCode.keys.toSet());
    final total = barsByStockCode.isEmpty ? 1 : barsByStockCode.length;
    onProgress?.call(total, total);
  }
}

DailyKlineCacheStore _buildStorageForPath(String basePath) {
  final storage = KLineFileStorage();
  storage.setBaseDirPathForTesting(basePath);
  return DailyKlineCacheStore(storage: storage);
}

MarketSnapshotStore _buildMarketSnapshotStoreForPath(String basePath) {
  final storage = KLineFileStorage();
  storage.setBaseDirPathForTesting(basePath);
  return MarketSnapshotStore(storage: storage);
}

List<KLine> _buildDailyBars(int n) {
  final bars = <KLine>[];
  final anchor = DateTime(2026, 2, 18);
  var cursor = anchor.subtract(Duration(days: n * 2));
  while (bars.length < n) {
    if (cursor.weekday <= DateTime.friday) {
      final index = bars.length;
      bars.add(
        KLine(
          datetime: cursor,
          open: 10,
          close: 10.2,
          high: 10.3,
          low: 9.9,
          volume: 1000.0 + index,
          amount: 10000.0 + index,
        ),
      );
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return bars;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forceRefetchDailyBars should ensure pool connection first', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-bars-provider-unit-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final stock = Stock(code: '600000', name: '浦发银行', market: 1);
    final monitorData = StockMonitorData(
      stock: stock,
      ratio: 1.2,
      changePercent: 0.5,
    );

    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode([monitorData.toJson()]),
      'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
    });

    final pool = _ReconnectableFakePool(
      dailyBarsByCode: {'600000': _buildDailyBars(260)},
    );
    final provider = MarketDataProvider(
      pool: pool,
      stockService: StockService(pool),
      industryService: IndustryService(),
      dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
    );
    provider.setPullbackService(PullbackService());

    await provider.loadFromCache();

    await provider.forceRefetchDailyBars();

    expect(pool.ensureConnectedCalls, 1);
    expect(pool.lastRequestedCount, 260);
    expect(provider.dailyBarsCacheCount, 1);
  });

  test(
    'forceRefetchDailyBars should avoid persisting huge daily bars payload',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-bars-provider-unit-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
        'daily_bars_cache_v1': '{"legacy":[]}',
      });

      final pool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
      );
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
      );
      provider.setPullbackService(PullbackService());

      await provider.loadFromCache();
      await provider.forceRefetchDailyBars();
      await Future<void>.delayed(const Duration(milliseconds: 700));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('daily_bars_cache_v1'), isNull);
      expect(
        prefs.getString('daily_kline_checkpoint_last_success_date'),
        isNotNull,
      );
      expect(prefs.getString('daily_kline_checkpoint_last_mode'), isNotNull);
      expect(
        prefs.getInt('daily_kline_checkpoint_last_success_at_ms'),
        isNotNull,
      );
      expect(
        prefs.getString('daily_kline_checkpoint_per_stock_last_success_at_ms'),
        isNull,
      );
    },
  );

  test(
    'forceRefetchDailyBars should clear legacy market_data_cache payload',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-bars-metadata-only-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
        isBreakout: false,
      );
      final originalCache = jsonEncode([monitorData.toJson()]);

      SharedPreferences.setMockInitialValues({
        'market_data_cache': originalCache,
        'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
      });

      final pool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
      );
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
      );
      provider
        ..setPullbackService(PullbackService())
        ..setBreakoutService(_AlwaysTrueBreakoutService());

      await provider.loadFromCache();
      await provider.forceRefetchDailyBars();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('market_data_cache'), isNull);
    },
  );

  test(
    'forceRefetchDailyBars should persist daily bars into file storage',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-bars-file-persist-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final today = DateTime.now();
      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': DateTime(
          today.year,
          today.month,
          today.day,
        ).toIso8601String(),
      });

      final storage = _buildStorageForPath(tempDir.path);
      final pool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
      );
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyBarsFileStorage: storage,
      );
      provider.setPullbackService(PullbackService());

      await provider.loadFromCache();
      await provider.forceRefetchDailyBars();

      final loadedFromStore = await storage.loadForStocks(
        const ['600000'],
        anchorDate: DateTime(2026, 12, 31),
        targetBars: 260,
      );
      expect(loadedFromStore['600000'], isNotNull);
      expect(loadedFromStore['600000']!.length, 260);
    },
  );

  test(
    'forceRefetchDailyBars should report file-write stage progress',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-bars-progress-stage-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
      });

      final pool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
      );
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
      );
      provider.setPullbackService(PullbackService());

      await provider.loadFromCache();

      final stages = <String>[];
      await provider.forceRefetchDailyBars(
        onProgress: (stage, _, __) {
          stages.add(stage);
        },
      );

      expect(stages.any((stage) => stage.startsWith('2/4 写入日K文件')), isTrue);
      expect(stages.last, '4/4 保存缓存元数据...');
    },
  );

  test(
    'forceRefetchDailyBars should avoid sequential breakout recompute latency',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-bars-breakout-latency-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final monitorData = List<StockMonitorData>.generate(10, (index) {
        final code = (600000 + index).toString();
        return StockMonitorData(
          stock: Stock(code: code, name: '股票$code', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        );
      });

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode(
          monitorData.map((e) => e.toJson()).toList(growable: false),
        ),
        'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
      });

      final pool = _ReconnectableFakePool(
        dailyBarsByCode: {
          for (final item in monitorData) item.stock.code: _buildDailyBars(260),
        },
      );
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
      );
      provider.setPullbackService(PullbackService());
      final breakoutService = _DelayedFalseBreakoutService(
        const Duration(milliseconds: 150),
      );
      provider.setBreakoutService(breakoutService);

      await provider.loadFromCache();

      final stopwatch = Stopwatch()..start();
      await provider.forceRefetchDailyBars();
      stopwatch.stop();

      expect(breakoutService.callCount, monitorData.length);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 1200)));
    },
  );

  test(
    'forceRefetchDailyBars should recompute indicators only for impacted stocks',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-bars-incremental-indicator-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final monitorData = List<StockMonitorData>.generate(3, (index) {
        final code = (600000 + index).toString();
        return StockMonitorData(
          stock: Stock(code: code, name: '股票$code', market: 1),
          ratio: 1.1,
          changePercent: 0.3,
        );
      });

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode(
          monitorData.map((e) => e.toJson()).toList(growable: false),
        ),
        'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
      });

      final barsByCode = <String, List<KLine>>{
        for (final item in monitorData) item.stock.code: _buildDailyBars(260),
      };
      final pool = _ReconnectableFakePool(dailyBarsByCode: barsByCode);
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
      );
      provider.setPullbackService(PullbackService());

      final breakoutService = _RecordingBreakoutService();
      provider.setBreakoutService(breakoutService);

      final macdService = _RecordingMacdIndicatorService(
        repository: _FakeDataRepository(),
      );
      provider.setMacdService(macdService);

      await provider.loadFromCache();

      await provider.forceRefetchDailyBars(
        indicatorTargetStockCodes: const {'600000'},
      );

      expect(breakoutService.touchedStockCodes.toSet(), {'600000'});
      expect(macdService.prewarmPayloadStockCodes.last, {'600000'});
    },
  );

  test(
    'forceRefetchDailyBars should start MACD and ADX prewarm concurrently',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-bars-indicator-concurrency-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
      });

      final pool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
      );
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
      );
      provider.setPullbackService(PullbackService());

      final macdService = _BlockingMacdPrewarmService(
        repository: _FakeDataRepository(),
      );
      final adxService = _BlockingAdxPrewarmService(
        repository: _FakeDataRepository(),
      );
      provider.setMacdService(macdService);
      provider.setAdxService(adxService);

      await provider.loadFromCache();

      final refetchFuture = provider.forceRefetchDailyBars();

      await macdService.started.future.timeout(const Duration(seconds: 2));
      Object? adxStartError;
      try {
        await adxService.started.future.timeout(const Duration(seconds: 1));
      } catch (error) {
        adxStartError = error;
      } finally {
        if (!macdService.unblock.isCompleted) {
          macdService.unblock.complete();
        }
        if (!adxService.unblock.isCompleted) {
          adxService.unblock.complete();
        }
      }

      await refetchFuture;

      expect(
        adxStartError,
        isNull,
        reason: 'ADX prewarm should start before MACD prewarm is unblocked',
      );
    },
  );

  test('refresh should reuse persisted daily bars after restart', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-bars-file-reuse-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final today = DateTime.now();
    final tradingDay = DateTime(today.year, today.month, today.day);
    final stock = Stock(code: '600000', name: '浦发银行', market: 1);
    final monitorData = StockMonitorData(
      stock: stock,
      ratio: 1.2,
      changePercent: 0.5,
    );

    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode([monitorData.toJson()]),
      'market_data_date': tradingDay.toIso8601String(),
      'minute_data_date': tradingDay.toIso8601String(),
      'minute_data_cache_v1': 1,
    });

    final storage1 = _buildStorageForPath(tempDir.path);
    final firstPool = _ReconnectableFakePool(
      dailyBarsByCode: {'600000': _buildDailyBars(260)},
    );
    final firstProvider = MarketDataProvider(
      pool: firstPool,
      stockService: StockService(firstPool),
      industryService: IndustryService(),
      dailyBarsFileStorage: storage1,
    );
    firstProvider.setPullbackService(PullbackService());
    await firstProvider.loadFromCache();
    await firstProvider.forceRefetchDailyBars();

    final storage2 = _buildStorageForPath(tempDir.path);
    final secondPool = _ReconnectableFakePool(
      dailyBarsByCode: const <String, List<KLine>>{},
      throwOnBatchFetch: true,
    );
    final secondProvider = MarketDataProvider(
      pool: secondPool,
      stockService: StockService(secondPool),
      industryService: IndustryService(),
      dailyBarsFileStorage: storage2,
    );
    secondProvider.setPullbackService(PullbackService());
    await secondProvider.loadFromCache();
    await secondProvider.refresh(silent: true);

    expect(secondPool.batchFetchCalls, 0);
    expect(secondProvider.dailyBarsCacheCount, 1);
  });

  test('loadFromCache should restore daily bars after restart', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-bars-load-cache-restart-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final tradingDay = DateTime(2026, 2, 15);
    final stock = Stock(code: '600000', name: '浦发银行', market: 1);
    final monitorData = StockMonitorData(
      stock: stock,
      ratio: 1.2,
      changePercent: 0.5,
    );

    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode([monitorData.toJson()]),
      'market_data_date': tradingDay.toIso8601String(),
      'minute_data_date': tradingDay.toIso8601String(),
      'minute_data_cache_v1': 1,
    });

    final storage1 = _buildStorageForPath(tempDir.path);
    final firstPool = _ReconnectableFakePool(
      dailyBarsByCode: {'600000': _buildDailyBars(260)},
    );
    final firstProvider = MarketDataProvider(
      pool: firstPool,
      stockService: StockService(firstPool),
      industryService: IndustryService(),
      dailyBarsFileStorage: storage1,
    );
    firstProvider.setPullbackService(PullbackService());
    await firstProvider.loadFromCache();
    await firstProvider.forceRefetchDailyBars();

    final storage2 = _buildStorageForPath(tempDir.path);
    final secondPool = _ReconnectableFakePool(
      dailyBarsByCode: const <String, List<KLine>>{},
      throwOnBatchFetch: true,
    );
    final secondProvider = MarketDataProvider(
      pool: secondPool,
      stockService: StockService(secondPool),
      industryService: IndustryService(),
      dailyBarsFileStorage: storage2,
    );
    secondProvider.setPullbackService(PullbackService());

    await secondProvider.loadFromCache();

    expect(secondProvider.dailyBarsCacheCount, 1);
    expect(secondPool.batchFetchCalls, 0);
  });

  test(
    'loadFromCache should best-effort load cached trading calendar',
    () async {
      final tradingDay = DateTime(2026, 2, 15);
      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': tradingDay.toIso8601String(),
        'minute_data_date': tradingDay.toIso8601String(),
        'minute_data_cache_v1': 1,
      });

      final calendarService = _SpyTradingCalendarService(throwOnLoad: true);
      final pool = _ReconnectableFakePool(
        dailyBarsByCode: const <String, List<KLine>>{},
        throwOnBatchFetch: true,
      );
      final provider = MarketDataProvider(
        pool: pool,
        stockService: _FailIfFetchedStockService(pool),
        industryService: IndustryService(),
        tradingCalendarService: calendarService,
        nowProvider: () => DateTime(2026, 2, 16, 10),
      );

      await provider.loadFromCache();

      expect(calendarService.loadCachedCalendarCalls, 1);
      expect(provider.allData, isNotEmpty);
    },
  );

  test(
    'refresh should reuse cache on holiday weekday without minute refetch',
    () async {
      final holidayDate = DateTime(2026, 10, 6, 10, 0); // National Day break
      final lastTradingDay = DateTime(2026, 10, 6);

      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': lastTradingDay.toIso8601String(),
        'minute_data_date': lastTradingDay.toIso8601String(),
        'minute_data_cache_v1': 1,
      });

      final pool = _ReconnectableFakePool(
        dailyBarsByCode: const <String, List<KLine>>{},
        throwOnBatchFetch: true,
      );
      final stockService = _FailIfFetchedStockService(pool);
      final provider = MarketDataProvider(
        pool: pool,
        stockService: stockService,
        industryService: IndustryService(),
        nowProvider: () => holidayDate,
        tradingCalendarService: const ChinaTradingCalendarService(),
      );

      await provider.loadFromCache();
      await provider.refresh(silent: true);

      expect(stockService.getAllStocksCalls, 0);
      expect(stockService.batchGetMonitorDataCalls, 0);
      expect(provider.errorMessage, isNull);
      expect(provider.allData, isNotEmpty);
    },
  );

  test(
    'refresh should trigger best-effort remote trading calendar sync',
    () async {
      final holidayDate = DateTime(2026, 10, 6, 10, 0);
      final lastTradingDay = DateTime(2026, 9, 30);

      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': lastTradingDay.toIso8601String(),
        'minute_data_date': lastTradingDay.toIso8601String(),
        'minute_data_cache_v1': 1,
      });

      final calendarService = _SpyTradingCalendarService(
        throwOnRefresh: true,
        isTradingDayOverride: false,
        latestTradingDayOverride: lastTradingDay,
      );
      final pool = _ReconnectableFakePool(
        dailyBarsByCode: const <String, List<KLine>>{},
        throwOnBatchFetch: true,
      );
      final stockService = _FailIfFetchedStockService(pool);
      final provider = MarketDataProvider(
        pool: pool,
        stockService: stockService,
        industryService: IndustryService(),
        nowProvider: () => holidayDate,
        tradingCalendarService: calendarService,
      );

      await provider.loadFromCache();
      await provider.refresh(silent: true);

      expect(calendarService.refreshRemoteCalendarCalls, 1);
      expect(stockService.getAllStocksCalls, 0);
      expect(provider.errorMessage, isNull);
    },
  );

  test('loadFromCache should show daily cache size from disk stats', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-bars-disk-stats-restore-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final tradingDay = DateTime(2026, 2, 15);
    final stock = Stock(code: '600000', name: '浦发银行', market: 1);
    final monitorData = StockMonitorData(
      stock: stock,
      ratio: 1.2,
      changePercent: 0.5,
    );

    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode([monitorData.toJson()]),
      'market_data_date': tradingDay.toIso8601String(),
      'minute_data_date': tradingDay.toIso8601String(),
      'minute_data_cache_v1': 1,
    });

    final storage1 = _buildStorageForPath(tempDir.path);
    final firstPool = _ReconnectableFakePool(
      dailyBarsByCode: {'600000': _buildDailyBars(260)},
    );
    final firstProvider = MarketDataProvider(
      pool: firstPool,
      stockService: StockService(firstPool),
      industryService: IndustryService(),
      dailyBarsFileStorage: storage1,
    );
    firstProvider.setPullbackService(PullbackService());
    await firstProvider.loadFromCache();
    await firstProvider.forceRefetchDailyBars();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('market_data_cache');
    await prefs.remove('market_data_date');
    await prefs.remove('minute_data_date');
    await prefs.remove('minute_data_cache_v1');

    final storage2 = _buildStorageForPath(tempDir.path);
    final secondPool = _ReconnectableFakePool(
      dailyBarsByCode: const <String, List<KLine>>{},
      throwOnBatchFetch: true,
    );
    final secondProvider = MarketDataProvider(
      pool: secondPool,
      stockService: StockService(secondPool),
      industryService: IndustryService(),
      dailyBarsFileStorage: storage2,
    );

    await secondProvider.loadFromCache();

    expect(secondProvider.allData, isEmpty);
    expect(secondProvider.dailyBarsCacheCount, 1);
    expect(secondProvider.dailyBarsCacheSize, isNot('<1KB'));
    expect(secondPool.batchFetchCalls, 0);
  });

  test(
    'loadFromCache should migrate legacy market_data_cache to file',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'market-snapshot-migration-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final tradingDay = DateTime(2026, 2, 15);
      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': tradingDay.toIso8601String(),
        'minute_data_date': tradingDay.toIso8601String(),
        'minute_data_cache_v1': 1,
      });

      final firstPool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
        throwOnBatchFetch: true,
      );
      final firstProvider = MarketDataProvider(
        pool: firstPool,
        stockService: StockService(firstPool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
        marketSnapshotStore: _buildMarketSnapshotStoreForPath(tempDir.path),
      );
      await firstProvider.loadFromCache();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('market_data_cache'), isNull);

      final secondPool = _ReconnectableFakePool(
        dailyBarsByCode: const <String, List<KLine>>{},
        throwOnBatchFetch: true,
      );
      final secondProvider = MarketDataProvider(
        pool: secondPool,
        stockService: StockService(secondPool),
        industryService: IndustryService(),
        dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
        marketSnapshotStore: _buildMarketSnapshotStoreForPath(tempDir.path),
      );

      await secondProvider.loadFromCache();

      expect(secondProvider.allData.length, 1);
      expect(secondProvider.allData.first.stock.code, '600000');
      expect(secondPool.batchFetchCalls, 0);
    },
  );

  test('forceRefetchDailyBars should prewarm daily macd cache', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-bars-macd-prewarm-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final stock = Stock(code: '600000', name: '浦发银行', market: 1);
    final monitorData = StockMonitorData(
      stock: stock,
      ratio: 1.2,
      changePercent: 0.5,
    );

    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode([monitorData.toJson()]),
      'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
    });

    final pool = _ReconnectableFakePool(
      dailyBarsByCode: {'600000': _buildDailyBars(260)},
    );
    final provider = MarketDataProvider(
      pool: pool,
      stockService: StockService(pool),
      industryService: IndustryService(),
      dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
    );
    provider.setPullbackService(PullbackService());

    final fileStorage = KLineFileStorage();
    fileStorage.setBaseDirPathForTesting(tempDir.path);
    final fakeRepository = _FakeDataRepository();
    final macdService = MacdIndicatorService(
      repository: fakeRepository,
      cacheStore: MacdCacheStore(storage: fileStorage),
    );
    await macdService.load();
    provider.setMacdService(macdService);

    await provider.loadFromCache();
    await provider.forceRefetchDailyBars();

    final macdFile = File(
      '${tempDir.path}/macd_cache/600000_daily_macd_cache.json',
    );
    expect(await macdFile.exists(), isTrue);
    expect(pool.batchFetchCalls, 1);
    expect(fakeRepository.getKlinesCallCount, 0);
  });

  test('recalculateBreakouts should fail fast when daily read fails', () async {
    final stock = Stock(code: '600000', name: '浦发银行', market: 1);
    final monitorData = StockMonitorData(
      stock: stock,
      ratio: 1.1,
      changePercent: 0.3,
    );
    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode([monitorData.toJson()]),
      'market_data_date': DateTime(2026, 2, 17).toIso8601String(),
      'minute_data_date': DateTime(2026, 2, 17).toIso8601String(),
      'minute_data_cache_v1': 1,
    });

    final pool = _ReconnectableFakePool(
      dailyBarsByCode: {'600000': _buildDailyBars(260)},
    );
    final readService = _FakeDailyKlineReadService()
      ..readError = const DailyKlineReadException(
        stockCode: '600000',
        reason: DailyKlineReadFailureReason.missingFile,
        message: 'missing',
      );
    final provider = MarketDataProvider(
      pool: pool,
      stockService: StockService(pool),
      industryService: IndustryService(),
      dailyKlineReadService: readService,
      dailyKlineSyncService: _FakeDailyKlineSyncService(),
    );
    provider.setBreakoutService(BreakoutService());

    await provider.loadFromCache();
    final error = await provider.recalculateBreakouts();

    expect(error, contains('日K读取失败'));
    expect(error, contains('missing'));
    expect(readService.readCallCount, greaterThanOrEqualTo(1));
  });

  test(
    'daily sync should surface returned completeness state on provider',
    () async {
      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.1,
        changePercent: 0.3,
      );
      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': DateTime(2026, 2, 17).toIso8601String(),
        'minute_data_date': DateTime(2026, 2, 17).toIso8601String(),
        'minute_data_cache_v1': 1,
      });

      final pool = _ReconnectableFakePool(dailyBarsByCode: const {});
      final syncService = _FakeDailyKlineSyncService()
        ..completenessState = DailySyncCompletenessState.finalOverride;
      final readService = _FakeDailyKlineReadService()
        ..payloadByCode['600000'] = _buildDailyBars(260);

      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyKlineReadService: readService,
        dailyKlineSyncService: syncService,
      );

      await provider.loadFromCache();
      await provider.syncDailyBarsForceFull();

      expect(
        provider.lastDailySyncCompletenessState,
        DailySyncCompletenessState.finalOverride,
      );
    },
  );

  test('daily sync should not fail when daily bars are insufficient', () async {
    final stockA = Stock(code: '600000', name: '浦发银行', market: 1);
    final stockB = Stock(code: '600001', name: '邯郸钢铁', market: 1);
    final monitorData = [
      StockMonitorData(stock: stockA, ratio: 1.1, changePercent: 0.3),
      StockMonitorData(stock: stockB, ratio: 1.0, changePercent: 0.1),
    ];
    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode(
        monitorData.map((data) => data.toJson()).toList(),
      ),
      'market_data_date': DateTime(2026, 2, 17).toIso8601String(),
      'minute_data_date': DateTime(2026, 2, 17).toIso8601String(),
      'minute_data_cache_v1': 2,
    });

    final pool = _ReconnectableFakePool(dailyBarsByCode: const {});
    final syncService = _FakeDailyKlineSyncService();
    final readService = _FakeDailyKlineReadService()
      ..readError = const DailyKlineReadException(
        stockCode: '600001',
        reason: DailyKlineReadFailureReason.insufficientBars,
        message: 'insufficient',
      );

    final provider = MarketDataProvider(
      pool: pool,
      stockService: StockService(pool),
      industryService: IndustryService(),
      dailyKlineReadService: readService,
      dailyKlineSyncService: syncService,
    );

    await provider.loadFromCache();
    await provider.syncDailyBarsForceFull();

    expect(syncService.syncCallCount, 1);
  });

  test(
    'refresh should not trigger daily sync unless explicit action is called',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.1,
        changePercent: 0.3,
      );
      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': today.toIso8601String(),
        'minute_data_date': today.toIso8601String(),
        'minute_data_cache_v1': 1,
      });

      final pool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
      );
      final syncService = _FakeDailyKlineSyncService();
      final readService = _FakeDailyKlineReadService();
      final provider = MarketDataProvider(
        pool: pool,
        stockService: StockService(pool),
        industryService: IndustryService(),
        dailyKlineReadService: readService,
        dailyKlineSyncService: syncService,
      );
      provider.setPullbackService(PullbackService());

      await provider.loadFromCache();
      await provider.refresh(silent: true);

      expect(syncService.syncCallCount, 0);
    },
  );

  test('forceRefetchDailyBars should prewarm daily ema cache', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-bars-ema-prewarm-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final stock = Stock(code: '600000', name: '浦发银行', market: 1);
    final monitorData = StockMonitorData(
      stock: stock,
      ratio: 1.2,
      changePercent: 0.5,
    );

    SharedPreferences.setMockInitialValues({
      'market_data_cache': jsonEncode([monitorData.toJson()]),
      'market_data_date': DateTime(2026, 2, 14).toIso8601String(),
    });

    final pool = _ReconnectableFakePool(
      dailyBarsByCode: {'600000': _buildDailyBars(260)},
    );
    final provider = MarketDataProvider(
      pool: pool,
      stockService: StockService(pool),
      industryService: IndustryService(),
      dailyBarsFileStorage: _buildStorageForPath(tempDir.path),
    );
    provider.setPullbackService(PullbackService());

    final fileStorage = KLineFileStorage();
    fileStorage.setBaseDirPathForTesting(tempDir.path);
    final fakeRepository = _FakeDataRepository();
    final emaService = EmaIndicatorService(
      repository: fakeRepository,
      cacheStore: EmaCacheStore(storage: fileStorage),
    );
    await emaService.load();
    provider.setEmaService(emaService);

    await provider.loadFromCache();
    await provider.forceRefetchDailyBars();

    final emaFile = File(
      '${tempDir.path}/ema_cache/600000_daily_ema_cache.json',
    );
    expect(await emaFile.exists(), isTrue);
    expect(pool.batchFetchCalls, 1);
    expect(fakeRepository.getKlinesCallCount, 0);
  });
}
