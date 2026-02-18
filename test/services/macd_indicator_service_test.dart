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
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';

class _FakeDataRepository implements DataRepository {
  Map<String, List<KLine>> klinesByStock = <String, List<KLine>>{};
  int getKlinesCallCount = 0;
  Duration getKlinesDelay = Duration.zero;
  final List<List<String>> getKlinesRequestBatches = <List<String>>[];
  int currentVersion = 1;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    getKlinesCallCount++;
    getKlinesRequestBatches.add(List<String>.from(stockCodes, growable: false));
    if (getKlinesDelay > Duration.zero) {
      await Future<void>.delayed(getKlinesDelay);
    }
    return {
      for (final code in stockCodes)
        code: (klinesByStock[code] ?? const <KLine>[])
            .where((bar) => dateRange.contains(bar.datetime))
            .toList(growable: false),
    };
  }

  @override
  Stream<DataStatus> get statusStream => const Stream.empty();

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => const Stream.empty();

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
  Future<int> getCurrentVersion() async => currentVersion;

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

class _SpyMacdCacheStore extends MacdCacheStore {
  _SpyMacdCacheStore({required super.storage});

  int saveSeriesCallCount = 0;
  int saveAllCallCount = 0;
  int loadSeriesCallCount = 0;
  int totalSavedItems = 0;
  int maxSavedBatchSize = 0;
  List<MacdCacheSeries> lastSavedBatch = const <MacdCacheSeries>[];
  final List<int?> requestedMaxConcurrentWrites = <int?>[];
  Set<String>? existingStockCodesForList;

  @override
  Future<Set<String>> listStockCodes({required KLineDataType dataType}) async {
    final existing = existingStockCodesForList;
    if (existing != null) {
      return existing;
    }
    return super.listStockCodes(dataType: dataType);
  }

  @override
  Future<MacdCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    loadSeriesCallCount++;
    return super.loadSeries(stockCode: stockCode, dataType: dataType);
  }

  @override
  Future<void> saveSeries({
    required String stockCode,
    required KLineDataType dataType,
    required MacdConfig config,
    required String sourceSignature,
    required List<MacdPoint> points,
  }) async {
    saveSeriesCallCount++;
    return super.saveSeries(
      stockCode: stockCode,
      dataType: dataType,
      config: config,
      sourceSignature: sourceSignature,
      points: points,
    );
  }

  @override
  Future<void> saveAll(
    List<MacdCacheSeries> items, {
    int? maxConcurrentWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    requestedMaxConcurrentWrites.add(maxConcurrentWrites);
    saveAllCallCount++;
    totalSavedItems += items.length;
    if (items.length > maxSavedBatchSize) {
      maxSavedBatchSize = items.length;
    }
    lastSavedBatch = List<MacdCacheSeries>.from(items, growable: false);
    return super.saveAll(
      items,
      maxConcurrentWrites: maxConcurrentWrites,
      onProgress: onProgress,
    );
  }
}

class _BlockingSaveAllMacdCacheStore extends _SpyMacdCacheStore {
  _BlockingSaveAllMacdCacheStore({required super.storage});

  final Completer<void> saveAllStarted = Completer<void>();
  final Completer<void> unblockSaveAll = Completer<void>();

  @override
  Future<void> saveAll(
    List<MacdCacheSeries> items, {
    int? maxConcurrentWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    if (!saveAllStarted.isCompleted) {
      saveAllStarted.complete();
    }
    await unblockSaveAll.future;
    return super.saveAll(
      items,
      maxConcurrentWrites: maxConcurrentWrites,
      onProgress: onProgress,
    );
  }
}

class _ConcurrencyProbeMacdService extends MacdIndicatorService {
  _ConcurrencyProbeMacdService({
    required super.repository,
    required super.cacheStore,
  });

  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<List<MacdPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
    bool persistToDisk = true,
    void Function(MacdCacheSeries series)? onSeriesComputed,
  }) async {
    _inFlight++;
    if (_inFlight > maxInFlight) {
      maxInFlight = _inFlight;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _inFlight--;
    return const <MacdPoint>[];
  }
}

class _DelayedPrewarmMacdService extends MacdIndicatorService {
  _DelayedPrewarmMacdService({
    required super.repository,
    required super.cacheStore,
    required this.delay,
  });

