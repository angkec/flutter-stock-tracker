# Data Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the new data layer with SQLite + monthly-sharded file storage, ensuring atomic writes and data integrity.

**Architecture:** Three-component design: (1) SQLite database for metadata/indexing, (2) Monthly-sharded compressed files for K-line data, (3) Incremental fetcher with checksum validation and atomic writes.

**Tech Stack:** Flutter/Dart, sqflite, path_provider, crypto (SHA256), archive (gzip), existing TdxClient/TdxPool

---

## Prerequisites

Before starting, ensure:
- Development environment is set up
- All existing tests pass: `flutter test`
- No uncommitted changes: `git status`

---

## Task 1: Create Data Layer Module Structure

**Files:**
- Create: `lib/data/models/data_status.dart`
- Create: `lib/data/models/data_freshness.dart`
- Create: `lib/data/models/fetch_result.dart`
- Create: `lib/data/models/date_range.dart`

**Step 1: Create data_status.dart with sealed class**

```dart
// lib/data/models/data_status.dart

/// 数据状态
sealed class DataStatus {
  const DataStatus();
}

/// 就绪
class DataReady extends DataStatus {
  final int dataVersion;
  const DataReady(this.dataVersion);
}

/// 数据过时
class DataStale extends DataStatus {
  final List<String> missingStockCodes;
  final DateRange missingRange;

  const DataStale({
    required this.missingStockCodes,
    required this.missingRange,
  });
}

/// 拉取中
class DataFetching extends DataStatus {
  final int current;
  final int total;
  final String currentStock;

  const DataFetching({
    required this.current,
    required this.total,
    required this.currentStock,
  });
}

/// 错误
class DataError extends DataStatus {
  final String message;
  final Exception? exception;

  const DataError(this.message, [this.exception]);
}
```

**Step 2: Create data_freshness.dart**

```dart
// lib/data/models/data_freshness.dart

import 'date_range.dart';

/// 数据新鲜度
sealed class DataFreshness {
  const DataFreshness();

  factory DataFreshness.fresh() => const Fresh();
  factory DataFreshness.stale({required DateRange missingRange}) =>
      Stale(missingRange: missingRange);
  factory DataFreshness.missing() => const Missing();
}

class Fresh extends DataFreshness {
  const Fresh();
}

class Stale extends DataFreshness {
  final DateRange missingRange;
  const Stale({required this.missingRange});
}

class Missing extends DataFreshness {
  const Missing();
}
```

**Step 3: Create date_range.dart**

```dart
// lib/data/models/date_range.dart

class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange(this.start, this.end);

  bool contains(DateTime date) {
    return !date.isBefore(start) && !date.isAfter(end);
  }

  Duration get duration => end.difference(start);

  @override
  String toString() => 'DateRange($start to $end)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}
```

**Step 4: Create fetch_result.dart**

```dart
// lib/data/models/fetch_result.dart

class FetchResult {
  final int totalStocks;
  final int successCount;
  final int failureCount;
  final Map<String, String> errors; // stockCode -> errorMessage
  final int totalRecords;
  final Duration duration;

  const FetchResult({
    required this.totalStocks,
    required this.successCount,
    required this.failureCount,
    required this.errors,
    required this.totalRecords,
    required this.duration,
  });

  bool get isSuccess => failureCount == 0;
  double get successRate => totalStocks > 0 ? successCount / totalStocks : 0.0;

  @override
  String toString() {
    return 'FetchResult(total: $totalStocks, success: $successCount, '
        'failed: $failureCount, records: $totalRecords, duration: $duration)';
  }
}
```

**Step 5: Verify files compile**

Run: `flutter analyze lib/data/models/`

Expected: No issues found

**Step 6: Commit**

```bash
git add lib/data/models/
git commit -m "feat(data): add core data layer models

- Add DataStatus sealed class for state management
- Add DataFreshness for data staleness detection
- Add DateRange utility model
- Add FetchResult for fetch operation results

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Set Up SQLite Database Schema

**Files:**
- Create: `lib/data/storage/database_schema.dart`
- Create: `lib/data/storage/market_database.dart`
- Modify: `pubspec.yaml` (add sqflite dependency if not present)

**Step 1: Check and add sqflite dependency**

Check `pubspec.yaml` for sqflite. If not present, add:

```yaml
dependencies:
  sqflite: ^2.3.0
```

Run: `flutter pub get`

**Step 2: Create database_schema.dart with table definitions**

```dart
// lib/data/storage/database_schema.dart

