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
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
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

class _FakeDataRepository implements DataRepository {
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

DailyKlineCacheStore _buildStorageForPath(String basePath) {
  final storage = KLineFileStorage();
  storage.setBaseDirPathForTesting(basePath);
  return DailyKlineCacheStore(storage: storage);
}

List<KLine> _buildDailyBars(int n) {
  final start = DateTime(2026, 2, 1);
  return List.generate(n, (index) {
    final dt = start.add(Duration(days: index));
    return KLine(
      datetime: dt,
      open: 10,
      close: 10.2,
      high: 10.3,
      low: 9.9,
      volume: 1000.0 + index,
      amount: 10000.0 + index,
    );
  });
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
    final macdService = MacdIndicatorService(
      repository: _FakeDataRepository(),
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
  });
}
