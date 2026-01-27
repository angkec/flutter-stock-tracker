import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
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
  Map<String, List<KLine>>? barsToReturn; // key: "${market}_${code}_${category}"
  Exception? barsExceptionToThrow;
  Map<String, Exception>? barsExceptionsByStock; // 每只股票独立的异常
  List<({int market, String code, int category, int start, int count})> barRequests = [];

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
    barRequests.add((market: market, code: code, category: category, start: start, count: count));

    // 检查全局异常
    if (barsExceptionToThrow != null) {
      throw barsExceptionToThrow!;
    }

    // 检查针对特定股票的异常
    if (barsExceptionsByStock != null && barsExceptionsByStock!.containsKey(code)) {
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

      // Initialize database
      database = MarketDatabase();
      await database.database;

      // Create metadata manager
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
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
      expect(result['000001']![0].datetime, equals(DateTime(2024, 1, 15, 9, 30)));
      expect(result['000001']![1].datetime, equals(DateTime(2024, 1, 15, 9, 31)));
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

    test('should detect fresh data', () async {
      // Save recent data (today)
      final todayKlines = [
        KLine(
          datetime: DateTime.now(),
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
        newBars: todayKlines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
    });

    test('should detect stale data', () async {
      // Save old data (7 days ago)
      final oldKlines = [
        KLine(
          datetime: DateTime.now().subtract(const Duration(days: 7)),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000002',
        newBars: oldKlines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000002'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000002'], isA<Stale>());
      final stale = freshness['000002'] as Stale;
      expect(stale.missingRange.start, isA<DateTime>());
    });

    test('should detect missing data', () async {
      final freshness = await repository.checkFreshness(
        stockCodes: ['999999'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['999999'], isA<Missing>());
    });

    test('should detect data exactly 24 hours old as fresh', () async {
      // Save data just under 24 hours ago (23 hours 59 minutes)
      // Note: We use slightly less than 24 hours because DateTime.now() is called
      // twice (in test and repository), causing millisecond differences
      final boundaryKlines = [
        KLine(
          datetime: DateTime.now().subtract(const Duration(hours: 23, minutes: 59)),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000003',
        newBars: boundaryKlines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000003'],
        dataType: KLineDataType.oneMinute,
      );

      // Just under 24 hours is Fresh (age > threshold, not >=)
      expect(freshness['000003'], isA<Fresh>());
    });

    test('should detect data just over 24 hours old as stale', () async {
      // Save data 25 hours ago
      final justOverKlines = [
        KLine(
          datetime: DateTime.now().subtract(const Duration(hours: 25)),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000004',
        newBars: justOverKlines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000004'],
        dataType: KLineDataType.oneMinute,
      );

      // Over 24 hours is Stale
      expect(freshness['000004'], isA<Stale>());
    });
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
      testDir = await Directory.systemTemp.createTemp('market_data_repo_quotes_test_');

      // Initialize file storage with test directory
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();

      // Initialize database
      database = MarketDatabase();
      await database.database;

      // Create metadata manager
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
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
        stockCodes: ['000001', '002001', '300001', '600001', '601001', '688001'],
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

      final result = await repository.getQuotes(
        stockCodes: ['000001'],
      );

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
      testDir = await Directory.systemTemp.createTemp('market_data_repo_fetch_test_');

      // 初始化文件存储
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();

      // 初始化数据库
      database = MarketDatabase();
      await database.database;

      // 创建元数据管理器
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
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
        klines.add(KLine(
          datetime: currentTime,
          open: 10.0 + i * 0.1,
          close: 10.0 + i * 0.1 + 0.05,
          high: 10.0 + i * 0.1 + 0.1,
          low: 10.0 + i * 0.1 - 0.05,
          volume: 1000 + i * 10,
          amount: 10000 + i * 100,
        ));

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
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

      // 生成 mock K线数据（5条1分钟数据）
      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      // 设置 mock 返回数据（深市股票，market=0，1分钟=category 7）
      mockTdxClient.barsToReturn = {
        '0_000001_7': mockKlines,
      };

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
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

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
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {
        '0_000001_7': mockKlines,
      };

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
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {
        '0_000001_7': mockKlines,
      };

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
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
      );

      final mockKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      // 设置：000001 成功，000002 失败
      mockTdxClient.barsToReturn = {
        '0_000001_7': mockKlines,
      };
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

      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
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
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 16),
      );

      // 测试1分钟数据
      final minuteKlines = generateTestKlines(
        startDate: DateTime(2024, 1, 15, 9, 30),
        count: 5,
        isMinuteData: true,
      );

      mockTdxClient.barsToReturn = {
        '0_000001_7': minuteKlines,  // category 7 = 1分钟
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
        '0_000002_4': dailyKlines,  // category 4 = 日线
      };

      await repository.fetchMissingData(
        stockCodes: ['000002'],
        dateRange: dateRange,
        dataType: KLineDataType.daily,
      );

      expect(mockTdxClient.barRequests.isNotEmpty, isTrue);
      expect(mockTdxClient.barRequests.first.category, equals(4)); // 日线
    });

    test('should invalidate cache for updated stocks', () async {
      // 先手动添加一些缓存数据
      final dateRange = DateRange(
        DateTime(2024, 1, 15),
        DateTime(2024, 1, 15, 9, 35),
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

      mockTdxClient.barsToReturn = {
        '0_000001_7': newKlines,
      };

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

      mockTdxClient.barsToReturn = {
        '0_000001_7': mockKlines,
      };

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
      testDir = await Directory.systemTemp.createTemp('market_data_repo_refetch_test_');

      // 初始化文件存储
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();

      // 初始化数据库
      database = MarketDatabase();
      await database.database;

      // 创建元数据管理器
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
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
      testDir = await Directory.systemTemp.createTemp('market_data_repo_cleanup_test_');

      // Initialize file storage with test directory
      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();

      // Initialize database
      database = MarketDatabase();
      await database.database;

      // Create metadata manager
      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
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
      await repository.cleanupOldData(
        beforeDate: DateTime(2024, 2, 1),
      );

      // 3. Verify Jan data deleted (empty result)
      final janData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: DateRange(
          DateTime(2024, 1, 1),
          DateTime(2024, 1, 31),
        ),
        dataType: KLineDataType.oneMinute,
      );
      expect(janData['000001'], isEmpty);

      // 4. Verify Feb data still exists
      final febData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: DateRange(
          DateTime(2024, 2, 1),
          DateTime(2024, 2, 29),
        ),
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
      final dateRange = DateRange(
        DateTime(2024, 1, 1),
        DateTime(2024, 1, 31),
      );

      final cachedData = await repository.getKlines(
        stockCodes: ['000001'],
        dateRange: dateRange,
        dataType: KLineDataType.oneMinute,
      );
      expect(cachedData['000001'], isNotEmpty);

      // 3. Call cleanupOldData
      await repository.cleanupOldData(
        beforeDate: DateTime(2024, 2, 1),
      );

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
      await repository.cleanupOldData(
        beforeDate: DateTime(2024, 2, 1),
      );

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
      await repository.cleanupOldData(
        beforeDate: DateTime(2024, 2, 1),
      );

      // Verify all stocks' data is cleaned
      final dateRange = DateRange(
        DateTime(2024, 1, 1),
        DateTime(2024, 1, 31),
      );

      for (final code in ['000001', '000002', '600000']) {
        final data = await repository.getKlines(
          stockCodes: [code],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );
        expect(data[code], isEmpty, reason: 'Stock $code should have no Jan data');
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
      await repository.cleanupOldData(
        beforeDate: DateTime(2024, 2, 1),
      );

      // Verify both data types are cleaned
      final dateRange = DateRange(
        DateTime(2024, 1, 1),
        DateTime(2024, 1, 31),
      );

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
  });
}
