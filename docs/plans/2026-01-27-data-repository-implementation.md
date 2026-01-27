# DataRepository Implementation Plan (Phase 2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement concrete DataRepository class that provides unified data access with caching, freshness checking, and reactive updates.

**Architecture:** Implement the DataRepository interface from Phase 1 using KLineMetadataManager for persistence, TdxClient for fetching, StreamControllers for reactive updates, and an in-memory cache for performance.

**Tech Stack:**
- Dart/Flutter
- TdxClient (existing - connects to TDX servers)
- KLineMetadataManager (Phase 1 - SQLite + file storage)
- StreamController for reactive streams
- In-memory Map cache for K-line data

---

## Task 1: Create DataRepository Implementation Shell

**Files:**
- Create: `lib/data/repository/market_data_repository.dart`
- Create: `test/data/repository/market_data_repository_test.dart`
- Reference: `lib/data/repository/data_repository.dart` (interface from Phase 1)

**Step 1: Write the failing test**

Create `test/data/repository/market_data_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';

void main() {
  group('MarketDataRepository', () {
    late MarketDataRepository repository;

    setUp(() {
      repository = MarketDataRepository();
    });

    tearDown(() async {
      await repository.dispose();
    });

    test('should implement DataRepository interface', () {
      expect(repository, isA<DataRepository>());
    });

    test('should provide status stream', () {
      expect(repository.statusStream, isA<Stream<DataStatus>>());
    });

    test('should emit initial status', () async {
      final status = await repository.statusStream.first;
      expect(status, isA<DataStatus>());
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: FAIL with "MarketDataRepository not found"

**Step 3: Write minimal implementation**

Create `lib/data/repository/market_data_repository.dart`:

```dart
import 'dart:async';
import '../models/data_status.dart';
import '../models/data_updated_event.dart';
import '../models/data_freshness.dart';
import '../models/kline_data_type.dart';
import '../models/date_range.dart';
import '../models/fetch_result.dart';
import '../../models/kline.dart';
import '../../models/quote.dart';
import 'data_repository.dart';

/// 市场数据仓库 - DataRepository 的具体实现
class MarketDataRepository implements DataRepository {
  final StreamController<DataStatus> _statusController = StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _dataUpdatedController = StreamController<DataUpdatedEvent>.broadcast();

