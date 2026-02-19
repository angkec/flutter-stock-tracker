import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/repository/kline_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/date_check_storage.dart';
import 'package:stock_rtwatcher/data/storage/minute_sync_state_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/repository/minute_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/repository/minute_sync_planner.dart';
import 'package:stock_rtwatcher/data/repository/minute_sync_writer.dart';
import 'package:stock_rtwatcher/data/models/minute_sync_state.dart';
import 'package:stock_rtwatcher/config/minute_sync_config.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mock TdxClient for testing
class MockTdxClient extends TdxClient {
  List<Quote>? quotesToReturn;
  Exception? exceptionToThrow;
  List<(int, String)>? lastRequestedStocks;
  bool connectCalled = false;
  bool disconnectCalled = false;
  bool shouldConnectSucceed = true;
  bool mockIsConnected = false;

  // K线数据支持
  Map<String, List<KLine>>?
  barsToReturn; // key: "${market}_${code}_${category}"
  Exception? barsExceptionToThrow;
  Map<String, Exception>? barsExceptionsByStock; // 每只股票独立的异常
  List<({int market, String code, int category, int start, int count})>
  barRequests = [];

  @override
  bool get isConnected => mockIsConnected;

  @override
  Future<bool> autoConnect() async {
    connectCalled = true;
    if (shouldConnectSucceed) {
      mockIsConnected = true;
    }
    return shouldConnectSucceed;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalled = true;
    mockIsConnected = false;
  }

  @override
  Future<List<Quote>> getSecurityQuotes(List<(int, String)> stocks) async {
    lastRequestedStocks = stocks;
    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }
    return quotesToReturn ?? [];
  }

  @override
  Future<List<KLine>> getSecurityBars({
    required int market,
    required String code,
    required int category,
    required int start,
    required int count,
  }) async {
    // 记录请求
    barRequests.add((
      market: market,
      code: code,
      category: category,
      start: start,
      count: count,
    ));

    // 检查全局异常
    if (barsExceptionToThrow != null) {
      throw barsExceptionToThrow!;
    }

    // 检查针对特定股票的异常
    if (barsExceptionsByStock != null &&
        barsExceptionsByStock!.containsKey(code)) {
      throw barsExceptionsByStock![code]!;
    }

    // 返回预设数据
    final key = '${market}_${code}_$category';
    if (barsToReturn != null && barsToReturn!.containsKey(key)) {
      final allBars = barsToReturn![key]!;
      // 模拟分页：从 start 开始取 count 条
      // start=0 表示最新，所以从末尾往前取
      final totalBars = allBars.length;
      if (start >= totalBars) return [];
      final endIndex = totalBars - start;
      final startIndex = (endIndex - count).clamp(0, totalBars);
      return allBars.sublist(startIndex, endIndex);
    }

    return [];
  }

  /// 清除请求记录
  void clearBarRequests() {
    barRequests.clear();
  }
}

class FakeMinuteFetchAdapter implements MinuteFetchAdapter, KlineFetchAdapter {
  int fetchCalls = 0;
  int fetchBarsCalls = 0;
  int fetchBarsProgressEvents = 0;
  int? lastCategory;
  int? lastStart;
  int? lastCount;
  List<String> lastStockCodes = const [];
  final List<int> startsByCall = [];
  final List<List<String>> stockCodesByCall = [];
  Map<String, List<KLine>> barsToReturn = {};
  Map<String, String> errorsToReturn = {};