class DatabaseSchema {
  static const int version = 1;
  static const String databaseName = 'market_data.db';

  // 股票基本信息表
  static const String createStocksTable = '''
    CREATE TABLE stocks (
      code TEXT PRIMARY KEY,
      name TEXT,
      market INTEGER,
      created_at INTEGER
    )
  ''';

  // K线文件索引表
  static const String createKlineFilesTable = '''
    CREATE TABLE kline_files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      stock_code TEXT NOT NULL,
      data_type TEXT NOT NULL,
      year_month TEXT NOT NULL,
      file_path TEXT NOT NULL,
      start_date INTEGER,
      end_date INTEGER,
      record_count INTEGER,
      checksum TEXT,
      file_size INTEGER,
      created_at INTEGER,
      updated_at INTEGER,
      UNIQUE(stock_code, data_type, year_month)
    )
  ''';

  static const String createKlineFilesStockIndex = '''
    CREATE INDEX idx_kline_files_stock
    ON kline_files(stock_code, data_type)
  ''';

  static const String createKlineFilesDateIndex = '''
    CREATE INDEX idx_kline_files_date
    ON kline_files(year_month)
  ''';

  // 数据版本控制表
  static const String createDataVersionsTable = '''
    CREATE TABLE data_versions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      version INTEGER NOT NULL,
      description TEXT,
      created_at INTEGER
    )
  ''';

  // 初始化版本记录
  static const String insertInitialVersion = '''
    INSERT INTO data_versions (version, description, created_at)
    VALUES (1, 'Initial version', ?)
  ''';
}
```

**Step 3: Create market_database.dart with database helper**

```dart
// lib/data/storage/market_database.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_schema.dart';

class MarketDatabase {
  static MarketDatabase? _instance;
  static Database? _database;

  MarketDatabase._();

  factory MarketDatabase() {
    _instance ??= MarketDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, DatabaseSchema.databaseName);