  final Duration delay;
  final Completer<void> firstPrewarmStarted = Completer<void>();
  int prewarmFromBarsCallCount = 0;

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
    prewarmFromBarsCallCount++;
    if (!firstPrewarmStarted.isCompleted) {
      firstPrewarmStarted.complete();
    }
    await Future<void>.delayed(delay);
    return super.prewarmFromBars(
      dataType: dataType,
      barsByStockCode: barsByStockCode,
      forceRecompute: forceRecompute,
      maxConcurrentTasks: maxConcurrentTasks,
      maxConcurrentPersistWrites: maxConcurrentPersistWrites,
      persistBatchSize: persistBatchSize,
      onProgress: onProgress,
    );
  }
}

List<KLine> _buildBars(DateTime start, int count) {
  return List.generate(count, (index) {
    final date = DateTime(start.year, start.month, start.day + index);
    final base = 10 + index * 0.03;
    return KLine(
      datetime: date,
      open: base,
      close: base + ((index % 5) - 2) * 0.06,
      high: base + 0.2,
      low: base - 0.2,
      volume: 1000 + index.toDouble(),
      amount: 10000 + index.toDouble(),
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeDataRepository repository;
  late MacdCacheStore cacheStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    tempDir = await Directory.systemTemp.createTemp('macd-indicator-service-');
    repository = _FakeDataRepository();

    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    cacheStore = MacdCacheStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'getOrComputeFromBars should compute and trim to recent months',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();

      final bars = _buildBars(DateTime(2025, 8, 1), 180);
      final points = await service.getOrComputeFromBars(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        bars: bars,
      );

      expect(points, isNotEmpty);
      expect(points.length, lessThan(bars.length));
      expect(points.first.datetime.isBefore(points.last.datetime), isTrue);
    },
  );

  test(
    'getOrComputeFromBars should reuse existing disk cache when unchanged',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();
      final bars = _buildBars(DateTime(2025, 10, 1), 100);

      await service.getOrComputeFromBars(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        bars: bars,
      );

      final cacheFile = File(
        '${tempDir.path}/macd_cache/600000_daily_macd_cache.json',
      );
      expect(await cacheFile.exists(), isTrue);
      final firstModified = await cacheFile.lastModified();

      final serviceAfterRestart = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await serviceAfterRestart.load();

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await serviceAfterRestart.getOrComputeFromBars(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        bars: bars,
      );

      final secondModified = await cacheFile.lastModified();
      expect(secondModified, firstModified);
    },
  );

  test('updateConfig should persist lightweight config payload', () async {
    final service = MacdIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await service.load();

    const newConfig = MacdConfig(
      fastPeriod: 8,
      slowPeriod: 21,
      signalPeriod: 5,
      windowMonths: 3,
    );
    await service.updateConfig(newConfig);

    final reloaded = MacdIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await reloaded.load();
    expect(reloaded.config, newConfig);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(MacdIndicatorService.configStorageKey);
    expect(raw, isNotNull);
    expect(raw!.length, lessThan(256));
  });

  test('weekly config should default to 12-month window', () async {
    final service = MacdIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await service.load();

    final weekly = service.configFor(KLineDataType.weekly);
    expect(weekly.windowMonths, 12);
  });

  test(
    'weekly config should upgrade legacy window to 12 months on load',
    () async {
      SharedPreferences.setMockInitialValues({
        MacdIndicatorService.weeklyConfigStorageKey: jsonEncode({
          'fastPeriod': 12,
          'slowPeriod': 26,
          'signalPeriod': 9,
          'windowMonths': 3,
        }),
      });

      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();

      final weekly = service.configFor(KLineDataType.weekly);
      expect(weekly.windowMonths, 12);
    },
  );

  test('updateConfigFor weekly should enforce 12-month window', () async {
    final service = MacdIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await service.load();

    await service.updateConfigFor(
      dataType: KLineDataType.weekly,
      newConfig: const MacdConfig(
        fastPeriod: 12,
        slowPeriod: 26,
        signalPeriod: 9,
        windowMonths: 6,
      ),
    );

    final reloaded = MacdIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await reloaded.load();

    expect(reloaded.configFor(KLineDataType.weekly).windowMonths, 12);
  });

  test('prewarmFromBars should process stocks concurrently', () async {
    final service = _ConcurrencyProbeMacdService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await service.load();

    final payload = <String, List<KLine>>{
      for (var i = 0; i < 6; i++)
        '60000$i': _buildBars(DateTime(2025, 10, 1), 90),
    };

    await service.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
    );

    expect(service.maxInFlight, greaterThan(1));
  });

  test(
    'prewarmFromRepository should fetch in chunks and aggregate progress',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();

      final stockCodes = <String>[
        '600000',
        '600001',
        '600002',
        '600003',
        '600004',
        '600005',
        '600006',
      ];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 90),
      };

      final progressRecords = <({int current, int total})>[];
      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
        fetchBatchSize: 3,
        onProgress: (current, total) {
          progressRecords.add((current: current, total: total));
        },
      );

      expect(repository.getKlinesCallCount, 3);
      expect(
        repository.getKlinesRequestBatches
            .map((batch) => batch.length)
            .toList(),
        <int>[3, 3, 1],
      );
      expect(progressRecords, isNotEmpty);
      expect(progressRecords.last.total, stockCodes.length * 2);
      expect(progressRecords.last.current, progressRecords.last.total);
    },
  );

  test(
    'daily prewarmFromRepository should read bars via DataRepository.getKlines',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();

      repository.klinesByStock = {
        '600000': _buildBars(DateTime(2025, 10, 1), 180),
      };

      await service.prewarmFromRepository(
        stockCodes: const <String>['600000'],
        dataType: KLineDataType.daily,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
        forceRecompute: true,
      );

      expect(repository.getKlinesCallCount, 1);
      final cacheFile = File(
        '${tempDir.path}/macd_cache/600000_daily_macd_cache.json',
      );
      expect(await cacheFile.exists(), isTrue);
    },
  );

  test(
    'prewarmFromRepository should pipeline next chunk fetch while current chunk computes',
    () async {
      final service = _DelayedPrewarmMacdService(
        repository: repository,
        cacheStore: cacheStore,
        delay: const Duration(milliseconds: 200),
      );
      await service.load();
      repository.getKlinesDelay = const Duration(milliseconds: 20);

      final stockCodes = <String>[
        '600000',
        '600001',
        '600002',
        '600003',
        '600004',
        '600005',
      ];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 90),
      };

      final prewarmFuture = service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
        fetchBatchSize: 3,
      );

      await service.firstPrewarmStarted.future;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(repository.getKlinesCallCount, 2);

      await prewarmFuture;
      expect(service.prewarmFromBarsCallCount, 2);
    },
  );

  test(
    'prewarmFromRepository should skip unchanged version with same config and stock scope',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();
      repository.currentVersion = 42;

      final stockCodes = <String>['600000', '600001', '600002'];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 90),
      };

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 1);

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 1);
    },
  );

  test(
    'prewarmFromRepository should bypass snapshot when ignoreSnapshot or forceRecompute is true',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();
      repository.currentVersion = 42;

      const stockCodes = <String>['600000'];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 120),
      };
      final range = DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1));

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.daily,
        dateRange: range,
      );
      expect(repository.getKlinesCallCount, 1);

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.daily,
        dateRange: range,
      );
      expect(repository.getKlinesCallCount, 1);

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.daily,
        dateRange: range,
        ignoreSnapshot: true,
      );
      expect(repository.getKlinesCallCount, 2);

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.daily,
        dateRange: range,
        forceRecompute: true,
      );
      expect(repository.getKlinesCallCount, 3);
    },
  );

  test(
    'prewarmFromRepository should rerun when config changes even with same data version',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();
      repository.currentVersion = 99;

      const stockCodes = <String>['600000', '600001'];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 90),
      };

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 1);

      await service.updateConfigFor(
        dataType: KLineDataType.weekly,
        newConfig: const MacdConfig(
          fastPeriod: 10,
          slowPeriod: 30,
          signalPeriod: 7,
          windowMonths: 12,
        ),
      );

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 2);
    },
  );

  test('prewarmFromBars should batch persist computed series', () async {
    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final spyStore = _SpyMacdCacheStore(storage: storage);

    final service = MacdIndicatorService(
      repository: repository,
      cacheStore: spyStore,
    );
    await service.load();

    final payload = <String, List<KLine>>{
      '600000': _buildBars(DateTime(2025, 10, 1), 90),
      '600001': _buildBars(DateTime(2025, 10, 1), 90),
      '600002': _buildBars(DateTime(2025, 10, 1), 90),
    };

    await service.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
      maxConcurrentTasks: 2,
    );

    expect(spyStore.saveAllCallCount, greaterThan(0));
    expect(spyStore.saveSeriesCallCount, 0);
    expect(spyStore.totalSavedItems, payload.length);

    for (final code in payload.keys) {
      final file = File(
        '${tempDir.path}/macd_cache/${code}_daily_macd_cache.json',
      );
      expect(await file.exists(), isTrue);
    }
  });

  test(
    'prewarmFromBars should not report 100% before disk writes finish',
    () async {
      final storage = KLineFileStorage();
      storage.setBaseDirPathForTesting(tempDir.path);
      final blockingStore = _BlockingSaveAllMacdCacheStore(storage: storage);

      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: blockingStore,
      );
      await service.load();

      final payload = <String, List<KLine>>{
        '600000': _buildBars(DateTime(2025, 10, 1), 90),
        '600001': _buildBars(DateTime(2025, 10, 1), 90),
        '600002': _buildBars(DateTime(2025, 10, 1), 90),
      };

      var latestCurrent = 0;
      var latestTotal = 0;
      var completed = false;

      final prewarmFuture = service
          .prewarmFromBars(
            dataType: KLineDataType.daily,
            barsByStockCode: payload,
            maxConcurrentTasks: 1,
            persistBatchSize: 2,
            onProgress: (current, total) {
              latestCurrent = current;
              latestTotal = total;
            },
          )
          .then((_) => completed = true);

      await blockingStore.saveAllStarted.future;

      expect(completed, isFalse);
      expect(latestTotal, greaterThan(payload.length));
      expect(latestCurrent, lessThan(latestTotal));

      blockingStore.unblockSaveAll.complete();
      await prewarmFuture;

      expect(latestCurrent, latestTotal);
    },
  );

  test('prewarmFromBars should cap saveAll batch size', () async {
    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final spyStore = _SpyMacdCacheStore(storage: storage);

    final service = MacdIndicatorService(
      repository: repository,
      cacheStore: spyStore,
    );
    await service.load();

    final payload = <String, List<KLine>>{
      for (var i = 0; i < 23; i++)
        '600${i.toString().padLeft(3, '0')}': _buildBars(
          DateTime(2025, 10, 1),
          90,
        ),
    };

    await service.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
      maxConcurrentTasks: 1,
      persistBatchSize: 5,
    );

    expect(spyStore.saveAllCallCount, greaterThan(1));
    expect(spyStore.maxSavedBatchSize, lessThanOrEqualTo(5));
    expect(spyStore.totalSavedItems, payload.length);
  });

  test(
    'prewarmFromBars should use configured persist write concurrency',
    () async {
      final storage = KLineFileStorage();
      storage.setBaseDirPathForTesting(tempDir.path);
      final spyStore = _SpyMacdCacheStore(storage: storage);

      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: spyStore,
      );
      await service.load();

      final payload = <String, List<KLine>>{
        for (var i = 0; i < 12; i++)
          '600${i.toString().padLeft(3, '0')}': _buildBars(
            DateTime(2025, 10, 1),
            90,
          ),
      };

      await service.prewarmFromBars(
        dataType: KLineDataType.weekly,
        barsByStockCode: payload,
        maxConcurrentTasks: 1,
        persistBatchSize: 4,
        maxConcurrentPersistWrites: 8,
      );

      expect(spyStore.saveAllCallCount, greaterThan(0));
      expect(spyStore.requestedMaxConcurrentWrites, isNotEmpty);
      expect(
        spyStore.requestedMaxConcurrentWrites.every((value) => value == 8),
        isTrue,
      );
    },
  );

  test(
    'prewarmFromBars should skip disk reads for stocks without cache files',
    () async {
      final storage = KLineFileStorage();
      storage.setBaseDirPathForTesting(tempDir.path);
      final spyStore = _SpyMacdCacheStore(storage: storage);
      spyStore.existingStockCodesForList = <String>{};

      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: spyStore,
      );
      await service.load();

      final payload = <String, List<KLine>>{
        for (var i = 0; i < 15; i++)
          '600${i.toString().padLeft(3, '0')}': _buildBars(
            DateTime(2025, 10, 1),
            90,
          ),
      };

      await service.prewarmFromBars(
        dataType: KLineDataType.weekly,
        barsByStockCode: payload,
        maxConcurrentTasks: 1,
      );

      expect(spyStore.loadSeriesCallCount, 0);
    },
  );

  test(
    'should persist daily and weekly configs independently with fixed weekly window',
    () async {
      final service = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();

      const dailyConfig = MacdConfig(
        fastPeriod: 8,
        slowPeriod: 21,
        signalPeriod: 5,
        windowMonths: 4,
      );
      const weeklyConfig = MacdConfig(
        fastPeriod: 10,
        slowPeriod: 30,
        signalPeriod: 7,
        windowMonths: 6,
      );

      await service.updateConfigFor(
        dataType: KLineDataType.daily,
        newConfig: dailyConfig,
      );
      await service.updateConfigFor(
        dataType: KLineDataType.weekly,
        newConfig: weeklyConfig,
      );

      final reloaded = MacdIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await reloaded.load();

      expect(reloaded.configFor(KLineDataType.daily), dailyConfig);
      expect(
        reloaded.configFor(KLineDataType.weekly),
        weeklyConfig.copyWith(windowMonths: 12),
      );
    },
  );
}