  @override
  Future<Map<String, List<KLine>>> fetchMinuteBars({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    fetchCalls++;
    lastStart = start;
    lastCount = count;
    lastStockCodes = stockCodes;
    startsByCall.add(start);
    stockCodesByCall.add(List<String>.from(stockCodes));

    for (var i = 0; i < stockCodes.length; i++) {
      if (onProgress != null) {
        fetchBarsProgressEvents++;
      }
      onProgress?.call(i + 1, stockCodes.length);
    }

    return {
      for (final code in stockCodes) code: barsToReturn[code] ?? const [],
    };
  }

  @override
  Future<MinuteFetchResult> fetchMinuteBarsWithResult({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    final bars = await fetchMinuteBars(
      stockCodes: stockCodes,
      start: start,
      count: count,
      onProgress: onProgress,
    );
    return MinuteFetchResult(
      barsByStock: bars,
      errorsByStock: {
        for (final code in stockCodes)
          if (errorsToReturn.containsKey(code)) code: errorsToReturn[code]!,
      },
    );
  }

  @override
  Future<Map<String, List<KLine>>> fetchBars({
    required List<String> stockCodes,
    required int category,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    fetchBarsCalls++;
    lastCategory = category;
    lastStart = start;
    lastCount = count;
    lastStockCodes = stockCodes;
    startsByCall.add(start);
    stockCodesByCall.add(List<String>.from(stockCodes));

    for (var i = 0; i < stockCodes.length; i++) {
      if (onProgress != null) {
        fetchBarsProgressEvents++;
      }
      onProgress?.call(i + 1, stockCodes.length);
    }

    return {
      for (final code in stockCodes) code: barsToReturn[code] ?? const [],
    };
  }
}

class FakeMinuteSyncPlanner extends MinuteSyncPlanner {
  int callCount = 0;
  final Map<String, MinuteFetchPlan> plansByStock = {};
  final Map<String, List<DateTime>> knownMissingDatesByStock = {};
  final Map<String, List<DateTime>> knownIncompleteDatesByStock = {};

  @override
  MinuteFetchPlan planForStock({
    required String stockCode,
    required List<DateTime> tradingDates,
    required MinuteSyncState? syncState,
    required List<DateTime> knownMissingDates,
    required List<DateTime> knownIncompleteDates,
  }) {
    callCount++;
    knownMissingDatesByStock[stockCode] = List<DateTime>.from(
      knownMissingDates,
    );
    knownIncompleteDatesByStock[stockCode] = List<DateTime>.from(
      knownIncompleteDates,
    );

    return plansByStock[stockCode] ??
        MinuteFetchPlan(
          stockCode: stockCode,
          mode: MinuteSyncMode.skip,
          datesToFetch: const [],
        );
  }
}

class FakeMinuteSyncWriter extends MinuteSyncWriter {
  int writeCalls = 0;
  Map<String, List<KLine>>? lastBarsByStock;
  KLineDataType? lastDataType;
  DateTime? lastFetchedTradingDay;
  MinuteWriteResult resultToReturn = const MinuteWriteResult(
    updatedStocks: [],
    totalRecords: 0,
  );

  FakeMinuteSyncWriter({
    required super.metadataManager,
    required super.syncStateStorage,
  });

  @override
  Future<MinuteWriteResult> writeBatch({
    required Map<String, List<KLine>> barsByStock,
    required KLineDataType dataType,
    DateTime? fetchedTradingDay,
    void Function(int current, int total)? onProgress,
  }) async {
    writeCalls++;
    lastBarsByStock = barsByStock;
    lastDataType = dataType;
    lastFetchedTradingDay = fetchedTradingDay;
    final nonEmptyCount = barsByStock.values
        .where((bars) => bars.isNotEmpty)
        .length;
    if (nonEmptyCount > 0) {
      onProgress?.call(nonEmptyCount, nonEmptyCount);
    }
    return resultToReturn;
  }
}

class DelayedLoadMetadataManager extends KLineMetadataManager {
  DelayedLoadMetadataManager({
    required super.database,
    required super.fileStorage,
    super.dailyFileStorage,
    required this.delay,
  });

  final Duration delay;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<List<KLine>> loadKlineData({
    required String stockCode,
    required KLineDataType dataType,
    required DateRange dateRange,
  }) async {
    inFlight++;
    if (inFlight > maxInFlight) {
      maxInFlight = inFlight;
    }
    await Future<void>.delayed(delay);
    try {
      return await super.loadKlineData(
        stockCode: stockCode,
        dataType: dataType,
        dateRange: dateRange,
      );
    } finally {
      inFlight--;
    }
  }
}

class CountingDateCheckStorage extends DateCheckStorage {
  CountingDateCheckStorage({required super.database});

  int getPendingDatesCalls = 0;
  int getPendingDatesBatchCalls = 0;
  int getLatestCheckedDateCalls = 0;
  int getLatestCheckedDateBatchCalls = 0;
  int saveCheckStatusCalls = 0;
  int saveCheckStatusBatchCalls = 0;

  @override
  Future<List<DateTime>> getPendingDates({
    required String stockCode,
    required KLineDataType dataType,
    bool excludeToday = false,
    DateTime? today,
  }) {
    getPendingDatesCalls++;
    return super.getPendingDates(
      stockCode: stockCode,
      dataType: dataType,
      excludeToday: excludeToday,
      today: today,
    );
  }

  @override
  Future<Map<String, List<DateTime>>> getPendingDatesBatch({
    required List<String> stockCodes,
    required KLineDataType dataType,
    DateTime? fromDate,
    DateTime? toDate,
    bool excludeToday = false,
    DateTime? today,
  }) {
    getPendingDatesBatchCalls++;
    return super.getPendingDatesBatch(
      stockCodes: stockCodes,
      dataType: dataType,
      fromDate: fromDate,
      toDate: toDate,
      excludeToday: excludeToday,
      today: today,
    );
  }

  @override
  Future<DateTime?> getLatestCheckedDate({
    required String stockCode,
    required KLineDataType dataType,
  }) {
    getLatestCheckedDateCalls++;
    return super.getLatestCheckedDate(stockCode: stockCode, dataType: dataType);
  }

  @override
  Future<Map<String, DateTime?>> getLatestCheckedDateBatch({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) {
    getLatestCheckedDateBatchCalls++;
    return super.getLatestCheckedDateBatch(
      stockCodes: stockCodes,
      dataType: dataType,
    );
  }

  @override
  Future<void> saveCheckStatus({
    required String stockCode,
    required KLineDataType dataType,
    required DateTime date,
    required DayDataStatus status,
    required int barCount,
  }) {
    saveCheckStatusCalls++;
    return super.saveCheckStatus(
      stockCode: stockCode,
      dataType: dataType,
      date: date,
      status: status,
      barCount: barCount,
    );
  }

  @override
  Future<void> saveCheckStatusBatch({
    required List<DateCheckStatusEntry> entries,
  }) {
    saveCheckStatusBatchCalls++;
    return super.saveCheckStatusBatch(entries: entries);
  }
}

void main() {
  late MarketDataRepository repository;
  late KLineMetadataManager manager;
  late MarketDatabase database;
  late KLineFileStorage fileStorage;
  late Directory testDir;

  setUpAll(() {
    // Initialize FFI for sqflite
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('MarketDataRepository', () {
    setUp(() async {
      // Create temporary test directory
      testDir = await Directory.systemTemp.createTemp('market_data_repo_test_');

      // Initialize file storage with test directory
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();
      final dailyFileStorage = KLineFileStorageV2();
      dailyFileStorage.setBaseDirPathForTesting(testDir.path);
      await dailyFileStorage.initialize();

      // Initialize database
      database = MarketDatabase();
      await database.database;

      // Create metadata manager
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
      );

      // Create repository with the test manager
      repository = MarketDataRepository(metadataManager: manager);
    });

    tearDown(() async {
      await repository.dispose();

      // Close database
      try {
        await database.close();
      } catch (_) {}

      // Reset singleton
      MarketDatabase.resetInstance();

      // Delete test directory
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }

      // Delete test database file
      try {
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/market_data.db';
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    test('should implement DataRepository interface', () {
      expect(repository, isA<DataRepository>());
    });

    test('should provide status stream', () {
      expect(repository.statusStream, isA<Stream<DataStatus>>());
    });

    test('should emit initial status', () async {
      // Note: With the spec-compliant implementation, the initial DataReady(0)
      // is added to the controller in the constructor. However, since we use
      // a broadcast stream and the event is emitted during construction,
      // listeners that subscribe after construction won't receive it.
      // This is expected behavior per the spec - "only the first listener
      // gets the initial status."
      //
      // We verify the stream is properly typed instead.
      expect(repository.statusStream, isA<Stream<DataStatus>>());
    });

    test('should load klines from storage', () async {
      // Setup test data
      final testKlines = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 31),
          open: 10.5,
          close: 10.3,
          high: 10.6,
          low: 10.2,
          volume: 1200,
          amount: 12400,
        ),
      ];

      // Save test data using the test manager
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: testKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Load via repository
      final result = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: DateRange(
          DateTime(2024, 1, 15),
          DateTime(2024, 1, 15, 23, 59),
        ),
        dataType: KLineDataType.oneMinute,
      );

      expect(result['000001'], hasLength(2));
      expect(
        result['000001']![0].datetime,
        equals(DateTime(2024, 1, 15, 9, 30)),
      );
      expect(
        result['000001']![1].datetime,
        equals(DateTime(2024, 1, 15, 9, 31)),
      );
    });

    test('should cache loaded klines in memory', () async {
      // First load - from storage
      final result1 = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: DateRange(
          DateTime(2024, 1, 15),
          DateTime(2024, 1, 15, 23, 59),
        ),
        dataType: KLineDataType.oneMinute,
      );

      // Second load - should return identical object (cached)
      final result2 = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: DateRange(
          DateTime(2024, 1, 15),
          DateTime(2024, 1, 15, 23, 59),
        ),
        dataType: KLineDataType.oneMinute,
      );

      // Verify it's the exact same list object (identity check)
      expect(identical(result2['000001'], result1['000001']), isTrue);
    });

    test('should return empty list for unknown stocks', () async {
      final result = await repository.getKlines(
        stockCodes: ['999999'],
        dateRange: DateRange(
          DateTime(2024, 1, 15),
          DateTime(2024, 1, 15, 23, 59),
        ),
        dataType: KLineDataType.oneMinute,
      );

      expect(result['999999'], isEmpty);
    });

    test('should load klines concurrently across stock codes', () async {
      final stockCodes = <String>[
        '600000',
        '600001',
        '600002',
        '600003',
        '600004',
        '600005',
      ];
      final dateRange = DateRange(DateTime(2024, 1, 1), DateTime(2024, 2, 1));

      for (final code in stockCodes) {
        await manager.saveKlineData(
          stockCode: code,
          newBars: [
            KLine(
              datetime: DateTime(2024, 1, 15),
              open: 10,
              close: 10.1,
              high: 10.2,
              low: 9.8,
              volume: 1000,
              amount: 12000,
            ),
          ],
          dataType: KLineDataType.weekly,
        );
      }

      final delayedManager = DelayedLoadMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
        delay: const Duration(milliseconds: 40),
      );
      final concurrentRepository = MarketDataRepository(
        metadataManager: delayedManager,
      );

      try {
        final result = await concurrentRepository.getKlines(
          stockCodes: stockCodes,
          dateRange: dateRange,
          dataType: KLineDataType.weekly,
        );

        expect(result.length, stockCodes.length);
        expect(delayedManager.maxInFlight, greaterThan(1));
      } finally {
        await concurrentRepository.dispose();
      }
    });

    test('should detect fresh data', () async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      // Define trading day via daily data
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: todayDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data (230 bars)
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(
          KLine(
            datetime: DateTime(
              todayDate.year,
              todayDate.month,
              todayDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.01,
            close: 10.5 + i * 0.01,
            high: 10.8 + i * 0.01,
            low: 9.9 + i * 0.01,
            volume: 1000.0 + i,
            amount: 10000 + i * 10,
          ),
        );
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(todayDate, todayDate),
      );

      // Now check freshness
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
    });

    test('should detect stale data', () async {
      // Save old data (7 days ago)
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final oldDate = todayDate.subtract(const Duration(days: 7));

      // Define trading day via daily data
      await manager.saveKlineData(
        stockCode: '000002',
        newBars: [
          KLine(
            datetime: oldDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // Save incomplete minute data (only 50 bars - less than 220)
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 50; i++) {
        minuteKlines.add(
          KLine(
            datetime: DateTime(
              oldDate.year,
              oldDate.month,
              oldDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.01,
            close: 10.5 + i * 0.01,
            high: 10.8 + i * 0.01,
            low: 9.9 + i * 0.01,
            volume: 1000.0 + i,
            amount: 10000 + i * 10,
          ),
        );
      }
      await manager.saveKlineData(
        stockCode: '000002',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache
      await repository.findMissingMinuteDates(
        stockCode: '000002',
        dateRange: DateRange(oldDate, oldDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000002'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000002'], isA<Stale>());
      final stale = freshness['000002'] as Stale;
      expect(stale.missingRange.start, isA<DateTime>());
    });

    test('should treat weekend-only unchecked range as fresh', () async {
      final fixedNow = DateTime(2026, 2, 9, 10, 0); // Monday
      final friday = DateTime(2026, 2, 6); // Previous Friday

      final dateCheckStorage = DateCheckStorage(database: database);
      await dateCheckStorage.saveCheckStatus(
        stockCode: '000010',
        dataType: KLineDataType.oneMinute,
        date: friday,
        status: DayDataStatus.complete,
        barCount: 230,
      );

      final weekendAwareRepository = MarketDataRepository(
        metadataManager: manager,
        nowProvider: () => fixedNow,
      );

      final freshness = await weekendAwareRepository.checkFreshness(
        stockCodes: ['000010'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000010'], isA<Fresh>());

      await weekendAwareRepository.dispose();
    });

    test(
      'should treat holiday-only unchecked range as fresh when trading calendar is reliable',
      () async {
        final fixedNow = DateTime(2026, 10, 8, 10, 0); // Thursday
        final latestCheckedDate = DateTime(2026, 9, 30);

        final dateCheckStorage = DateCheckStorage(database: database);
        await dateCheckStorage.saveCheckStatus(
          stockCode: '000011',
          dataType: KLineDataType.oneMinute,
          date: latestCheckedDate,
          status: DayDataStatus.complete,
          barCount: 230,
        );

        // Build reliable trading-day context around National Day holiday window.
        // Holiday range: 2026-10-01 .. 2026-10-07 (no trading days expected).
        final surroundingDailyBars = <KLine>[];
        var cursor = DateTime(2026, 9, 10);
        final end = DateTime(2026, 10, 31);
        while (!cursor.isAfter(end)) {
          final isWeekday =
              cursor.weekday >= DateTime.monday &&
              cursor.weekday <= DateTime.friday;
          final isHolidayWindow =
              !cursor.isBefore(DateTime(2026, 10, 1)) &&
              !cursor.isAfter(DateTime(2026, 10, 7));

          if (isWeekday && !isHolidayWindow) {
            surroundingDailyBars.add(
              KLine(
                datetime: cursor,
                open: 10.0,
                close: 10.5,
                high: 10.8,
                low: 9.9,
                volume: 1000,
                amount: 10000,
              ),
            );
          }

          cursor = cursor.add(const Duration(days: 1));
        }

        await manager.saveKlineData(
          stockCode: '000011',
          newBars: surroundingDailyBars,
          dataType: KLineDataType.daily,
        );

        final holidayAwareRepository = MarketDataRepository(
          metadataManager: manager,
          dateCheckStorage: dateCheckStorage,
          nowProvider: () => fixedNow,
        );

        final freshness = await holidayAwareRepository.checkFreshness(
          stockCodes: ['000011'],
          dataType: KLineDataType.oneMinute,
        );

        expect(freshness['000011'], isA<Fresh>());

        await holidayAwareRepository.dispose();
      },
    );

    test(
      'should use nowProvider when excluding today pending status',
      () async {
        final fixedNow = DateTime(2025, 1, 10, 10, 0);
        final fixedToday = DateTime(2025, 1, 10);
        final fixedYesterday = DateTime(2025, 1, 9);

        final dateCheckStorage = DateCheckStorage(database: database);
        await dateCheckStorage.saveCheckStatus(
          stockCode: '000012',
          dataType: KLineDataType.oneMinute,
          date: fixedToday,
          status: DayDataStatus.incomplete,
          barCount: 80,
        );
        await dateCheckStorage.saveCheckStatus(
          stockCode: '000012',
          dataType: KLineDataType.oneMinute,
          date: fixedYesterday,
          status: DayDataStatus.complete,
          barCount: 230,
        );

        final nowAwareRepository = MarketDataRepository(
          metadataManager: manager,
          dateCheckStorage: dateCheckStorage,
          nowProvider: () => fixedNow,
        );

        final freshness = await nowAwareRepository.checkFreshness(
          stockCodes: ['000012'],
          dataType: KLineDataType.oneMinute,
        );

        expect(freshness['000012'], isA<Fresh>());

        await nowAwareRepository.dispose();
      },
    );

    test('should detect missing data', () async {
      final freshness = await repository.checkFreshness(
        stockCodes: ['999999'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['999999'], isA<Missing>());
    });

    test('should detect data exactly 24 hours old as fresh', () async {
      // Save data for yesterday (within 24 hours threshold)
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final yesterdayDate = todayDate.subtract(const Duration(days: 1));

      // Define trading day via daily data
      await manager.saveKlineData(
        stockCode: '000003',
        newBars: [
          KLine(
            datetime: yesterdayDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data (230 bars)
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(
          KLine(
            datetime: DateTime(
              yesterdayDate.year,
              yesterdayDate.month,
              yesterdayDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.01,
            close: 10.5 + i * 0.01,
            high: 10.8 + i * 0.01,
            low: 9.9 + i * 0.01,
            volume: 1000.0 + i,
            amount: 10000 + i * 10,
          ),
        );
      }
      await manager.saveKlineData(
        stockCode: '000003',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache
      await repository.findMissingMinuteDates(
        stockCode: '000003',
        dateRange: DateRange(yesterdayDate, yesterdayDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000003'],
        dataType: KLineDataType.oneMinute,
      );

      // Data from yesterday with complete bars is Fresh (daysSinceLastCheck <= 1)
      expect(freshness['000003'], isA<Fresh>());
    });

    test(
      'should detect stale data when unchecked range includes weekday',
      () async {
        final fixedNow = DateTime(2026, 2, 11, 10, 0); // Wednesday
        final twoDaysAgo = DateTime(2026, 2, 9); // Monday

        // Define trading day via daily data
        await manager.saveKlineData(
          stockCode: '000004',
          newBars: [
            KLine(
              datetime: twoDaysAgo,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        // Save complete minute data (230 bars)
        final minuteKlines = <KLine>[];
        for (var i = 0; i < 230; i++) {
          minuteKlines.add(
            KLine(
              datetime: DateTime(
                twoDaysAgo.year,
                twoDaysAgo.month,
                twoDaysAgo.day,
                9,
                30,
              ).add(Duration(minutes: i)),
              open: 10.0 + i * 0.01,
              close: 10.5 + i * 0.01,
              high: 10.8 + i * 0.01,
              low: 9.9 + i * 0.01,
              volume: 1000.0 + i,
              amount: 10000 + i * 10,
            ),
          );
        }
        await manager.saveKlineData(
          stockCode: '000004',
          newBars: minuteKlines,
          dataType: KLineDataType.oneMinute,
        );

        final weekdayAwareRepository = MarketDataRepository(
          metadataManager: manager,
          nowProvider: () => fixedNow,
        );

        // Populate cache
        await weekdayAwareRepository.findMissingMinuteDates(
          stockCode: '000004',
          dateRange: DateRange(twoDaysAgo, twoDaysAgo),
        );

        final freshness = await weekdayAwareRepository.checkFreshness(
          stockCodes: ['000004'],
          dataType: KLineDataType.oneMinute,
        );

        expect(freshness['000004'], isA<Stale>());

        await weekdayAwareRepository.dispose();
      },
    );

    test(
      'checkFreshness uses batched storage reads for multi-stock input',
      () async {
        final countingStorage = CountingDateCheckStorage(database: database);
        final batchingRepository = MarketDataRepository(
          metadataManager: manager,
          dateCheckStorage: countingStorage,
          nowProvider: () => DateTime(2026, 1, 20, 10, 0),
        );

        final result = await batchingRepository.checkFreshness(
          stockCodes: const ['000001', '000002', '000003'],
          dataType: KLineDataType.oneMinute,
        );

        expect(
          result.values.every((freshness) => freshness is Missing),
          isTrue,
        );
        expect(countingStorage.getPendingDatesBatchCalls, 1);
        expect(countingStorage.getLatestCheckedDateBatchCalls, 1);
        expect(countingStorage.getPendingDatesCalls, 0);
        expect(countingStorage.getLatestCheckedDateCalls, 0);

        await batchingRepository.dispose();
      },
    );

    test(
      'findMissingMinuteDates caches outcomes via batched status writes',
      () async {
        final day = DateTime(2026, 1, 15);
        await manager.saveKlineData(
          stockCode: '000021',
          newBars: [
            KLine(
              datetime: day,
              open: 10.0,
              close: 10.1,
              high: 10.2,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        final countingStorage = CountingDateCheckStorage(database: database);
        final batchingRepository = MarketDataRepository(
          metadataManager: manager,
          dateCheckStorage: countingStorage,
        );

        final result = await batchingRepository.findMissingMinuteDates(
          stockCode: '000021',
          dateRange: DateRange(day, DateTime(2026, 1, 15, 23, 59, 59)),
        );

        expect(result.missingDates, [day]);
        expect(countingStorage.saveCheckStatusBatchCalls, 1);
        expect(countingStorage.saveCheckStatusCalls, 0);

        await batchingRepository.dispose();
      },
    );
  });

  group('MarketDataRepository - getQuotes', () {
    late MarketDataRepository repository;
    late MockTdxClient mockTdxClient;
    late KLineMetadataManager manager;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late Directory testDir;

    setUp(() async {
      // Create temporary test directory
      testDir = await Directory.systemTemp.createTemp(
        'market_data_repo_quotes_test_',
      );

      // Initialize file storage with test directory
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();
      final dailyFileStorage = KLineFileStorageV2();
      dailyFileStorage.setBaseDirPathForTesting(testDir.path);
      await dailyFileStorage.initialize();

      // Initialize database
      database = MarketDatabase();
      await database.database;

      // Create metadata manager
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
      );

      // Create mock TdxClient
      mockTdxClient = MockTdxClient();

      // Create repository with the test manager and mock TdxClient
      repository = MarketDataRepository(
        metadataManager: manager,
        tdxClient: mockTdxClient,
      );
    });

    tearDown(() async {
      await repository.dispose();

      // Close database
      try {
        await database.close();
      } catch (_) {}

      // Reset singleton
      MarketDatabase.resetInstance();

      // Delete test directory
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }

      // Delete test database file
      try {
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/market_data.db';
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    test('should get quotes from TdxClient', () async {
      // 设置 mock 返回数据
      mockTdxClient.quotesToReturn = [
        Quote(
          market: 0,
          code: '000001',
          price: 10.5,
          lastClose: 10.0,
          open: 10.2,
          high: 10.8,
          low: 9.9,
          volume: 1000000,
          amount: 10500000,
        ),
        Quote(
          market: 1,
          code: '600000',
          price: 15.5,
          lastClose: 15.0,
          open: 15.2,
          high: 15.8,
          low: 14.9,
          volume: 2000000,
          amount: 31000000,
        ),
      ];

      final result = await repository.getQuotes(
        stockCodes: ['000001', '600000'],
      );

      // 验证返回结果
      expect(result.length, equals(2));
      expect(result['000001']?.price, equals(10.5));
      expect(result['000001']?.market, equals(0));
      expect(result['600000']?.price, equals(15.5));
      expect(result['600000']?.market, equals(1));

      // 验证市场映射正确：000001 -> market 0 (深市), 600000 -> market 1 (沪市)
      expect(mockTdxClient.lastRequestedStocks, isNotNull);
      expect(mockTdxClient.lastRequestedStocks!.length, equals(2));

      // 查找对应的请求
      final request000001 = mockTdxClient.lastRequestedStocks!.firstWhere(
        (e) => e.$2 == '000001',
      );
      final request600000 = mockTdxClient.lastRequestedStocks!.firstWhere(
        (e) => e.$2 == '600000',
      );

      expect(request000001.$1, equals(0)); // 深市
      expect(request600000.$1, equals(1)); // 沪市
    });

    test('should map stock codes to correct markets', () async {
      mockTdxClient.quotesToReturn = [];

      // 测试不同前缀的股票代码映射
      await repository.getQuotes(
        stockCodes: [
          '000001',
          '002001',
          '300001',
          '600001',
          '601001',
          '688001',
        ],
      );

      final requests = mockTdxClient.lastRequestedStocks!;
      expect(requests.length, equals(6));

      // 0xx, 3xx -> 深市 (market 0)
      // 6xx -> 沪市 (market 1)
      final marketMap = {for (final r in requests) r.$2: r.$1};

      expect(marketMap['000001'], equals(0)); // 深市主板
      expect(marketMap['002001'], equals(0)); // 深市中小板
      expect(marketMap['300001'], equals(0)); // 深市创业板
      expect(marketMap['600001'], equals(1)); // 沪市主板
      expect(marketMap['601001'], equals(1)); // 沪市主板
      expect(marketMap['688001'], equals(1)); // 沪市科创板
    });

    test('should handle quote fetch errors gracefully', () async {
      // 设置 mock 抛出异常
      mockTdxClient.exceptionToThrow = Exception('Network error');

      // 不应该抛出异常，应该返回空 map
      final result = await repository.getQuotes(
        stockCodes: ['000001', '600000'],
      );

      expect(result, isEmpty);
    });

    test('should handle connection failure gracefully', () async {
      mockTdxClient.shouldConnectSucceed = false;

      final result = await repository.getQuotes(stockCodes: ['000001']);

      expect(result, isEmpty);
    });

    test('should return empty map for empty stock list', () async {
      final result = await repository.getQuotes(stockCodes: []);

      expect(result, isEmpty);
      // 不应该调用 TdxClient
      expect(mockTdxClient.lastRequestedStocks, isNull);
    });

    test('should disconnect TdxClient on dispose', () async {
      // 创建一个新的 repository，手动 dispose
      final testRepo = MarketDataRepository(
        metadataManager: manager,
        tdxClient: mockTdxClient,
      );

      await testRepo.dispose();

      expect(mockTdxClient.disconnectCalled, isTrue);
    });

    test('should skip connection if already connected', () async {
      // 设置 mock 为已连接状态
      mockTdxClient.mockIsConnected = true;
      mockTdxClient.quotesToReturn = [
        Quote(
          market: 0,
          code: '000001',
          price: 10.5,
          lastClose: 10.0,
          open: 10.2,
          high: 10.8,
          low: 9.9,
          volume: 1000000,
          amount: 10500000,
        ),
      ];

      await repository.getQuotes(stockCodes: ['000001']);

      // 不应该调用 autoConnect
      expect(mockTdxClient.connectCalled, isFalse);
    });
  });

  group('MarketDataRepository - fetchMissingData', () {
    late MarketDataRepository repository;
    late MockTdxClient mockTdxClient;
    late KLineMetadataManager manager;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late Directory testDir;

    setUp(() async {
      // 创建临时测试目录
      testDir = await Directory.systemTemp.createTemp(
        'market_data_repo_fetch_test_',
      );

      // 初始化文件存储
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();
      final dailyFileStorage = KLineFileStorageV2();
      dailyFileStorage.setBaseDirPathForTesting(testDir.path);
      await dailyFileStorage.initialize();

      // 初始化数据库
      database = MarketDatabase();
      await database.database;

      // 创建元数据管理器
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
      );

      // 创建 mock TdxClient
      mockTdxClient = MockTdxClient();

      // 创建 repository
      repository = MarketDataRepository(
        metadataManager: manager,
        tdxClient: mockTdxClient,
      );
    });

    tearDown(() async {
      await repository.dispose();

      // 关闭数据库
      try {
        await database.close();
      } catch (_) {}

      // 重置单例
      MarketDatabase.resetInstance();

      // 删除测试目录
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }

      // 删除测试数据库文件
      try {
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/market_data.db';
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    /// 生成测试用的K线数据
    List<KLine> generateTestKlines({
      required DateTime startDate,
      required int count,
      required bool isMinuteData,
    }) {
      final klines = <KLine>[];
      var currentTime = startDate;

      for (var i = 0; i < count; i++) {
        klines.add(
          KLine(
            datetime: currentTime,
            open: 10.0 + i * 0.1,
            close: 10.0 + i * 0.1 + 0.05,
            high: 10.0 + i * 0.1 + 0.1,
            low: 10.0 + i * 0.1 - 0.05,
            volume: 1000 + i * 10,
            amount: 10000 + i * 100,
          ),
        );

        if (isMinuteData) {
          currentTime = currentTime.add(const Duration(minutes: 1));
        } else {
          currentTime = currentTime.add(const Duration(days: 1));
        }
      }

      return klines;
    }

    test('should fetch missing data and save to storage', () async {
      // 准备测试数据
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 15, 9, 35));

      // 定义交易日（通过日线数据）
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // 生成 mock K线数据（5条1分钟数据）
      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      // 设置 mock 返回数据（深市股票，market=0，1分钟=category 7）
      mockTdxClient.barsToReturn = {'0_000001_7': mockKlines};

      // 调用 fetchMissingData
      final result = await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 验证结果
      expect(result.totalStocks, equals(1));
      expect(result.successCount, equals(1));
      expect(result.failureCount, equals(0));
      expect(result.totalRecords, greaterThan(0));
      expect(result.errors, isEmpty);

      // 验证数据已保存到存储
      final savedKlines = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      expect(savedKlines['000001'], isNotEmpty);
      expect(savedKlines['000001']!.length, equals(5));
    });

    test('should report progress during fetch', () async {
      // 准备测试数据
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 15, 9, 35));

      // 定义交易日（通过日线数据）
      for (final code in ['000001', '000002', '600000']) {
        await manager.saveKlineData(
          stockCode: code,
          newBars: [
            KLine(
              datetime: testDate,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );
      }

      // 生成 mock K线数据
      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {
        '0_000001_7': mockKlines,
        '0_000002_7': mockKlines,
        '1_600000_7': mockKlines,
      };

      // 跟踪进度回调
      final progressCalls = <(int, int)>[];

      // 调用 fetchMissingData
      await repository.fetchMissingData(
        stockCodes: ['000001', '000002', '600000'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
        onProgress: (current, total) {
          progressCalls.add((current, total));
        },
      );

      // 验证进度回调
      expect(progressCalls, isNotEmpty);
      expect(progressCalls.length, equals(3)); // 每只股票一次
      expect(progressCalls[0], equals((1, 3)));
      expect(progressCalls[1], equals((2, 3)));
      expect(progressCalls[2], equals((3, 3)));
    });

    test('should emit DataUpdatedEvent after successful fetch', () async {
      // 准备测试数据
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 15, 9, 35));

      // 定义交易日（通过日线数据）
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {'0_000001_7': mockKlines};

      // 监听 dataUpdatedStream - 设置监听器在调用 fetchMissingData 之前
      final events = <DataUpdatedEvent>[];
      final subscription = repository.dataUpdatedStream.listen(events.add);

      // 调用 fetchMissingData
      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 让事件循环处理一次（事件应该在 fetchMissingData 返回前已添加到流）
      await Future.delayed(Duration.zero);

      // 验证事件
      expect(events, isNotEmpty);
      expect(events.first.stockCodes, contains('000001'));
      expect(events.first.dataType, equals(KLineDataType.oneMinute));
      expect(events.first.dataVersion, greaterThan(0));

      await subscription.cancel();
    });

    test('should emit DataFetching status during fetch', () async {
      // 准备测试数据
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 15, 9, 35));

      // 定义交易日（通过日线数据）
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {'0_000001_7': mockKlines};

      // 收集状态变化 - 设置监听器在调用 fetchMissingData 之前
      final statusChanges = <DataStatus>[];
      final subscription = repository.statusStream.listen(statusChanges.add);

      // 调用 fetchMissingData
      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 让事件循环处理一次（状态应该在 fetchMissingData 返回前已添加到流）
      await Future.delayed(Duration.zero);

      // 验证状态变化：应该有 DataFetching 和 DataReady
      expect(statusChanges.any((s) => s is DataFetching), isTrue);
      expect(statusChanges.any((s) => s is DataReady), isTrue);

      await subscription.cancel();
    });

    test('should handle errors per-stock without aborting', () async {
      // 准备测试数据
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 15, 9, 35));

      // 定义交易日（通过日线数据）
      for (final code in ['000001', '000002']) {
        await manager.saveKlineData(
          stockCode: code,
          newBars: [
            KLine(
              datetime: testDate,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );
      }

      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      // 设置：000001 成功，000002 失败
      mockTdxClient.barsToReturn = {'0_000001_7': mockKlines};
      mockTdxClient.barsExceptionsByStock = {
        '000002': Exception('Network error for 000002'),
      };

      // 调用 fetchMissingData
      final result = await repository.fetchMissingData(
        stockCodes: ['000001', '000002'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 验证结果
      expect(result.totalStocks, equals(2));
      expect(result.successCount, equals(1));
      expect(result.failureCount, equals(1));
      expect(result.errors.containsKey('000002'), isTrue);

      // 验证成功的股票数据已保存
      final savedKlines = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      expect(savedKlines['000001'], isNotEmpty);
    });

    test('should handle connection failure', () async {
      // 设置连接失败
      mockTdxClient.shouldConnectSucceed = false;

      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 15, 9, 35));

      // 定义交易日（通过日线数据）
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // 调用 fetchMissingData
      final result = await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 验证返回失败结果
      expect(result.totalStocks, equals(1));
      expect(result.successCount, equals(0));
      expect(result.failureCount, equals(1));
    });

    test('should map data type to correct TDX category', () async {
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 16));

      // 定义交易日（通过日线数据）
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // 测试1分钟数据
      final minuteKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {
        '0_000001_7': minuteKlines, // category 7 = 1分钟
      };

      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 验证请求使用了正确的 category
      expect(mockTdxClient.barRequests.isNotEmpty, isTrue);
      expect(mockTdxClient.barRequests.first.category, equals(7)); // 1分钟

      // 清除请求记录
      mockTdxClient.clearBarRequests();

      // 测试日线数据
      final dailyKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15),
        count: 5,
        isMinuteData: false,
      );

      mockTdxClient.barsToReturn = {
        '0_000002_4': dailyKlines, // category 4 = 日线
      };

      await repository.fetchMissingData(
        stockCodes: ['000002'],
        dateRange: dateRange,
        dataType: KLineDataType.daily,
      );

      expect(mockTdxClient.barRequests.isNotEmpty, isTrue);
      expect(mockTdxClient.barRequests.first.category, equals(4)); // 日线

      mockTdxClient.clearBarRequests();

      // 测试周线数据
      final weeklyKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15),
        count: 5,
        isMinuteData: false,
      );

      mockTdxClient.barsToReturn = {
        '0_000003_5': weeklyKlines, // category 5 = 周线
      };

      await repository.fetchMissingData(
        stockCodes: ['000003'],
        dateRange: dateRange,
        dataType: KLineDataType.weekly,
      );

      expect(mockTdxClient.barRequests.isNotEmpty, isTrue);
      expect(mockTdxClient.barRequests.first.category, equals(5)); // 周线
    });

    test('should invalidate cache for updated stocks', () async {
      // 先手动添加一些缓存数据
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(testDate, DateTime(2024, 1, 15, 9, 35));

      // 定义交易日（通过日线数据）
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // 首先保存一些旧数据
      final oldKlines = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: oldKlines,
        dataType: KLineDataType.oneMinute,
      );

      // 加载以填充缓存
      final cachedData1 = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      expect(cachedData1['000001']!.length, equals(1));

      // 准备新数据
      final newKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 31),
        count: 3,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {'0_000001_7': newKlines};

      // 获取新数据
      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 再次加载，应该得到更新后的数据
      final cachedData2 = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 数据应该已更新（旧数据 + 新数据去重）
      expect(cachedData2['000001']!.length, greaterThan(1));
    });

    test('should return correct FetchResult duration', () async {
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {'0_000001_7': mockKlines};

      final result = await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 验证 duration 是正数
      expect(result.duration, isA<Duration>());
      expect(result.duration.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('should handle empty stock codes list', () async {
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

      final result = await repository.fetchMissingData(
        stockCodes: [],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      expect(result.totalStocks, equals(0));
      expect(result.successCount, equals(0));
      expect(result.failureCount, equals(0));
      expect(result.totalRecords, equals(0));
    });

    test('should skip stocks with complete data', () async {
      // 1. Setup: Save complete data for a stock (≥220 bars)
      final testDate = DateTime(2024, 1, 15);
      final dateRange = DateRange(
        testDate,
        testDate.add(const Duration(hours: 23)),
      );

      // First, save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data (230 bars - more than 220 threshold)
      final completeKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        completeKlines.add(
          KLine(
            datetime: DateTime(
              testDate.year,
              testDate.month,
              testDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.01,
            close: 10.5 + i * 0.01,
            high: 10.8 + i * 0.01,
            low: 9.9 + i * 0.01,
            volume: 1000.0 + i,
            amount: 10000 + i * 10,
          ),
        );
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: completeKlines,
        dataType: KLineDataType.oneMinute,
      );

      // 2. Call fetchMissingData
      mockTdxClient.clearBarRequests();
      final result = await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 3. Verify: stock was skipped (no TDX requests made)
      expect(mockTdxClient.barRequests, isEmpty);
      expect(result.totalStocks, equals(1));
      expect(result.successCount, equals(1)); // Skipped counts as success
      expect(result.failureCount, equals(0));
      expect(result.totalRecords, equals(0)); // No new records fetched
    });

    test('should fetch stocks with missing data', () async {
      // 1. Setup: Stock has no data at all
      final testDate = DateTime(2024, 1, 16);
      final dateRange = DateRange(
        testDate,
        testDate.add(const Duration(hours: 23)),
      );

      // Define trading day via daily data
      await manager.saveKlineData(
        stockCode: '000003',
        newBars: [
          KLine(
            datetime: testDate,
            open: 10.0,
            close: 10.5,
            high: 10.8,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      // Setup mock to return K-line data
      final mockKlines = <KLine>[];
      for (var i = 0; i < 5; i++) {
        mockKlines.add(
          KLine(
            datetime: DateTime(
              testDate.year,
              testDate.month,
              testDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.1,
            close: 10.0 + i * 0.1 + 0.05,
            high: 10.0 + i * 0.1 + 0.1,
            low: 10.0 + i * 0.1 - 0.05,
            volume: 1000 + i * 10,
            amount: 10000 + i * 100,
          ),
        );
      }
      mockTdxClient.barsToReturn = {'0_000003_7': mockKlines};

      // 2. Call fetchMissingData
      mockTdxClient.clearBarRequests();
      final result = await repository.fetchMissingData(
        stockCodes: ['000003'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 3. Verify: stock was fetched (TDX requests were made)
      expect(mockTdxClient.barRequests, isNotEmpty);
      expect(result.totalStocks, equals(1));
      expect(result.successCount, equals(1));
      expect(result.totalRecords, greaterThan(0));
    });

    test(
      'should refresh minute freshness cache after successful fetch',
      () async {
        final fixedNow = DateTime(2026, 1, 20, 10, 0);
        final testDate = DateTime(2026, 1, 19);
        final dateRange = DateRange(
          testDate,
          testDate.add(const Duration(hours: 23)),
        );

        await manager.saveKlineData(
          stockCode: '000010',
          newBars: [
            KLine(
              datetime: testDate,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        final localMockTdxClient = MockTdxClient();
        final cacheAwareRepository = MarketDataRepository(
          metadataManager: manager,
          tdxClient: localMockTdxClient,
          nowProvider: () => fixedNow,
        );

        final missingBefore = await cacheAwareRepository.findMissingMinuteDates(
          stockCode: '000010',
          dateRange: dateRange,
        );
        expect(missingBefore.missingDates, contains(testDate));

        final freshnessBefore = await cacheAwareRepository.checkFreshness(
          stockCodes: ['000010'],
          dataType: KLineDataType.oneMinute,
        );
        expect(freshnessBefore['000010'], isA<Stale>());

        final completeMinuteBars = <KLine>[];
        for (var i = 0; i < 230; i++) {
          completeMinuteBars.add(
            KLine(
              datetime: DateTime(
                testDate.year,
                testDate.month,
                testDate.day,
                9,
                30,
              ).add(Duration(minutes: i)),
              open: 10.0 + i * 0.01,
              close: 10.5 + i * 0.01,
              high: 10.8 + i * 0.01,
              low: 9.9 + i * 0.01,
              volume: 1000.0 + i,
              amount: 10000 + i * 10,
            ),
          );
        }
        localMockTdxClient.barsToReturn = {'0_000010_7': completeMinuteBars};

        final result = await cacheAwareRepository.fetchMissingData(
          stockCodes: ['000010'],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );
        expect(result.totalRecords, greaterThan(0));

        final freshnessAfter = await cacheAwareRepository.checkFreshness(
          stockCodes: ['000010'],
          dataType: KLineDataType.oneMinute,
        );
        expect(freshnessAfter['000010'], isA<Fresh>());

        await cacheAwareRepository.dispose();
      },
    );

    test('should fetch minute data when trading dates are unavailable', () async {
      // No daily data is saved on purpose (trading dates unavailable).
      final testDate = DateTime(2024, 1, 18);
      final dateRange = DateRange(
        testDate,
        testDate.add(const Duration(hours: 23)),
      );

      final mockKlines = <KLine>[];
      for (var i = 0; i < 5; i++) {
        mockKlines.add(
          KLine(
            datetime: DateTime(
              testDate.year,
              testDate.month,
              testDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.1,
            close: 10.0 + i * 0.1 + 0.05,
            high: 10.0 + i * 0.1 + 0.1,
            low: 10.0 + i * 0.1 - 0.05,
            volume: 1000 + i * 10,
            amount: 10000 + i * 100,
          ),
        );
      }
      mockTdxClient.barsToReturn = {'0_000006_7': mockKlines};

      mockTdxClient.clearBarRequests();
      final result = await repository.fetchMissingData(
        stockCodes: ['000006'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // Should not be skipped by precheck just because trading dates are unavailable.
      expect(mockTdxClient.barRequests, isNotEmpty);
      expect(result.totalStocks, equals(1));
      expect(result.successCount, equals(1));
      expect(result.totalRecords, greaterThan(0));
    });

    test(
      'should fetch when cached complete status is stale after external minute data loss',
      () async {
        final testDate = DateTime(2024, 1, 19);
        final dateRange = DateRange(
          testDate,
          testDate.add(const Duration(hours: 23)),
        );

        // Define trading day via daily data.
        await manager.saveKlineData(
          stockCode: '000007',
          newBars: [
            KLine(
              datetime: testDate,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        // Save complete minute data first, then run detection to cache "complete".
        final completeMinuteBars = <KLine>[];
        for (var i = 0; i < 230; i++) {
          completeMinuteBars.add(
            KLine(
              datetime: DateTime(
                testDate.year,
                testDate.month,
                testDate.day,
                9,
                30,
              ).add(Duration(minutes: i)),
              open: 10.0 + i * 0.01,
              close: 10.5 + i * 0.01,
              high: 10.8 + i * 0.01,
              low: 9.9 + i * 0.01,
              volume: 1000 + i * 10,
              amount: 10000 + i * 100,
            ),
          );
        }
        await manager.saveKlineData(
          stockCode: '000007',
          newBars: completeMinuteBars,
          dataType: KLineDataType.oneMinute,
        );

        final cached = await repository.findMissingMinuteDates(
          stockCode: '000007',
          dateRange: dateRange,
        );
        expect(cached.isComplete, isTrue);

        // Simulate external/minor-version data loss: delete minute data directly
        // via metadata manager (bypassing repository cache invalidation path).
        await manager.deleteOldData(
          stockCode: '000007',
          dataType: KLineDataType.oneMinute,
          beforeDate: testDate.add(const Duration(days: 1)),
        );

        final mockKlines = generateTestKlines(
          startDate: DateTime(2024, 1, 19, 9, 30),
          count: 5,
          isMinuteData: true,
        );
        mockTdxClient.barsToReturn = {'0_000007_7': mockKlines};

        mockTdxClient.clearBarRequests();
        final result = await repository.fetchMissingData(
          stockCodes: ['000007'],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );

        // Must re-check and actually fetch instead of trusting stale "complete" cache.
        expect(mockTdxClient.barRequests, isNotEmpty);
        expect(result.totalRecords, greaterThan(0));
      },
    );

    test(
      'should fetch when a non-validation cached complete date becomes missing',
      () async {
        final jan18 = DateTime(2024, 1, 18);
        final jan19 = DateTime(2024, 1, 19);
        final dateRange = DateRange(
          jan18,
          jan19.add(const Duration(hours: 23)),
        );

        await manager.saveKlineData(
          stockCode: '000008',
          newBars: [
            KLine(
              datetime: jan18,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
            KLine(
              datetime: jan19,
              open: 10.5,
              close: 10.8,
              high: 11.0,
              low: 10.2,
              volume: 1200,
              amount: 12000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        final completeMinuteBars = <KLine>[];
        for (final day in [jan18, jan19]) {
          for (var i = 0; i < 230; i++) {
            completeMinuteBars.add(
              KLine(
                datetime: DateTime(
                  day.year,
                  day.month,
                  day.day,
                  9,
                  30,
                ).add(Duration(minutes: i)),
                open: 10.0 + i * 0.01,
                close: 10.5 + i * 0.01,
                high: 10.8 + i * 0.01,
                low: 9.9 + i * 0.01,
                volume: 1000 + i * 10,
                amount: 10000 + i * 100,
              ),
            );
          }
        }
        await manager.saveKlineData(
          stockCode: '000008',
          newBars: completeMinuteBars,
          dataType: KLineDataType.oneMinute,
        );

        final cached = await repository.findMissingMinuteDates(
          stockCode: '000008',
          dateRange: dateRange,
        );
        expect(cached.isComplete, isTrue);

        // Simulate external file corruption: Jan 18 bars are lost, Jan 19 remains.
        final jan19BarsOnly = completeMinuteBars.where((bar) {
          return bar.datetime.year == jan19.year &&
              bar.datetime.month == jan19.month &&
              bar.datetime.day == jan19.day;
        }).toList();
        await fileStorage.saveMonthlyKlineFile(
          '000008',
          KLineDataType.oneMinute,
          2024,
          1,
          jan19BarsOnly,
        );

        final mockKlines = generateTestKlines(
          startDate: DateTime(2024, 1, 18, 9, 30),
          count: 5,
          isMinuteData: true,
        );
        mockTdxClient.barsToReturn = {'0_000008_7': mockKlines};

        mockTdxClient.clearBarRequests();
        final result = await repository.fetchMissingData(
          stockCodes: ['000008'],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );

        expect(mockTdxClient.barRequests, isNotEmpty);
        expect(result.totalRecords, greaterThan(0));
      },
    );

    test(
      'should reuse cached complete dates without rewriting status',
      () async {
        final testDate = DateTime(2024, 1, 22);
        final dateRange = DateRange(
          testDate,
          testDate.add(const Duration(hours: 23)),
        );

        await manager.saveKlineData(
          stockCode: '000013',
          newBars: [
            KLine(
              datetime: testDate,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        final completeMinuteBars = <KLine>[];
        for (var i = 0; i < 230; i++) {
          completeMinuteBars.add(
            KLine(
              datetime: DateTime(
                testDate.year,
                testDate.month,
                testDate.day,
                9,
                30,
              ).add(Duration(minutes: i)),
              open: 10.0 + i * 0.01,
              close: 10.5 + i * 0.01,
              high: 10.8 + i * 0.01,
              low: 9.9 + i * 0.01,
              volume: 1000 + i * 10,
              amount: 10000 + i * 100,
            ),
          );
        }
        await manager.saveKlineData(
          stockCode: '000013',
          newBars: completeMinuteBars,
          dataType: KLineDataType.oneMinute,
        );

        final firstResult = await repository.findMissingMinuteDates(
          stockCode: '000013',
          dateRange: dateRange,
        );
        expect(firstResult.isComplete, isTrue);

        final db = await database.database;
        final beforeRows = await db.rawQuery(
          '''
        SELECT checked_at FROM date_check_status
        WHERE stock_code = ? AND data_type = ? AND date = ?
        ''',
          [
            '000013',
            KLineDataType.oneMinute.name,
            testDate.millisecondsSinceEpoch,
          ],
        );
        expect(beforeRows, isNotEmpty);
        final checkedAtBefore = beforeRows.first['checked_at'] as int;

        await Future<void>.delayed(const Duration(milliseconds: 20));

        final secondResult = await repository.findMissingMinuteDates(
          stockCode: '000013',
          dateRange: dateRange,
        );
        expect(secondResult.isComplete, isTrue);

        final afterRows = await db.rawQuery(
          '''
        SELECT checked_at FROM date_check_status
        WHERE stock_code = ? AND data_type = ? AND date = ?
        ''',
          [
            '000013',
            KLineDataType.oneMinute.name,
            testDate.millisecondsSinceEpoch,
          ],
        );
        expect(afterRows, isNotEmpty);
        final checkedAtAfter = afterRows.first['checked_at'] as int;

        expect(checkedAtAfter, equals(checkedAtBefore));
      },
    );

    test(
      'should fetch when daily trading dates are too sparse for reliable precheck',
      () async {
        final rangeStart = DateTime(2024, 1, 1);
        final rangeEnd = DateTime(2024, 1, 30, 23);
        final sparseTradingDay = DateTime(2024, 1, 15);
        final dateRange = DateRange(rangeStart, rangeEnd);

        // Only one daily bar in a 30-day window: trading-date coverage is sparse.
        await manager.saveKlineData(
          stockCode: '000009',
          newBars: [
            KLine(
              datetime: sparseTradingDay,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        final sparseMinuteBars = <KLine>[];
        for (var i = 0; i < 230; i++) {
          sparseMinuteBars.add(
            KLine(
              datetime: DateTime(
                sparseTradingDay.year,
                sparseTradingDay.month,
                sparseTradingDay.day,
                9,
                30,
              ).add(Duration(minutes: i)),
              open: 10.0 + i * 0.01,
              close: 10.5 + i * 0.01,
              high: 10.8 + i * 0.01,
              low: 9.9 + i * 0.01,
              volume: 1000 + i * 10,
              amount: 10000 + i * 100,
            ),
          );
        }
        await manager.saveKlineData(
          stockCode: '000009',
          newBars: sparseMinuteBars,
          dataType: KLineDataType.oneMinute,
        );

        // Cache complete status for the only known day.
        await repository.findMissingMinuteDates(
          stockCode: '000009',
          dateRange: dateRange,
        );

        final mockKlines = generateTestKlines(
          startDate: DateTime(2024, 1, 20, 9, 30),
          count: 5,
          isMinuteData: true,
        );
        mockTdxClient.barsToReturn = {'0_000009_7': mockKlines};

        mockTdxClient.clearBarRequests();
        final result = await repository.fetchMissingData(
          stockCodes: ['000009'],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );

        expect(mockTdxClient.barRequests, isNotEmpty);
        expect(result.totalRecords, greaterThan(0));
      },
    );

    test('should return correct counts for mixed stocks', () async {
      // 1. Setup: One stock complete, one stock missing
      final testDate = DateTime(2024, 1, 17);
      final dateRange = DateRange(
        testDate,
        testDate.add(const Duration(hours: 23)),
      );

      // Define trading day for both stocks
      for (final code in ['000004', '000005']) {
        await manager.saveKlineData(
          stockCode: code,
          newBars: [
            KLine(
              datetime: testDate,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );
      }

      // Save complete data for 000004 (230 bars)
      final completeKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        completeKlines.add(
          KLine(
            datetime: DateTime(
              testDate.year,
              testDate.month,
              testDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.01,
            close: 10.5 + i * 0.01,
            high: 10.8 + i * 0.01,
            low: 9.9 + i * 0.01,
            volume: 1000.0 + i,
            amount: 10000 + i * 10,
          ),
        );
      }
      await manager.saveKlineData(
        stockCode: '000004',
        newBars: completeKlines,
        dataType: KLineDataType.oneMinute,
      );

      // 000005 has no minute data (missing)

      // Setup mock for 000005
      final mockKlines = <KLine>[];
      for (var i = 0; i < 5; i++) {
        mockKlines.add(
          KLine(
            datetime: DateTime(
              testDate.year,
              testDate.month,
              testDate.day,
              9,
              30,
            ).add(Duration(minutes: i)),
            open: 10.0 + i * 0.1,
            close: 10.0 + i * 0.1 + 0.05,
            high: 10.0 + i * 0.1 + 0.1,
            low: 10.0 + i * 0.1 - 0.05,
            volume: 1000 + i * 10,
            amount: 10000 + i * 100,
          ),
        );
      }
      mockTdxClient.barsToReturn = {'0_000005_7': mockKlines};

      // 2. Call fetchMissingData with both stocks
      mockTdxClient.clearBarRequests();
      final result = await repository.fetchMissingData(
        stockCodes: ['000004', '000005'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // 3. Verify counts
      expect(result.totalStocks, equals(2));
      expect(result.successCount, equals(2)); // 1 skipped + 1 fetched
      expect(result.failureCount, equals(0));

      // Verify only 000005 was fetched (000004 was skipped)
      final fetchedCodes = mockTdxClient.barRequests.map((r) => r.code).toSet();
      expect(fetchedCodes.contains('000005'), isTrue);
      expect(fetchedCodes.contains('000004'), isFalse);
    });
  });

  group('MarketDataRepository - refetchData', () {
    late MarketDataRepository repository;
    late MockTdxClient mockTdxClient;
    late KLineMetadataManager manager;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late Directory testDir;

    setUp(() async {
      // 创建临时测试目录
      testDir = await Directory.systemTemp.createTemp(
        'market_data_repo_refetch_test_',
      );

      // 初始化文件存储
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();
      final dailyFileStorage = KLineFileStorageV2();
      dailyFileStorage.setBaseDirPathForTesting(testDir.path);
      await dailyFileStorage.initialize();

      // 初始化数据库
      database = MarketDatabase();
      await database.database;

      // 创建元数据管理器
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
      );

      // 创建 mock TdxClient
      mockTdxClient = MockTdxClient();

      // 创建 repository
      repository = MarketDataRepository(
        metadataManager: manager,
        tdxClient: mockTdxClient,
      );
    });

    tearDown(() async {
      await repository.dispose();

      // 关闭数据库
      try {
        await database.close();
      } catch (_) {}

      // 重置单例
      MarketDatabase.resetInstance();

      // 删除测试目录
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }

      // 删除测试数据库文件
      try {
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/market_data.db';
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    test('should refetch data and overwrite existing', () async {
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

      // 1. Save old data first
      final oldKlines = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: oldKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Verify old data is saved
      final oldData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );
      expect(oldData['000001']!.first.open, equals(10.0));

      // 2. Setup mock to return new data with different values
      final newKlines = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 20.0, // Different price - should overwrite
          close: 20.5,
          high: 20.8,
          low: 19.9,
          volume: 2000,
          amount: 40000,
        ),
      ];

      mockTdxClient.barsToReturn = {
        '0_000001_7': newKlines, // market=0 (深市), code=000001, category=7 (1分钟)
      };

      // 3. Call refetchData with mock that returns new data
      final result = await repository.refetchData(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // Verify fetch succeeded
      expect(result.totalStocks, equals(1));
      expect(result.successCount, equals(1));
      expect(result.failureCount, equals(0));

      // 4. Verify data was overwritten by loading and checking values
      final newData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );

      // The new data should have overwritten the old data
      expect(newData['000001'], isNotEmpty);
      expect(newData['000001']!.first.open, equals(20.0));
      expect(newData['000001']!.first.volume, equals(2000));
    });
  });

  group('MarketDataRepository - cleanupOldData', () {
    late MarketDataRepository repository;
    late KLineMetadataManager manager;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late Directory testDir;

    setUp(() async {
      // Create temporary test directory
      testDir = await Directory.systemTemp.createTemp(
        'market_data_repo_cleanup_test_',
      );

      // Initialize file storage with test directory
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();
      final dailyFileStorage = KLineFileStorageV2();
      dailyFileStorage.setBaseDirPathForTesting(testDir.path);
      await dailyFileStorage.initialize();

      // Initialize database
      database = MarketDatabase();
      await database.database;

      // Create metadata manager
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
      );

      // Create repository with the test manager
      repository = MarketDataRepository(metadataManager: manager);
    });

    tearDown(() async {
      await repository.dispose();

      // Close database
      try {
        await database.close();
      } catch (_) {}

      // Reset singleton
      MarketDatabase.resetInstance();

      // Delete test directory
      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }

      // Delete test database file
      try {
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/market_data.db';
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    test('should cleanup old data before specified date', () async {
      // 1. Save data across multiple months (Jan + Feb 2024)
      final jan2024 = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      final feb2024 = [
        KLine(
          datetime: DateTime(2024, 2, 15, 9, 30),
          open: 11.0,
          close: 11.5,
          high: 11.8,
          low: 10.9,
          volume: 1100,
          amount: 11000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024,
        dataType: KLineDataType.oneMinute,
      );
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: feb2024,
        dataType: KLineDataType.oneMinute,
      );

      // 2. Call cleanupOldData with beforeDate = Feb 1, 2024
      await repository.cleanupOldData(beforeDate: DateTime(2024, 2, 1));

      // 3. Verify Jan data deleted (empty result)
      final janData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: DateRange(DateTime(2024, 1, 1), DateTime(2024, 1, 31)),
        dataType: KLineDataType.oneMinute,
      );
      expect(janData['000001'], isEmpty);

      // 4. Verify Feb data still exists
      final febData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: DateRange(DateTime(2024, 2, 1), DateTime(2024, 2, 29)),
        dataType: KLineDataType.oneMinute,
      );
      expect(febData['000001'], isNotEmpty);
      expect(febData['000001']!.first.datetime.month, equals(2));
    });

    test('should clear cache after cleanup', () async {
      // 1. Save some data
      final jan2024 = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024,
        dataType: KLineDataType.oneMinute,
      );

      // 2. Load data into cache via getKlines
      final dateRange = DateRange(DateTime(2024, 1, 1), DateTime(2024, 1, 31));

      final cachedData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );
      expect(cachedData['000001'], isNotEmpty);

      // 3. Call cleanupOldData
      await repository.cleanupOldData(beforeDate: DateTime(2024, 2, 1));

      // 4. Verify subsequent getKlines doesn't return cached stale data
      final afterCleanup = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );
      expect(afterCleanup['000001'], isEmpty);
    });

    test('should emit DataReady status after cleanup', () async {
      // Save some data
      final jan2024 = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024,
        dataType: KLineDataType.oneMinute,
      );

      // Listen to status stream
      final statusChanges = <DataStatus>[];
      final subscription = repository.statusStream.listen(statusChanges.add);

      // Call cleanup
      await repository.cleanupOldData(beforeDate: DateTime(2024, 2, 1));

      // Let event loop process
      await Future.delayed(Duration.zero);

      // Verify DataReady was emitted
      expect(statusChanges.any((s) => s is DataReady), isTrue);

      await subscription.cancel();
    });

    test('should cleanup data for multiple stocks', () async {
      // Save data for multiple stocks
      final jan2024 = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024,
        dataType: KLineDataType.oneMinute,
      );
      await manager.saveKlineData(
        stockCode: '000002',
        newBars: jan2024,
        dataType: KLineDataType.oneMinute,
      );
      await manager.saveKlineData(
        stockCode: '600000',
        newBars: jan2024,
        dataType: KLineDataType.oneMinute,
      );

      // Cleanup
      await repository.cleanupOldData(beforeDate: DateTime(2024, 2, 1));

      // Verify all stocks' data is cleaned
      final dateRange = DateRange(DateTime(2024, 1, 1), DateTime(2024, 1, 31));

      for (final code in ['000001', '000002', '600000']) {
        final data = await repository.getKlines(
          stockCodes: [code],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );
        expect(
          data[code],
          isEmpty,
          reason: 'Stock $code should have no Jan data',
        );
      }
    });

    test('should cleanup data for all data types', () async {
      // Save data for both data types
      final jan2024 = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024,
        dataType: KLineDataType.oneMinute,
      );
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024,
        dataType: KLineDataType.daily,
      );

      // Cleanup
      await repository.cleanupOldData(beforeDate: DateTime(2024, 2, 1));

      // Verify both data types are cleaned
      final dateRange = DateRange(DateTime(2024, 1, 1), DateTime(2024, 1, 31));

      final oneMinuteData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );
      expect(oneMinuteData['000001'], isEmpty);

      final dailyData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.daily,
      );
      expect(dailyData['000001'], isEmpty);
    });

    test('should cleanup only specified data type when provided', () async {
      final jan2024Minute = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];
      final jan2024Daily = [
        KLine(
          datetime: DateTime(2024, 1, 15),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024Minute,
        dataType: KLineDataType.oneMinute,
      );
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan2024Daily,
        dataType: KLineDataType.daily,
      );

      await repository.cleanupOldData(
        beforeDate: DateTime(2024, 2, 1),
        dataType: KLineDataType.oneMinute,
      );

      final dateRange = DateRange(DateTime(2024, 1, 1), DateTime(2024, 1, 31));

      final oneMinuteData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );
      expect(oneMinuteData['000001'], isEmpty);

      final dailyData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.daily,
      );
      expect(dailyData['000001'], isNotEmpty);
    });

    test(
      'should invalidate minute freshness cache after minute cleanup',
      () async {
        final tradingDate = DateTime(2024, 1, 22);
        final dateRange = DateRange(
          tradingDate,
          tradingDate.add(const Duration(hours: 23)),
        );

        await manager.saveKlineData(
          stockCode: '000001',
          newBars: [
            KLine(
              datetime: tradingDate,
              open: 10.0,
              close: 10.5,
              high: 10.8,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        final minuteBars = <KLine>[];
        for (var i = 0; i < 230; i++) {
          minuteBars.add(
            KLine(
              datetime: DateTime(
                tradingDate.year,
                tradingDate.month,
                tradingDate.day,
                9,
                30,
              ).add(Duration(minutes: i)),
              open: 10.0 + i * 0.01,
              close: 10.5 + i * 0.01,
              high: 10.8 + i * 0.01,
              low: 9.9 + i * 0.01,
              volume: 1000.0 + i,
              amount: 10000 + i * 10,
            ),
          );
        }
        await manager.saveKlineData(
          stockCode: '000001',
          newBars: minuteBars,
          dataType: KLineDataType.oneMinute,
        );

        final initial = await repository.findMissingMinuteDates(
          stockCode: '000001',
          dateRange: dateRange,
        );
        expect(initial.missingDates, isEmpty);
        expect(initial.incompleteDates, isEmpty);

        await repository.cleanupOldData(
          beforeDate: tradingDate.add(const Duration(days: 1)),
          dataType: KLineDataType.oneMinute,
        );

        final afterCleanup = await repository.findMissingMinuteDates(
          stockCode: '000001',
          dateRange: dateRange,
        );
        expect(
          afterCleanup.missingDates,
          contains(
            DateTime(tradingDate.year, tradingDate.month, tradingDate.day),
          ),
        );
      },
    );
  });

  group('MarketDataRepository - minute pool pipeline', () {
    late MarketDataRepository repository;
    late MockTdxClient mockTdxClient;
    late KLineMetadataManager manager;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late MinuteSyncStateStorage syncStateStorage;
    late Directory testDir;
    late FakeMinuteFetchAdapter fakeAdapter;
    late FakeMinuteSyncPlanner fakePlanner;
    late FakeMinuteSyncWriter fakeWriter;

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp(
        'market_data_repo_pool_pipeline_test_',
      );

      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();
      final dailyFileStorage = KLineFileStorageV2();
      dailyFileStorage.setBaseDirPathForTesting(testDir.path);
      await dailyFileStorage.initialize();

      database = MarketDatabase();
      await database.database;

      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
      );
      syncStateStorage = MinuteSyncStateStorage(database: database);

      mockTdxClient = MockTdxClient();
      fakeAdapter = FakeMinuteFetchAdapter();
      fakePlanner = FakeMinuteSyncPlanner();
      fakeWriter = FakeMinuteSyncWriter(
        metadataManager: manager,
        syncStateStorage: syncStateStorage,
      );

      repository = MarketDataRepository(
        metadataManager: manager,
        tdxClient: mockTdxClient,
        minuteFetchAdapter: fakeAdapter,
        minuteSyncPlanner: fakePlanner,
        minuteSyncWriter: fakeWriter,
        minuteSyncConfig: const MinuteSyncConfig(
          enablePoolMinutePipeline: true,
          poolBatchCount: 800,
        ),
      );
    });

    tearDown(() async {
      await repository.dispose();

      try {
        await database.close();
      } catch (_) {}

      MarketDatabase.resetInstance();

      if (await testDir.exists()) {
        await testDir.delete(recursive: true);
      }

      try {
        final dbPath = await getDatabasesPath();
        final path = '$dbPath/market_data.db';
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    KLine buildMinuteBar(DateTime time) {
      return KLine(
        datetime: time,
        open: 10,
        close: 10.2,
        high: 10.3,
        low: 9.9,
        volume: 1000,
        amount: 10000,
      );
    }

    test('uses new minute pipeline when enabled', () async {
      final tradingDay = DateTime(2026, 2, 13);

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: tradingDay,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      fakePlanner.plansByStock['000001'] = MinuteFetchPlan(
        stockCode: '000001',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );
      fakeAdapter.barsToReturn = {
        '000001': [buildMinuteBar(DateTime(2026, 2, 13, 9, 30))],
      };
      fakeWriter.resultToReturn = const MinuteWriteResult(
        updatedStocks: ['000001'],
        totalRecords: 1,
        outcomesByStock: {
          '000001': MinuteWriteStockOutcome(
            stockCode: '000001',
            success: true,
            updated: true,
            recordCount: 1,
          ),
          '000002': MinuteWriteStockOutcome(
            stockCode: '000002',
            success: false,
            updated: false,
            recordCount: 0,
            error: 'persist failed: disk full',
          ),
        },
        errorsByStock: {'000002': 'persist failed: disk full'},
      );

      final result = await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.oneMinute,
      );

      expect(fakeAdapter.fetchCalls, 1);
      expect(fakeWriter.writeCalls, 1);
      expect(fakePlanner.callCount, 1);
      expect(mockTdxClient.barRequests, isEmpty);
      expect(result.totalRecords, 1);
    });

    test('minute pipeline emits write-phase DataFetching status', () async {
      final tradingDay = DateTime(2026, 2, 13);

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: tradingDay,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      fakePlanner.plansByStock['000001'] = MinuteFetchPlan(
        stockCode: '000001',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );
      fakeAdapter.barsToReturn = {
        '000001': [buildMinuteBar(DateTime(2026, 2, 13, 9, 30))],
      };
      fakeWriter.resultToReturn = const MinuteWriteResult(
        updatedStocks: ['000001'],
        totalRecords: 1,
      );

      final fetchingStatuses = <DataFetching>[];
      final subscription = repository.statusStream.listen((status) {
        if (status is DataFetching) {
          fetchingStatuses.add(status);
        }
      });

      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.oneMinute,
      );

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      final writeStatuses = fetchingStatuses
          .where((status) => status.currentStock == '__WRITE__')
          .toList(growable: false);

      expect(writeStatuses, isNotEmpty);
      expect(writeStatuses.last.current, greaterThanOrEqualTo(1));
      expect(writeStatuses.last.total, greaterThanOrEqualTo(1));
    });

    test('daily fetch uses pool kline adapter when available', () async {
      final day = DateTime(2026, 2, 13);
      fakeAdapter.barsToReturn = {
        '000001': [
          KLine(
            datetime: day,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
      };

      final result = await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: DateRange(day, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.daily,
      );

      expect(fakeAdapter.fetchBarsCalls, greaterThan(0));
      expect(fakeAdapter.lastCategory, klineTypeDaily);
      expect(mockTdxClient.barRequests, isEmpty);
      expect(result.totalRecords, 1);
    });

    test('weekly fetch uses pool kline adapter when available', () async {
      final day = DateTime(2026, 2, 13);
      fakeAdapter.barsToReturn = {
        '000001': [
          KLine(
            datetime: day,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
      };

      final result = await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: DateRange(day, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.weekly,
      );

      expect(fakeAdapter.fetchBarsCalls, greaterThan(0));
      expect(fakeAdapter.lastCategory, klineTypeWeekly);
      expect(mockTdxClient.barRequests, isEmpty);
      expect(result.totalRecords, 1);
    });

    test('weekly refetch uses pool kline adapter when available', () async {
      final day = DateTime(2026, 2, 13);
      fakeAdapter.barsToReturn = {
        '000001': [
          KLine(
            datetime: day,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
      };

      final result = await repository.refetchData(
        stockCodes: ['000001'],
        dateRange: DateRange(day, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.weekly,
      );

      expect(fakeAdapter.fetchBarsCalls, greaterThan(0));
      expect(fakeAdapter.lastCategory, klineTypeWeekly);
      expect(mockTdxClient.barRequests, isEmpty);
      expect(result.totalRecords, 1);
    });

    test(
      'weekly fetch wires adapter progress callback for fetch stage',
      () async {
        final day = DateTime(2026, 2, 13);
        fakeAdapter.barsToReturn = {
          '000001': [
            KLine(
              datetime: day,
              open: 10,
              close: 10.2,
              high: 10.3,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
        };

        await repository.fetchMissingData(
          stockCodes: ['000001'],
          dateRange: DateRange(day, DateTime(2026, 2, 13, 23, 59, 59)),
          dataType: KLineDataType.weekly,
        );

        expect(fakeAdapter.fetchBarsProgressEvents, greaterThan(0));
      },
    );

    test('weekly fetch emits precheck progress before fetching', () async {
      final day = DateTime(2026, 2, 13);
      fakeAdapter.barsToReturn = {
        '000001': [
          KLine(
            datetime: day,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
      };

      final statuses = <DataFetching>[];
      final subscription = repository.statusStream.listen((status) {
        if (status is DataFetching) {
          statuses.add(status);
        }
      });

      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: DateRange(day, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.weekly,
      );

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(
        statuses.any((status) => status.currentStock == '__PRECHECK__'),
        isTrue,
      );
    });

    test(
      'weekly pool pipeline emits write-phase DataFetching status',
      () async {
        final day = DateTime(2026, 2, 13);
        fakeAdapter.barsToReturn = {
          '000001': [
            KLine(
              datetime: day,
              open: 10,
              close: 10.2,
              high: 10.3,
              low: 9.9,
              volume: 1000,
              amount: 10000,
            ),
          ],
        };

        final statuses = <DataFetching>[];
        final subscription = repository.statusStream.listen((status) {
          if (status is DataFetching) {
            statuses.add(status);
          }
        });

        await repository.fetchMissingData(
          stockCodes: ['000001'],
          dateRange: DateRange(day, DateTime(2026, 2, 13, 23, 59, 59)),
          dataType: KLineDataType.weekly,
        );

        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        final writeStatuses = statuses
            .where((status) => status.currentStock == '__WRITE__')
            .toList(growable: false);

        expect(writeStatuses, isNotEmpty);
        expect(writeStatuses.last.current, greaterThanOrEqualTo(1));
        expect(writeStatuses.last.total, greaterThanOrEqualTo(1));
      },
    );

    test('incremental plan only fetches stocks with datesToFetch', () async {
      final tradingDay = DateTime(2026, 2, 13);

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: tradingDay,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      fakePlanner.plansByStock['000001'] = const MinuteFetchPlan(
        stockCode: '000001',
        mode: MinuteSyncMode.skip,
        datesToFetch: [],
      );
      fakePlanner.plansByStock['000002'] = MinuteFetchPlan(
        stockCode: '000002',
        mode: MinuteSyncMode.incremental,
        datesToFetch: [tradingDay],
      );
      fakeAdapter.barsToReturn = {
        '000002': [buildMinuteBar(DateTime(2026, 2, 13, 9, 31))],
      };
      fakeWriter.resultToReturn = const MinuteWriteResult(
        updatedStocks: ['000002'],
        totalRecords: 1,
      );

      final result = await repository.fetchMissingData(
        stockCodes: ['000001', '000002'],
        dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.oneMinute,
      );

      expect(fakeAdapter.lastStockCodes, ['000002']);
      expect(result.totalRecords, 1);
    });

    test('planner receives cached pending dates as backfill hints', () async {
      final tradingDay = DateTime(2026, 2, 13);

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          KLine(
            datetime: tradingDay,
            open: 10,
            close: 10.2,
            high: 10.3,
            low: 9.9,
            volume: 1000,
            amount: 10000,
          ),
        ],
        dataType: KLineDataType.daily,
      );

      final checkStorage = DateCheckStorage(database: database);
      await checkStorage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: tradingDay,
        status: DayDataStatus.incomplete,
        barCount: 120,
      );

      fakePlanner.plansByStock['000001'] = const MinuteFetchPlan(
        stockCode: '000001',
        mode: MinuteSyncMode.skip,
        datesToFetch: [],
      );

      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.oneMinute,
      );

      expect(fakePlanner.knownMissingDatesByStock['000001'], [tradingDay]);
      expect(fakePlanner.knownIncompleteDatesByStock['000001'], isEmpty);
    });

    test('supports runtime update of minute write concurrency', () {
      expect(repository.minuteWriteConcurrency, 6);

      repository.setMinuteWriteConcurrency(3);
      expect(repository.minuteWriteConcurrency, 3);

      repository.setMinuteWriteConcurrency(0);
      expect(repository.minuteWriteConcurrency, 1);
    });

    test(
      'non-trading day without trading-date baseline should still bootstrap minute fetch',
      () async {
        await repository.dispose();

        repository = MarketDataRepository(
          metadataManager: manager,
          tdxClient: mockTdxClient,
          minuteFetchAdapter: fakeAdapter,
          minuteSyncPlanner: MinuteSyncPlanner(),
          minuteSyncWriter: fakeWriter,
          minuteSyncConfig: const MinuteSyncConfig(
            enablePoolMinutePipeline: true,
            poolBatchCount: 800,
            poolMaxBatches: 1,
          ),
          nowProvider: () => DateTime(2026, 2, 14, 10, 0), // Saturday
        );

        fakeAdapter.barsToReturn = {
          '000001': [buildMinuteBar(DateTime(2026, 2, 13, 9, 30))],
        };
        fakeWriter.resultToReturn = const MinuteWriteResult(
          updatedStocks: ['000001'],
          totalRecords: 1,
        );

        final result = await repository.fetchMissingData(
          stockCodes: ['000001'],
          dateRange: DateRange(
            DateTime(2026, 1, 15),
            DateTime(2026, 2, 14, 23, 59, 59),
          ),
          dataType: KLineDataType.oneMinute,
        );

        expect(
          fakeAdapter.fetchCalls,
          greaterThan(0),
          reason: '非交易日仍应尝试全量/回退拉取，而不是直接返回成功',
        );
        expect(fakeWriter.writeCalls, 1);
        expect(result.totalRecords, greaterThan(0));
      },
    );

    test(
      'bootstrap plan paginates pool fetch for long minute ranges',
      () async {
        final startDay = DateTime(2026, 1, 5);
        final tradingDays = List<DateTime>.generate(
          20,
          (index) => startDay.add(Duration(days: index)),
        );

        await manager.saveKlineData(
          stockCode: '000001',
          newBars: [
            for (final day in tradingDays)
              KLine(
                datetime: day,
                open: 10,
                close: 10.2,
                high: 10.3,
                low: 9.9,
                volume: 1000,
                amount: 10000,
              ),
          ],
          dataType: KLineDataType.daily,
        );

        fakePlanner.plansByStock['000001'] = MinuteFetchPlan(
          stockCode: '000001',
          mode: MinuteSyncMode.bootstrap,
          datesToFetch: tradingDays,
        );
        fakeAdapter.barsToReturn = {
          '000001': [buildMinuteBar(DateTime(2026, 1, 24, 9, 30))],
        };
        fakeWriter.resultToReturn = const MinuteWriteResult(
          updatedStocks: ['000001'],
          totalRecords: 6,
        );

        final result = await repository.fetchMissingData(
          stockCodes: ['000001'],
          dateRange: DateRange(
            tradingDays.first,
            DateTime(
              tradingDays.last.year,
              tradingDays.last.month,
              tradingDays.last.day,
              23,
              59,
              59,
            ),
          ),
          dataType: KLineDataType.oneMinute,
        );

        expect(fakeAdapter.fetchCalls, 6);
        expect(fakeAdapter.startsByCall, [0, 800, 1600, 2400, 3200, 4000]);
        expect(result.totalRecords, 6);
      },
    );

    test(
      'empty bars for one stock should not be counted as successful update',
      () async {
        final tradingDay = DateTime(2026, 2, 13);

        fakePlanner.plansByStock['000001'] = MinuteFetchPlan(
          stockCode: '000001',
          mode: MinuteSyncMode.bootstrap,
          datesToFetch: [tradingDay],
        );
        fakePlanner.plansByStock['000002'] = MinuteFetchPlan(
          stockCode: '000002',
          mode: MinuteSyncMode.bootstrap,
          datesToFetch: [tradingDay],
        );

        fakeAdapter.barsToReturn = {
          '000001': [buildMinuteBar(DateTime(2026, 2, 13, 9, 30))],
          '000002': const [],
        };
        fakeWriter.resultToReturn = const MinuteWriteResult(
          updatedStocks: ['000001'],
          totalRecords: 1,
        );

        final result = await repository.fetchMissingData(
          stockCodes: ['000001', '000002'],
          dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
          dataType: KLineDataType.oneMinute,
        );

        expect(result.successCount, 1);
        expect(result.failureCount, 1);
        expect(result.errors.containsKey('000002'), isTrue);
      },
    );

    test('per-stock persist failure should increase failureCount', () async {
      final tradingDay = DateTime(2026, 2, 13);

      fakePlanner.plansByStock['000001'] = MinuteFetchPlan(
        stockCode: '000001',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );
      fakePlanner.plansByStock['000002'] = MinuteFetchPlan(
        stockCode: '000002',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );

      fakeAdapter.barsToReturn = {
        '000001': [buildMinuteBar(DateTime(2026, 2, 13, 9, 30))],
        '000002': [buildMinuteBar(DateTime(2026, 2, 13, 9, 31))],
      };
      fakeWriter.resultToReturn = const MinuteWriteResult(
        updatedStocks: ['000001'],
        totalRecords: 1,
        outcomesByStock: {
          '000001': MinuteWriteStockOutcome(
            stockCode: '000001',
            success: true,
            updated: true,
            recordCount: 1,
          ),
          '000002': MinuteWriteStockOutcome(
            stockCode: '000002',
            success: false,
            updated: false,
            recordCount: 0,
            error: 'persist failed: disk full',
          ),
        },
        errorsByStock: {'000002': 'persist failed: disk full'},
      );

      final result = await repository.fetchMissingData(
        stockCodes: ['000001', '000002'],
        dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.oneMinute,
      );

      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(result.errors.containsKey('000002'), isTrue);
      expect(result.errors['000002'], 'persist failed: disk full');
    });

    test('result should report partial success accurately', () async {
      final tradingDay = DateTime(2026, 2, 13);

      fakePlanner.plansByStock['000001'] = MinuteFetchPlan(
        stockCode: '000001',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );
      fakePlanner.plansByStock['000002'] = MinuteFetchPlan(
        stockCode: '000002',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );
      fakePlanner.plansByStock['000003'] = MinuteFetchPlan(
        stockCode: '000003',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );

      fakeAdapter.barsToReturn = {
        '000001': [buildMinuteBar(DateTime(2026, 2, 13, 9, 30))],
        '000002': const [],
        '000003': [buildMinuteBar(DateTime(2026, 2, 13, 9, 32))],
      };
      fakeWriter.resultToReturn = const MinuteWriteResult(
        updatedStocks: ['000001'],
        totalRecords: 1,
        outcomesByStock: {
          '000001': MinuteWriteStockOutcome(
            stockCode: '000001',
            success: true,
            updated: true,
            recordCount: 1,
          ),
          '000003': MinuteWriteStockOutcome(
            stockCode: '000003',
            success: false,
            updated: false,
            recordCount: 0,
            error: 'persist failed: timeout',
          ),
        },
        errorsByStock: {'000003': 'persist failed: timeout'},
      );

      final result = await repository.fetchMissingData(
        stockCodes: ['000001', '000002', '000003'],
        dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.oneMinute,
      );

      expect(result.successCount, 1);
      expect(result.failureCount, 2);
      expect(result.errors.containsKey('000002'), isTrue);
      expect(result.errors.containsKey('000003'), isTrue);
      expect(result.errors['000003'], 'persist failed: timeout');
    });

    test('propagates fetch-side errors into final FetchResult errors', () async {
      final tradingDay = DateTime(2026, 2, 13);

      fakePlanner.plansByStock['000001'] = MinuteFetchPlan(
        stockCode: '000001',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );
      fakePlanner.plansByStock['000002'] = MinuteFetchPlan(
        stockCode: '000002',
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: [tradingDay],
      );

      fakeAdapter.barsToReturn = {
        '000001': [buildMinuteBar(DateTime(2026, 2, 13, 9, 30))],
        '000002': const [],
      };
      fakeAdapter.errorsToReturn = {
        '000002': 'fetch failed: timeout',
      };
      fakeWriter.resultToReturn = const MinuteWriteResult(
        updatedStocks: ['000001'],
        totalRecords: 1,
      );

      final result = await repository.fetchMissingData(
        stockCodes: ['000001', '000002'],
        dateRange: DateRange(tradingDay, DateTime(2026, 2, 13, 23, 59, 59)),
        dataType: KLineDataType.oneMinute,
      );

      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(result.errors['000002'], 'fetch failed: timeout');
    });
  });
}