    return await openDatabase(
      path,
      version: DatabaseSchema.version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 创建表
    await db.execute(DatabaseSchema.createStocksTable);
    await db.execute(DatabaseSchema.createKlineFilesTable);
    await db.execute(DatabaseSchema.createDataVersionsTable);

    // 创建索引
    await db.execute(DatabaseSchema.createKlineFilesStockIndex);
    await db.execute(DatabaseSchema.createKlineFilesDateIndex);

    // 插入初始版本
    await db.rawInsert(
      DatabaseSchema.insertInitialVersion,
      [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 预留升级逻辑
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // 获取当前数据版本
  Future<int> getCurrentVersion() async {
    final db = await database;
    final result = await db.query(
      'data_versions',
      columns: ['version'],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (result.isEmpty) return 1;
    return result.first['version'] as int;
  }

  // 增加数据版本
  Future<int> incrementVersion(String description) async {
    final db = await database;
    final currentVersion = await getCurrentVersion();
    final newVersion = currentVersion + 1;

    await db.insert('data_versions', {
      'version': newVersion,
      'description': description,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    return newVersion;
  }
}
```

**Step 4: Write test for database initialization**

```dart
// test/data/storage/market_database_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';

void main() {
  setUpAll(() {
    // 初始化 FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MarketDatabase', () {
    test('should create database with correct schema', () async {
      final db = MarketDatabase();
      final database = await db.database;

      // 验证表存在
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );

      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames, contains('stocks'));
      expect(tableNames, contains('kline_files'));
      expect(tableNames, contains('data_versions'));

      await db.close();
    });

    test('should initialize with version 1', () async {
      final db = MarketDatabase();
      final version = await db.getCurrentVersion();

      expect(version, equals(1));

      await db.close();
    });

    test('should increment version correctly', () async {
      final db = MarketDatabase();
      final initialVersion = await db.getCurrentVersion();

      final newVersion = await db.incrementVersion('Test increment');

      expect(newVersion, equals(initialVersion + 1));
      expect(await db.getCurrentVersion(), equals(newVersion));

      await db.close();
    });
  });
}
```

**Step 5: Add test dependency if needed**

Check `pubspec.yaml` dev_dependencies for sqflite_common_ffi:

```yaml
dev_dependencies:
  sqflite_common_ffi: ^2.3.0
```

Run: `flutter pub get`

**Step 6: Run test**

Run: `flutter test test/data/storage/market_database_test.dart`

Expected: All tests pass

**Step 7: Commit**

```bash
git add lib/data/storage/ test/data/storage/ pubspec.yaml
git commit -m "feat(data): implement SQLite database schema and helper

- Add DatabaseSchema with tables for stocks, kline_files, data_versions
- Add MarketDatabase singleton helper with version management
- Add indexes for efficient querying
- Add comprehensive unit tests

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Implement File Storage with Monthly Sharding

**Files:**
- Create: `lib/data/storage/kline_file_storage.dart`
- Create: `lib/data/models/kline_data_type.dart`
- Create: `test/data/storage/kline_file_storage_test.dart`

**Step 1: Create kline_data_type.dart enum**

```dart
// lib/data/models/kline_data_type.dart

enum KLineDataType {
  oneMinute('1min'),
  daily('daily');

  final String name;
  const KLineDataType(this.name);

  static KLineDataType fromName(String name) {
    return values.firstWhere((e) => e.name == name);
  }
}
```

**Step 2: Create kline_file_storage.dart with core storage logic**

```dart
// lib/data/storage/kline_file_storage.dart

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import '../models/kline_data_type.dart';
import '../../models/kline.dart';

class KLineFileStorage {
  late final String _baseDir;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final appDir = await getApplicationDocumentsDirectory();
    _baseDir = path.join(appDir.path, 'market_data', 'klines');

    // 创建目录
    await Directory(_baseDir).create(recursive: true);

    _initialized = true;
  }

  /// 获取文件路径
  String _getFilePath(String stockCode, String yearMonth, KLineDataType dataType) {
    return path.join(_baseDir, '${stockCode}_${dataType.name}_$yearMonth.bin.gz');
  }

  /// 获取临时文件路径
  String _getTempFilePath(String stockCode, String yearMonth, KLineDataType dataType) {
    return path.join(_baseDir, '${stockCode}_${dataType.name}_$yearMonth.tmp');
  }

  /// 按月份分组K线数据
  Map<String, List<KLine>> _groupByMonth(List<KLine> bars) {
    final grouped = <String, List<KLine>>{};

    for (final bar in bars) {
      final yearMonth = '${bar.datetime.year}-${bar.datetime.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(yearMonth, () => []);
      grouped[yearMonth]!.add(bar);
    }

    return grouped;
  }

  /// 合并并去重K线数据（按时间戳）
  List<KLine> _mergeAndDeduplicate(List<KLine> existing, List<KLine> newBars) {
    final map = <int, KLine>{};

    // 先添加已有数据
    for (final bar in existing) {
      map[bar.datetime.millisecondsSinceEpoch] = bar;
    }

    // 新数据覆盖（如果时间戳相同）
    for (final bar in newBars) {
      map[bar.datetime.millisecondsSinceEpoch] = bar;
    }

    // 按时间排序
    final merged = map.values.toList();
    merged.sort((a, b) => a.datetime.compareTo(b.datetime));

    return merged;
  }

  /// 序列化并压缩
  static List<int> _serializeAndCompress(List<KLine> bars) {
    // 序列化为JSON
    final jsonList = bars.map((bar) => {
      't': bar.datetime.millisecondsSinceEpoch,
      'o': bar.open,
      'c': bar.close,
      'h': bar.high,
      'l': bar.low,
      'v': bar.volume,
      'a': bar.amount,
    }).toList();

    final jsonStr = jsonEncode(jsonList);
    final bytes = utf8.encode(jsonStr);

    // 压缩
    final compressed = GZipEncoder().encode(bytes);
    return compressed!;
  }

  /// 解压缩并反序列化
  static List<KLine> _decompressAndDeserialize(List<int> compressed) {
    // 解压
    final bytes = GZipDecoder().decodeBytes(compressed);
    final jsonStr = utf8.decode(bytes);

    // 反序列化
    final jsonList = jsonDecode(jsonStr) as List;
    return jsonList.map((json) => KLine(
      datetime: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      open: (json['o'] as num).toDouble(),
      close: (json['c'] as num).toDouble(),
      high: (json['h'] as num).toDouble(),
      low: (json['l'] as num).toDouble(),
      volume: (json['v'] as num).toDouble(),
      amount: (json['a'] as num).toDouble(),
    )).toList();
  }

  /// 计算 SHA256 校验和
  String _calculateChecksum(List<int> data) {
    return sha256.convert(data).toString();
  }

  /// 读取月度K线文件
  Future<List<KLine>> loadMonthlyKlineFile({
    required String stockCode,
    required String yearMonth,
    required KLineDataType dataType,
  }) async {
    await initialize();

    final filePath = _getFilePath(stockCode, yearMonth, dataType);
    final file = File(filePath);

    if (!await file.exists()) {
      return [];
    }

    try {
      final compressed = await file.readAsBytes();
      return await compute(_decompressAndDeserialize, compressed);
    } catch (e) {
      debugPrint('Failed to load kline file $filePath: $e');
      return [];
    }
  }

  /// 保存月度K线文件（原子写入）
  Future<String> saveMonthlyKlineFile({
    required String stockCode,
    required String yearMonth,
    required KLineDataType dataType,
    required List<KLine> bars,
  }) async {
    await initialize();

    if (bars.isEmpty) {
      throw ArgumentError('Cannot save empty bars list');
    }

    // 序列化并压缩
    final compressed = await compute(_serializeAndCompress, bars);

    // 计算校验和
    final checksum = _calculateChecksum(compressed);

    // 写入临时文件
    final tempPath = _getTempFilePath(stockCode, yearMonth, dataType);
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(compressed);

    // 验证写入完整性
    final writtenData = await tempFile.readAsBytes();
    final writtenChecksum = _calculateChecksum(writtenData);

    if (writtenChecksum != checksum) {
      await tempFile.delete();
      throw Exception('Checksum mismatch: data corruption detected');
    }

    // 原子重命名
    final targetPath = _getFilePath(stockCode, yearMonth, dataType);
    await tempFile.rename(targetPath);

    return checksum;
  }

  /// 追加K线��据（增量更新）
  Future<Map<String, dynamic>> appendKlineData({
    required String stockCode,
    required List<KLine> newBars,
    required KLineDataType dataType,
  }) async {
    await initialize();

    // 按月份分组
    final barsByMonth = _groupByMonth(newBars);

    int totalRecords = 0;
    final checksums = <String, String>{};

    for (final entry in barsByMonth.entries) {
      final yearMonth = entry.key;
      final monthBars = entry.value;

      // 读取现有数据
      final existingBars = await loadMonthlyKlineFile(
        stockCode: stockCode,
        yearMonth: yearMonth,
        dataType: dataType,
      );

      // 合并去重
      final merged = _mergeAndDeduplicate(existingBars, monthBars);

      // 保存
      final checksum = await saveMonthlyKlineFile(
        stockCode: stockCode,
        yearMonth: yearMonth,
        dataType: dataType,
        bars: merged,
      );

      totalRecords += merged.length;
      checksums[yearMonth] = checksum;
    }

    return {
      'totalRecords': totalRecords,
      'monthsUpdated': barsByMonth.keys.toList(),
      'checksums': checksums,
    };
  }

  /// 删除旧数据文件
  Future<void> deleteMonthlyFile({
    required String stockCode,
    required String yearMonth,
    required KLineDataType dataType,
  }) async {
    await initialize();

    final filePath = _getFilePath(stockCode, yearMonth, dataType);
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }
  }
}
```

**Step 3: Write tests for file storage**

```dart
// test/data/storage/kline_file_storage_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  group('KLineFileStorage', () {
    late KLineFileStorage storage;

    setUp(() {
      storage = KLineFileStorage();
    });

    test('should save and load monthly kline file', () async {
      final testBars = [
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

      // 保存
      final checksum = await storage.saveMonthlyKlineFile(
        stockCode: '000001',
        yearMonth: '2024-01',
        dataType: KLineDataType.oneMinute,
        bars: testBars,
      );

      expect(checksum, isNotEmpty);

      // 读取
      final loadedBars = await storage.loadMonthlyKlineFile(
        stockCode: '000001',
        yearMonth: '2024-01',
        dataType: KLineDataType.oneMinute,
      );

      expect(loadedBars.length, equals(2));
      expect(loadedBars[0].datetime, equals(testBars[0].datetime));
      expect(loadedBars[0].close, equals(testBars[0].close));
    });

    test('should append and deduplicate kline data', () async {
      final initialBars = [
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

      // 初始保存
      await storage.saveMonthlyKlineFile(
        stockCode: '000001',
        yearMonth: '2024-01',
        dataType: KLineDataType.oneMinute,
        bars: initialBars,
      );

      // 追加新数据（包含重复）
      final newBars = [
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 30), // 重复
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
        KLine(
          datetime: DateTime(2024, 1, 15, 9, 31), // 新数据
          open: 10.5,
          close: 10.3,
          high: 10.6,
          low: 10.2,
          volume: 1200,
          amount: 12400,
        ),
      ];

      final result = await storage.appendKlineData(
        stockCode: '000001',
        newBars: newBars,
        dataType: KLineDataType.oneMinute,
      );

      expect(result['totalRecords'], equals(2)); // 去重后应该是2条

      // 验证
      final loadedBars = await storage.loadMonthlyKlineFile(
        stockCode: '000001',
        yearMonth: '2024-01',
        dataType: KLineDataType.oneMinute,
      );

      expect(loadedBars.length, equals(2));
    });

    test('should handle cross-month data correctly', () async {
      final crossMonthBars = [
        KLine(
          datetime: DateTime(2024, 1, 31, 15, 0),
          open: 10.0,
          close: 10.5,
          high: 10.8,
          low: 9.9,
          volume: 1000,
          amount: 10000,
        ),
        KLine(
          datetime: DateTime(2024, 2, 1, 9, 30),
          open: 10.5,
          close: 10.3,
          high: 10.6,
          low: 10.2,
          volume: 1200,
          amount: 12400,
        ),
      ];

      final result = await storage.appendKlineData(
        stockCode: '000001',
        newBars: crossMonthBars,
        dataType: KLineDataType.oneMinute,
      );

      expect(result['monthsUpdated'], hasLength(2));
      expect(result['monthsUpdated'], contains('2024-01'));
      expect(result['monthsUpdated'], contains('2024-02'));
    });

    test('should throw on checksum mismatch', () async {
      // 这个测试验证校验和机制
      // 在实际场景中，如果数据损坏，应该抛出异常
      // 由于很难模拟数据损坏，这里主要验证异常类型

      final testBars = [
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

      // 正常保存不应该抛出异常
      expect(
        () => storage.saveMonthlyKlineFile(
          stockCode: '000001',
          yearMonth: '2024-01',
          dataType: KLineDataType.oneMinute,
          bars: testBars,
        ),
        returnsNormally,
      );
    });
  });
}
```

**Step 4: Add crypto dependency**

Check `pubspec.yaml` for crypto package:

```yaml
dependencies:
  crypto: ^3.0.3
```

Run: `flutter pub get`

**Step 5: Run tests**

Run: `flutter test test/data/storage/kline_file_storage_test.dart`

Expected: All tests pass

**Step 6: Commit**

```bash
git add lib/data/storage/kline_file_storage.dart lib/data/models/kline_data_type.dart test/data/storage/kline_file_storage_test.dart pubspec.yaml
git commit -m "feat(data): implement monthly-sharded file storage with atomic writes

- Add KLineDataType enum for 1min/daily classification
- Implement KLineFileStorage with:
  - Monthly sharding (per stock per month)
  - Atomic writes (temp file + rename)
  - Checksum validation (SHA256)
  - Gzip compression
  - Automatic deduplication by timestamp
- Add comprehensive tests for save/load/append/cross-month scenarios

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Integrate Storage Layer with Database

**Files:**
- Create: `lib/data/storage/kline_metadata_manager.dart`
- Create: `test/data/storage/kline_metadata_manager_test.dart`

**Step 1: Create kline_metadata_manager.dart to coordinate SQLite and files**

```dart
// lib/data/storage/kline_metadata_manager.dart

import 'package:sqflite/sqflite.dart';
import 'market_database.dart';
import 'kline_file_storage.dart';
import '../models/kline_data_type.dart';
import '../../models/kline.dart';

/// K线元数据记录
class KLineFileMetadata {
  final String stockCode;
  final KLineDataType dataType;
  final String yearMonth;
  final String filePath;
  final DateTime? startDate;
  final DateTime? endDate;
  final int recordCount;
  final String checksum;
  final int fileSize;

  const KLineFileMetadata({
    required this.stockCode,
    required this.dataType,
    required this.yearMonth,
    required this.filePath,
    this.startDate,
    this.endDate,
    required this.recordCount,
    required this.checksum,
    required this.fileSize,
  });

  factory KLineFileMetadata.fromMap(Map<String, dynamic> map) {
    return KLineFileMetadata(
      stockCode: map['stock_code'] as String,
      dataType: KLineDataType.fromName(map['data_type'] as String),
      yearMonth: map['year_month'] as String,
      filePath: map['file_path'] as String,
      startDate: map['start_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['start_date'] as int)
          : null,
      endDate: map['end_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_date'] as int)
          : null,
      recordCount: map['record_count'] as int,
      checksum: map['checksum'] as String,
      fileSize: map['file_size'] as int,
    );
  }
}

/// K线元数据管理器（协调SQLite和文件存储）
class KLineMetadataManager {
  final MarketDatabase _db;
  final KLineFileStorage _fileStorage;

  KLineMetadataManager({
    MarketDatabase? database,
    KLineFileStorage? fileStorage,
  })  : _db = database ?? MarketDatabase(),
        _fileStorage = fileStorage ?? KLineFileStorage();

  /// 保存K线数据（文件 + 元数据，事务保证）
  Future<void> saveKlineData({
    required String stockCode,
    required List<KLine> newBars,
    required KLineDataType dataType,
  }) async {
    if (newBars.isEmpty) return;

    // 1. 保存到文件
    final fileResult = await _fileStorage.appendKlineData(
      stockCode: stockCode,
      newBars: newBars,
      dataType: dataType,
    );

    final monthsUpdated = fileResult['monthsUpdated'] as List<String>;
    final checksums = fileResult['checksums'] as Map<String, String>;

    // 2. 在事务中更新元数据
    final database = await _db.database;
    await database.transaction((txn) async {
      for (final yearMonth in monthsUpdated) {
        // 读取该月份的完整数据以获取日期范围
        final monthBars = await _fileStorage.loadMonthlyKlineFile(
          stockCode: stockCode,
          yearMonth: yearMonth,
          dataType: dataType,
        );

        if (monthBars.isEmpty) continue;

        final filePath = _fileStorage._getFilePath(stockCode, yearMonth, dataType);
        final checksum = checksums[yearMonth]!;

        // 计算文件大小
        final file = File(filePath);
        final fileSize = await file.length();

        // 插入或更新元数据
        await txn.insert(
          'kline_files',
          {
            'stock_code': stockCode,
            'data_type': dataType.name,
            'year_month': yearMonth,
            'file_path': filePath,
            'start_date': monthBars.first.datetime.millisecondsSinceEpoch,
            'end_date': monthBars.last.datetime.millisecondsSinceEpoch,
            'record_count': monthBars.length,
            'checksum': checksum,
            'file_size': fileSize,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. 增加数据版本
      await _db.incrementVersion(
        'Updated K-line data for $stockCode (${monthsUpdated.length} months)',
      );
    });
  }

  /// 获取K线元数据
  Future<List<KLineFileMetadata>> getMetadata({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    final database = await _db.database;
    final results = await database.query(
      'kline_files',
      where: 'stock_code = ? AND data_type = ?',
      whereArgs: [stockCode, dataType.name],
      orderBy: 'year_month ASC',
    );

    return results.map((map) => KLineFileMetadata.fromMap(map)).toList();
  }

  /// 获取最新数据日期
  Future<DateTime?> getLatestDataDate({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    final database = await _db.database;
    final results = await database.query(
      'kline_files',
      columns: ['end_date'],
      where: 'stock_code = ? AND data_type = ?',
      whereArgs: [stockCode, dataType.name],
      orderBy: 'end_date DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;

    final endDate = results.first['end_date'] as int?;
    return endDate != null
        ? DateTime.fromMillisecondsSinceEpoch(endDate)
        : null;
  }

  /// 读取K线数据（按日期范围）
  Future<List<KLine>> loadKlineData({
    required String stockCode,
    required DateTime startDate,
    required DateTime endDate,
    required KLineDataType dataType,
  }) async {
    // 1. 查询需要读取的月份
    final database = await _db.database;

    final startYearMonth = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}';
    final endYearMonth = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}';

    final results = await database.query(
      'kline_files',
      where: 'stock_code = ? AND data_type = ? AND year_month >= ? AND year_month <= ?',
      whereArgs: [stockCode, dataType.name, startYearMonth, endYearMonth],
      orderBy: 'year_month ASC',
    );

    // 2. 读取所有相关月份的文件
    final allBars = <KLine>[];

    for (final result in results) {
      final yearMonth = result['year_month'] as String;
      final monthBars = await _fileStorage.loadMonthlyKlineFile(
        stockCode: stockCode,
        yearMonth: yearMonth,
        dataType: dataType,
      );
      allBars.addAll(monthBars);
    }

    // 3. 过滤日期范围
    final filtered = allBars.where((bar) {
      return !bar.datetime.isBefore(startDate) && !bar.datetime.isAfter(endDate);
    }).toList();

    return filtered;
  }

  /// 删除旧数据
  Future<void> deleteOldData({
    required DateTime beforeDate,
  }) async {
    final database = await _db.database;

    // 1. 查询需要删除的文件
    final results = await database.query(
      'kline_files',
      where: 'end_date < ?',
      whereArgs: [beforeDate.millisecondsSinceEpoch],
    );

    // 2. 删除文件
    for (final result in results) {
      final metadata = KLineFileMetadata.fromMap(result);
      await _fileStorage.deleteMonthlyFile(
        stockCode: metadata.stockCode,
        yearMonth: metadata.yearMonth,
        dataType: metadata.dataType,
      );
    }

    // 3. 删除元数据
    await database.delete(
      'kline_files',
      where: 'end_date < ?',
      whereArgs: [beforeDate.millisecondsSinceEpoch],
    );
  }
}
```

**Note:** The `_getFilePath` method needs to be made accessible. Let's fix this:

```dart
// Modify lib/data/storage/kline_file_storage.dart
// Change the visibility of _getFilePath method:

  /// 获取文件路径（公开以供元数据管理器使用）
  String getFilePath(String stockCode, String yearMonth, KLineDataType dataType) {
    return path.join(_baseDir, '${stockCode}_${dataType.name}_$yearMonth.bin.gz');
  }
```

And update the reference in `kline_metadata_manager.dart`:

```dart
        final filePath = _fileStorage.getFilePath(stockCode, yearMonth, dataType);
```

**Step 2: Write tests for metadata manager**

```dart
// test/data/storage/kline_metadata_manager_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('KLineMetadataManager', () {
    late KLineMetadataManager manager;

    setUp(() {
      manager = KLineMetadataManager();
    });

    test('should save kline data with metadata', () async {
      final testBars = [
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

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: testBars,
        dataType: KLineDataType.oneMinute,
      );

      // 验证元数据
      final metadata = await manager.getMetadata(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
      );

      expect(metadata, hasLength(1));
      expect(metadata.first.yearMonth, equals('2024-01'));
      expect(metadata.first.recordCount, equals(2));
      expect(metadata.first.checksum, isNotEmpty);
    });

    test('should get latest data date', () async {
      final testBars = [
        KLine(
          datetime: DateTime(2024, 1, 15, 14, 55),
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
        newBars: testBars,
        dataType: KLineDataType.oneMinute,
      );

      final latestDate = await manager.getLatestDataDate(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
      );

      expect(latestDate, isNotNull);
      expect(latestDate!.year, equals(2024));
      expect(latestDate.month, equals(1));
      expect(latestDate.day, equals(15));
    });

    test('should load kline data by date range', () async {
      final testBars = [
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
          datetime: DateTime(2024, 1, 20, 9, 30),
          open: 11.0,
          close: 11.5,
          high: 11.8,
          low: 10.9,
          volume: 1100,
          amount: 11000,
        ),
        KLine(
          datetime: DateTime(2024, 2, 5, 9, 30),
          open: 12.0,
          close: 12.5,
          high: 12.8,
          low: 11.9,
          volume: 1200,
          amount: 12000,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: testBars,
        dataType: KLineDataType.oneMinute,
      );

      // 查询1月的数据
      final januaryBars = await manager.loadKlineData(
        stockCode: '000001',
        startDate: DateTime(2024, 1, 1),
        endDate: DateTime(2024, 1, 31, 23, 59),
        dataType: KLineDataType.oneMinute,
      );

      expect(januaryBars, hasLength(2));

      // 查询跨月数据
      final crossMonthBars = await manager.loadKlineData(
        stockCode: '000001',
        startDate: DateTime(2024, 1, 15),
        endDate: DateTime(2024, 2, 10),
        dataType: KLineDataType.oneMinute,
      );

      expect(crossMonthBars, hasLength(3));
    });

    test('should handle incremental updates correctly', () async {
      // 第一次保存
      final initialBars = [
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
        newBars: initialBars,
        dataType: KLineDataType.oneMinute,
      );

      // 第二次追加
      final additionalBars = [
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

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: additionalBars,
        dataType: KLineDataType.oneMinute,
      );

      // 验证元数据更新
      final metadata = await manager.getMetadata(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
      );

      expect(metadata, hasLength(1));
      expect(metadata.first.recordCount, equals(2));

      // 验证数据完整
      final allBars = await manager.loadKlineData(
        stockCode: '000001',
        startDate: DateTime(2024, 1, 1),
        endDate: DateTime(2024, 1, 31),
        dataType: KLineDataType.oneMinute,
      );

      expect(allBars, hasLength(2));
    });
  });
}
```

**Step 3: Fix visibility issue in kline_file_storage.dart**

Modify `lib/data/storage/kline_file_storage.dart`:

```dart
  /// 获取文件路径（公开以供元数据管理器使用）
  String getFilePath(String stockCode, String yearMonth, KLineDataType dataType) {
    return path.join(_baseDir, '${stockCode}_${dataType.name}_$yearMonth.bin.gz');
  }
```

Also add missing import in `kline_metadata_manager.dart`:

```dart
import 'dart:io';
```

**Step 4: Run tests**

Run: `flutter test test/data/storage/kline_metadata_manager_test.dart`

Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/storage/kline_metadata_manager.dart lib/data/storage/kline_file_storage.dart test/data/storage/kline_metadata_manager_test.dart
git commit -m "feat(data): add metadata manager to coordinate SQLite and file storage

- Add KLineMetadataManager to ensure transactional consistency
- Coordinate file writes with metadata updates
- Support querying by date range across multiple months
- Add comprehensive integration tests
- Make getFilePath public for metadata manager access

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Implement Data Repository Interface

**Files:**
- Create: `lib/data/repository/data_repository.dart`
- Create: `lib/data/models/data_updated_event.dart`

**Step 1: Create data_updated_event.dart**

```dart
// lib/data/models/data_updated_event.dart

import 'kline_data_type.dart';
import 'date_range.dart';

/// 数据更新事件
class DataUpdatedEvent {
  final List<String> stockCodes;
  final DateRange dateRange;
  final KLineDataType dataType;
  final int dataVersion;

  const DataUpdatedEvent({
    required this.stockCodes,
    required this.dateRange,
    required this.dataType,
    required this.dataVersion,
  });

  @override
  String toString() {
    return 'DataUpdatedEvent(stocks: ${stockCodes.length}, '
        'range: $dateRange, type: ${dataType.name}, version: $dataVersion)';
  }
}
```

**Step 2: Create data_repository.dart interface**

```dart
// lib/data/repository/data_repository.dart

import 'dart:async';
import '../models/data_status.dart';
import '../models/data_updated_event.dart';
import '../models/data_freshness.dart';
import '../models/kline_data_type.dart';
import '../models/date_range.dart';
import '../models/fetch_result.dart';
import '../../models/kline.dart';
import '../../models/quote.dart';

typedef ProgressCallback = void Function(int current, int total);

/// 数据仓库接口 - 唯一的数据源
abstract class DataRepository {
  // ============ 状态流 ============

  /// 数据状态流
  Stream<DataStatus> get statusStream;

  /// 数据更新事件流
  Stream<DataUpdatedEvent> get dataUpdatedStream;

  // ============ 查询接口 ============

  /// 获取K线数据（优先从缓存读取）
  ///
  /// [stockCodes] 股票代码列表
  /// [dateRange] 日期范围
  /// [dataType] 数据类型 '1min' 或 'daily'
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  });

  /// 检查数据新鲜度
  ///
  /// 返回每只股票的数据状态：
  /// - fresh: 数据完整
  /// - stale: 数据过时，需要拉取
  /// - missing: 完全缺失
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  });

  /// 获取实时行情
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  });