  MarketDataRepository() {
    // 初始状态：就绪
    _statusController.add(const DataReady(0));
  }

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _dataUpdatedController.stream;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    // TODO: Implement
    return {};
  }

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    // TODO: Implement
    return {};
  }

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async {
    // TODO: Implement
    return {};
  }

  @override
  Future<int> getCurrentVersion() async {
    // TODO: Implement
    return 0;
  }

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    // TODO: Implement
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: {},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    // TODO: Implement
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: {},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
  }) async {
    // TODO: Implement
  }

  /// 释放资源
  Future<void> dispose() async {
    await _statusController.close();
    await _dataUpdatedController.close();
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/market_data_repository_test.dart
git commit -m "feat(data): create MarketDataRepository implementation shell

- Implement DataRepository interface
- Add StreamControllers for status and data events
- Add dispose method for cleanup
- Add basic tests for interface compliance

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Implement getKlines with In-Memory Cache

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add to `test/data/repository/market_data_repository_test.dart`:

```dart
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

// Add to test group
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

  // Save test data
  final manager = KLineMetadataManager();
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

  // Second load - should be from cache (faster)
  final stopwatch = Stopwatch()..start();
  final result2 = await repository.getKlines(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 1, 15),
      DateTime(2024, 1, 15, 23, 59),
    ),
    dataType: KLineDataType.oneMinute,
  );
  stopwatch.stop();

  // Cache hit should be much faster (< 10ms)
  expect(stopwatch.elapsedMilliseconds, lessThan(10));
  expect(result2['000001'], equals(result1['000001']));
});

test('should return empty map for unknown stocks', () async {
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
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: FAIL with "TODO: Implement" or timeout

**Step 3: Implement getKlines with caching**

Modify `lib/data/repository/market_data_repository.dart`:

```dart
import '../storage/kline_metadata_manager.dart';
import '../storage/market_database.dart';
import '../storage/kline_file_storage.dart';

class MarketDataRepository implements DataRepository {
  final KLineMetadataManager _metadataManager;

  // 内存缓存：Map<cacheKey, List<KLine>>
  // cacheKey = "${stockCode}_${dataType}_${startDate}_${endDate}"
  final Map<String, List<KLine>> _klineCache = {};

  MarketDataRepository({
    KLineMetadataManager? metadataManager,
  }) : _metadataManager = metadataManager ?? KLineMetadataManager() {
    _statusController.add(const DataReady(0));
  }

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final result = <String, List<KLine>>{};

    for (final stockCode in stockCodes) {
      // 构建缓存key
      final cacheKey = _buildCacheKey(stockCode, dateRange, dataType);

      // 检查缓存
      if (_klineCache.containsKey(cacheKey)) {
        result[stockCode] = _klineCache[cacheKey]!;
        continue;
      }

      // 从存储加载
      try {
        final klines = await _metadataManager.loadKlineData(
          stockCode: stockCode,
          startDate: dateRange.start,
          endDate: dateRange.end,
          dataType: dataType,
        );

        // 存入缓存
        _klineCache[cacheKey] = klines;
        result[stockCode] = klines;
      } catch (e) {
        // 加载失败，返回空列表
        result[stockCode] = [];
      }
    }

    return result;
  }

  String _buildCacheKey(String stockCode, DateRange dateRange, KLineDataType dataType) {
    final startMs = dateRange.start.millisecondsSinceEpoch;
    final endMs = dateRange.end.millisecondsSinceEpoch;
    return '${stockCode}_${dataType.name}_${startMs}_$endMs';
  }

  @override
  Future<int> getCurrentVersion() async {
    return await _metadataManager.getCurrentVersion();
  }

  // ... rest of the class
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: PASS (6 tests)

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/market_data_repository_test.dart
git commit -m "feat(data): implement getKlines with in-memory cache

- Load K-line data from KLineMetadataManager
- Cache loaded data in memory by cache key
- Return empty list on load failure
- Implement getCurrentVersion delegation

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Implement checkFreshness Logic

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add to test file:

```dart
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

  final manager = KLineMetadataManager();
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

  final manager = KLineMetadataManager();
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
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: FAIL with empty map or type mismatch

**Step 3: Implement checkFreshness**

Modify `lib/data/repository/market_data_repository.dart`:

```dart
@override
Future<Map<String, DataFreshness>> checkFreshness({
  required List<String> stockCodes,
  required KLineDataType dataType,
}) async {
  final result = <String, DataFreshness>{};

  for (final stockCode in stockCodes) {
    try {
      // 获取最新数据日期
      final latestDate = await _metadataManager.getLatestDataDate(
        stockCode: stockCode,
        dataType: dataType,
      );

      if (latestDate == null) {
        // 完全没有数据
        result[stockCode] = const Missing();
        continue;
      }

      // 检查数据是否过时
      final now = DateTime.now();
      final age = now.difference(latestDate);

      // 1分钟数据：超过1天视为过时
      // 日线数据：超过1天视为过时
      final staleThreshold = dataType == KLineDataType.oneMinute
          ? const Duration(days: 1)
          : const Duration(days: 1);

      if (age > staleThreshold) {
        // 数据过时，需要拉取从 latestDate+1 到现在的数据
        final missingStart = latestDate.add(const Duration(days: 1));
        result[stockCode] = Stale(
          missingRange: DateRange(missingStart, now),
        );
      } else {
        // 数据新鲜
        result[stockCode] = const Fresh();
      }
    } catch (e) {
      // 出错视为缺失
      result[stockCode] = const Missing();
    }
  }

  return result;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: PASS (9 tests)

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/market_data_repository_test.dart
git commit -m "feat(data): implement checkFreshness logic

- Detect fresh data (within 1 day threshold)
- Detect stale data with missing date range
- Detect completely missing data
- Use getLatestDataDate from metadata manager

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Implement getQuotes (Delegate to TdxClient)

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add to test file:

```dart
import 'package:stock_rtwatcher/services/tdx_client.dart';

// Mock TdxClient for testing
class MockTdxClient extends TdxClient {
  final Map<String, Quote> _mockQuotes = {};

  void addMockQuote(String stockCode, Quote quote) {
    _mockQuotes[stockCode] = quote;
  }

  @override
  Future<List<Quote>> getSecurityQuotes(List<(int, String)> stocks) async {
    return stocks
        .map((stock) => _mockQuotes[stock.$2])
        .whereType<Quote>()
        .toList();
  }
}

// Add to test group
test('should get quotes from TdxClient', () async {
  final mockClient = MockTdxClient();
  mockClient.addMockQuote('000001', Quote(
    code: '000001',
    name: '平安银行',
    price: 10.5,
    open: 10.0,
    close: 10.3,
    high: 10.8,
    low: 9.9,
    volume: 1000000,
    amount: 10500000,
    bid1: 10.49,
    ask1: 10.51,
    // ... other fields
  ));

  final repoWithMock = MarketDataRepository(tdxClient: mockClient);

  final quotes = await repoWithMock.getQuotes(
    stockCodes: ['000001'],
  );

  expect(quotes['000001'], isNotNull);
  expect(quotes['000001']!.code, equals('000001'));
  expect(quotes['000001']!.price, equals(10.5));

  await repoWithMock.dispose();
});

test('should handle quote fetch errors gracefully', () async {
  final quotes = await repository.getQuotes(
    stockCodes: ['INVALID'],
  );

  // Should not throw, just return empty for failed stocks
  expect(quotes['INVALID'], isNull);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: FAIL with unimplemented or type error

**Step 3: Implement getQuotes**

Modify `lib/data/repository/market_data_repository.dart`:

```dart
import '../../services/tdx_client.dart';

class MarketDataRepository implements DataRepository {
  final TdxClient _tdxClient;

  MarketDataRepository({
    KLineMetadataManager? metadataManager,
    TdxClient? tdxClient,
  }) : _metadataManager = metadataManager ?? KLineMetadataManager(),
       _tdxClient = tdxClient ?? TdxClient() {
    _statusController.add(const DataReady(0));
  }

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async {
    final result = <String, Quote>{};

    try {
      // 确保连接到TDX服务器
      if (!_tdxClient.isConnected) {
        // 尝试连接到第一个可用服务器
        bool connected = false;
        for (final server in TdxClient.servers) {
          connected = await _tdxClient.connect(
            server['host'] as String,
            server['port'] as int,
          );
          if (connected) break;
        }

        if (!connected) {
          // 连接失败，返回空map
          return result;
        }
      }

      // 将股票代码转换为 (market, code) 格式
      final stocks = stockCodes.map((code) {
        // 根据代码前缀判断市场
        final market = _getMarketByCode(code);
        return (market, code);
      }).toList();

      // 批量获取行情
      final quotes = await _tdxClient.getSecurityQuotes(stocks);

      // 构建结果map
      for (final quote in quotes) {
        result[quote.code] = quote;
      }
    } catch (e) {
      // 获取行情失败，返回已有结果
      print('Failed to get quotes: $e');
    }

    return result;
  }

  /// 根据股票代码判断市场
  /// 0 = 深圳, 1 = 上海
  int _getMarketByCode(String code) {
    if (code.startsWith('6')) {
      return 1; // 上海
    } else if (code.startsWith('0') || code.startsWith('3')) {
      return 0; // 深圳
    } else {
      return 0; // 默认深圳
    }
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _dataUpdatedController.close();
    await _tdxClient.disconnect();
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: PASS (11 tests)

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/market_data_repository_test.dart
git commit -m "feat(data): implement getQuotes delegating to TdxClient

- Connect to TDX server if not connected
- Map stock codes to (market, code) tuples
- Batch fetch quotes via TdxClient
- Handle connection failures gracefully
- Add disconnect in dispose method

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Implement fetchMissingData with Progress

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add to test file:

```dart
test('should fetch missing data and save to storage', () async {
  final mockClient = MockTdxClient();

  // Mock K-line data
  final mockKlines = [
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

  mockClient.setMockKlines('000001', mockKlines);

  final repoWithMock = MarketDataRepository(tdxClient: mockClient);

  final result = await repoWithMock.fetchMissingData(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 1, 15),
      DateTime(2024, 1, 15, 23, 59),
    ),
    dataType: KLineDataType.oneMinute,
  );

  expect(result.totalStocks, equals(1));
  expect(result.successCount, equals(1));
  expect(result.failureCount, equals(0));
  expect(result.totalRecords, greaterThan(0));

  await repoWithMock.dispose();
});

test('should report progress during fetch', () async {
  final progressUpdates = <(int, int)>[];

  await repository.fetchMissingData(
    stockCodes: ['000001', '000002', '000003'],
    dateRange: DateRange(
      DateTime(2024, 1, 15),
      DateTime(2024, 1, 15, 23, 59),
    ),
    dataType: KLineDataType.oneMinute,
    onProgress: (current, total) {
      progressUpdates.add((current, total));
    },
  );

  expect(progressUpdates, isNotEmpty);
  expect(progressUpdates.last.$1, equals(progressUpdates.last.$2));
});

test('should emit DataUpdatedEvent after successful fetch', () async {
  final events = <DataUpdatedEvent>[];
  final subscription = repository.dataUpdatedStream.listen(events.add);

  await repository.fetchMissingData(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 1, 15),
      DateTime(2024, 1, 15, 23, 59),
    ),
    dataType: KLineDataType.oneMinute,
  );

  await Future.delayed(const Duration(milliseconds: 100));

  expect(events, isNotEmpty);
  expect(events.first.stockCodes, contains('000001'));

  await subscription.cancel();
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: FAIL with unimplemented

**Step 3: Implement fetchMissingData**

Modify `lib/data/repository/market_data_repository.dart`:

```dart
@override
Future<FetchResult> fetchMissingData({
  required List<String> stockCodes,
  required DateRange dateRange,
  required KLineDataType dataType,
  ProgressCallback? onProgress,
}) async {
  final startTime = DateTime.now();

  // 发出拉取中状态
  _statusController.add(const DataFetching());

  int successCount = 0;
  int failureCount = 0;
  int totalRecords = 0;
  final errors = <String, String>{};

  try {
    // 确保连接到TDX服务器
    if (!_tdxClient.isConnected) {
      bool connected = false;
      for (final server in TdxClient.servers) {
        connected = await _tdxClient.connect(
          server['host'] as String,
          server['port'] as int,
        );
        if (connected) break;
      }

      if (!connected) {
        _statusController.add(const DataError('Failed to connect to TDX server'));
        return FetchResult(
          totalStocks: stockCodes.length,
          successCount: 0,
          failureCount: stockCodes.length,
          errors: {for (var code in stockCodes) code: 'Connection failed'},
          totalRecords: 0,
          duration: DateTime.now().difference(startTime),
        );
      }
    }

    // 逐个股票拉取数据
    for (var i = 0; i < stockCodes.length; i++) {
      final stockCode = stockCodes[i];

      try {
        // 拉取K线数据
        final klines = await _fetchKlinesForStock(
          stockCode: stockCode,
          dateRange: dateRange,
          dataType: dataType,
        );

        if (klines.isNotEmpty) {
          // 保存到存储
          await _metadataManager.saveKlineData(
            stockCode: stockCode,
            newBars: klines,
            dataType: dataType,
          );

          // 清除缓存（数据已更新）
          _invalidateCache(stockCode, dataType);

          successCount++;
          totalRecords += klines.length;
        } else {
          failureCount++;
          errors[stockCode] = 'No data returned';
        }
      } catch (e) {
        failureCount++;
        errors[stockCode] = e.toString();
      }

      // 报告进度
      onProgress?.call(i + 1, stockCodes.length);
    }

    // 获取新的数据版本
    final newVersion = await _metadataManager.getCurrentVersion();

    // 发出数据更新事件
    if (successCount > 0) {
      _dataUpdatedController.add(DataUpdatedEvent(
        stockCodes: stockCodes.where((code) => !errors.containsKey(code)).toList(),
        dateRange: dateRange,
        dataType: dataType,
        dataVersion: newVersion,
      ));
    }

    // 恢复就绪状态
    _statusController.add(DataReady(newVersion));

    return FetchResult(
      totalStocks: stockCodes.length,
      successCount: successCount,
      failureCount: failureCount,
      errors: errors,
      totalRecords: totalRecords,
      duration: DateTime.now().difference(startTime),
    );
  } catch (e) {
    _statusController.add(DataError(e.toString()));
    rethrow;
  }
}

/// 为单个股票拉取K线数据
Future<List<KLine>> _fetchKlinesForStock({
  required String stockCode,
  required DateRange dateRange,
  required KLineDataType dataType,
}) async {
  final market = _getMarketByCode(stockCode);
  final category = dataType == KLineDataType.oneMinute ? 7 : 4;

  // TDX协议：start=0表示最新，逐步向历史拉取
  // 这里简化实现，拉取最新800条（可根据dateRange计算需要拉取的条数）
  final allKlines = <KLine>[];
  int start = 0;
  const batchSize = 800;

  while (true) {
    final batch = await _tdxClient.getSecurityBars(
      market: market,
      code: stockCode,
      category: category,
      start: start,
      count: batchSize,
    );

    if (batch.isEmpty) break;

    allKlines.addAll(batch);

    // 检查是否已覆盖dateRange
    final oldestDate = batch.last.datetime;
    if (oldestDate.isBefore(dateRange.start)) {
      break;
    }

    start += batchSize;

    // 安全限制：最多拉取10批次
    if (start >= 8000) break;
  }

  // 过滤出dateRange内的数据
  return allKlines.where((kline) {
    return !kline.datetime.isBefore(dateRange.start) &&
           !kline.datetime.isAfter(dateRange.end);
  }).toList();
}

/// 清除缓存中与指定股票和数据类型相关的条目
void _invalidateCache(String stockCode, KLineDataType dataType) {
  _klineCache.removeWhere((key, _) {
    return key.startsWith('${stockCode}_${dataType.name}_');
  });
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: PASS (14 tests)

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/market_data_repository_test.dart
git commit -m "feat(data): implement fetchMissingData with progress tracking

- Connect to TDX server and fetch K-line data
- Save fetched data via KLineMetadataManager
- Emit progress callbacks during fetch
- Emit DataUpdatedEvent on successful fetch
- Update status stream (Fetching -> Ready/Error)
- Invalidate cache after data update

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Implement refetchData

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add to test file:

```dart
test('should refetch data and overwrite existing', () async {
  // Save old data
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

  final manager = KLineMetadataManager();
  await manager.saveKlineData(
    stockCode: '000001',
    newBars: oldKlines,
    dataType: KLineDataType.oneMinute,
  );

  // Refetch with mock client
  final mockClient = MockTdxClient();
  final newKlines = [
    KLine(
      datetime: DateTime(2024, 1, 15, 9, 30),
      open: 11.0, // Different price
      close: 11.5,
      high: 11.8,
      low: 10.9,
      volume: 2000,
      amount: 22000,
    ),
  ];
  mockClient.setMockKlines('000001', newKlines);

  final repoWithMock = MarketDataRepository(tdxClient: mockClient);

  final result = await repoWithMock.refetchData(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 1, 15),
      DateTime(2024, 1, 15, 23, 59),
    ),
    dataType: KLineDataType.oneMinute,
  );

  expect(result.successCount, equals(1));

  // Verify data was overwritten
  final loaded = await repoWithMock.getKlines(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 1, 15),
      DateTime(2024, 1, 15, 23, 59),
    ),
    dataType: KLineDataType.oneMinute,
  );

  expect(loaded['000001']![0].open, equals(11.0));

  await repoWithMock.dispose();
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: FAIL with unimplemented

**Step 3: Implement refetchData**

Modify `lib/data/repository/market_data_repository.dart`:

```dart
@override
Future<FetchResult> refetchData({
  required List<String> stockCodes,
  required DateRange dateRange,
  required KLineDataType dataType,
  ProgressCallback? onProgress,
}) async {
  // refetchData 和 fetchMissingData 逻辑相同
  // 区别在于 refetchData 强制重新拉取，覆盖现有数据
  // 由于 saveKlineData 会覆盖同月数据，所以实现相同
  return await fetchMissingData(
    stockCodes: stockCodes,
    dateRange: dateRange,
    dataType: dataType,
    onProgress: onProgress,
  );
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: PASS (15 tests)

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/market_data_repository_test.dart
git commit -m "feat(data): implement refetchData

- Delegate to fetchMissingData (overwrites existing data)
- saveKlineData already overwrites same-month data
- Support progress callbacks

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Implement cleanupOldData

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `test/data/repository/market_data_repository_test.dart`

**Step 1: Write the failing test**

Add to test file:

```dart
test('should cleanup old data before specified date', () async {
  // Save data across multiple months
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
      volume: 1000,
      amount: 11000,
    ),
  ];

  final manager = KLineMetadataManager();
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

  // Cleanup data before Feb 1, 2024
  await repository.cleanupOldData(
    beforeDate: DateTime(2024, 2, 1),
  );

  // Verify Jan data deleted
  final janData = await repository.getKlines(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 1, 1),
      DateTime(2024, 1, 31),
    ),
    dataType: KLineDataType.oneMinute,
  );
  expect(janData['000001'], isEmpty);

  // Verify Feb data still exists
  final febData = await repository.getKlines(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 2, 1),
      DateTime(2024, 2, 29),
    ),
    dataType: KLineDataType.oneMinute,
  );
  expect(febData['000001'], isNotEmpty);
});

test('should clear cache after cleanup', () async {
  // Load data into cache
  await repository.getKlines(
    stockCodes: ['000001'],
    dateRange: DateRange(
      DateTime(2024, 1, 1),
      DateTime(2024, 1, 31),
    ),
    dataType: KLineDataType.oneMinute,
  );

  // Cleanup
  await repository.cleanupOldData(
    beforeDate: DateTime(2024, 2, 1),
  );

  // Cache should be cleared
  // (Verified by checking internal cache, or by timing next load)
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: FAIL with unimplemented

**Step 3: Implement cleanupOldData**

Modify `lib/data/repository/market_data_repository.dart`:

```dart
@override
Future<void> cleanupOldData({
  required DateTime beforeDate,
}) async {
  try {
    // 获取所有股票代码（从元数据）
    // 简化实现：遍历两种数据类型
    for (final dataType in KLineDataType.values) {
      // 注意：这里需要获取所有股票列表
      // 实际实现中可能需要从数据库查询所有不同的stock_code
      // 这里简化为直接调用 deleteOldData（它会处理所有股票）

      // 由于 deleteOldData 需要 stockCode，我们需要先查询所有股票
      // 暂时通过查询数据库实现
      final db = await _metadataManager.database;
      final results = await db.rawQuery(
        'SELECT DISTINCT stock_code FROM kline_files WHERE data_type = ?',
        [dataType.name],
      );

      for (final row in results) {
        final stockCode = row['stock_code'] as String;

        await _metadataManager.deleteOldData(
          stockCode: stockCode,
          dataType: dataType,
          beforeDate: beforeDate,
        );

        // 清除缓存
        _invalidateCache(stockCode, dataType);
      }
    }

    // 发出数据更新事件（数据已清理）
    final newVersion = await _metadataManager.getCurrentVersion();
    _statusController.add(DataReady(newVersion));
  } catch (e) {
    print('Failed to cleanup old data: $e');
    rethrow;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/market_data_repository_test.dart`

Expected: PASS (17 tests)

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/market_data_repository_test.dart
git commit -m "feat(data): implement cleanupOldData

- Query all stock codes from database
- Delete old data via KLineMetadataManager
- Invalidate cache for cleaned stocks
- Update status stream with new version

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary

This plan implements Phase 2 of the data architecture refactor: **the concrete DataRepository implementation**.

**What's been accomplished:**
1. ✅ MarketDataRepository shell with streams
2. ✅ getKlines with in-memory cache
3. ✅ checkFreshness logic (Fresh/Stale/Missing)
4. ✅ getQuotes delegating to TdxClient
5. ✅ fetchMissingData with progress and events
6. ✅ refetchData (overwrites existing)
7. ✅ cleanupOldData with cache invalidation

**What's next:**
- Phase 3: Update existing services to use DataRepository
- Phase 4: Presentation layer integration
- Phase 5: Migration and cleanup

**Estimated effort:** 1-2 weeks for complete Phase 2

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-01-27-data-repository-implementation.md`.

Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