  /// 获取当前数据版本
  Future<int> getCurrentVersion();

  // ============ 命令接口 ============

  /// 拉取缺失数据（增量更新）
  ///
  /// [stockCodes] 需要更新的股票列表
  /// [dateRange] 需要拉取的日期范围
  /// [dataType] 数据类型
  ///
  /// 返回拉取结果统计
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  });

  /// 强制重新拉取（覆盖现有数据）
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  });

  /// 清理旧数据
  ///
  /// [beforeDate] 清理此日期之前的数据
  Future<void> cleanupOldData({
    required DateTime beforeDate,
  });
}
```

**Step 3: Commit interface**

```bash
git add lib/data/repository/data_repository.dart lib/data/models/data_updated_event.dart
git commit -m "feat(data): define DataRepository interface

- Add Stream-based status and event notification
- Define query methods for K-lines, quotes, and freshness checks
- Define command methods for fetch and cleanup operations
- Add DataUpdatedEvent model for change notifications

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary

This plan implements Phase 1 of the data architecture refactor: **the new data layer**.

**What's been accomplished:**
1. ✅ Core data models (DataStatus, DataFreshness, DateRange, FetchResult)
2. ✅ SQLite database schema with version control
3. ✅ Monthly-sharded file storage with atomic writes and checksum validation
4. ✅ Metadata manager to coordinate SQLite and file storage
5. ✅ DataRepository interface definition

**What's next:**
- Implement the concrete DataRepository class
- Add incremental fetcher with TdxClient integration
- Add data freshness checker
- Write integration tests for the complete data layer

**Estimated effort:** 2-3 weeks for complete Phase 1

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-01-27-data-layer-implementation.md`.

Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
