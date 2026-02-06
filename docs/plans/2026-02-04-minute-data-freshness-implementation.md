# Minute Data Freshness Detection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement precise minute K-line data missing detection with caching to avoid repeated full scans.

**Architecture:** Add a `date_check_status` table to cache per-date detection results. New `findMissingMinuteDates` API scans data and writes cache; existing `checkFreshness` reads from cache. Trading days are inferred from daily K-line data.

**Tech Stack:** Flutter/Dart, sqflite, existing KLineFileStorage and KLineMetadataManager

**Design Doc:** `docs/plans/2026-02-04-minute-data-freshness-design.md`

---

## Task 1: Add DayDataStatus enum and MissingDatesResult model

**Files:**
- Create: `lib/data/models/day_data_status.dart`
- Test: `test/data/models/day_data_status_test.dart`

**Step 1: Write the failing test**

Create `test/data/models/day_data_status_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';

void main() {
  group('DayDataStatus', () {
    test('should have all expected values', () {
      expect(DayDataStatus.values, contains(DayDataStatus.complete));
      expect(DayDataStatus.values, contains(DayDataStatus.incomplete));
      expect(DayDataStatus.values, contains(DayDataStatus.missing));
      expect(DayDataStatus.values, contains(DayDataStatus.inProgress));
    });
  });

  group('MissingDatesResult', () {
    test('isComplete returns true when no missing or incomplete dates', () {
      final result = MissingDatesResult(
        missingDates: [],
        incompleteDates: [],
        completeDates: [DateTime(2026, 1, 15)],
      );

      expect(result.isComplete, isTrue);
    });

    test('isComplete returns false when has missing dates', () {
      final result = MissingDatesResult(
        missingDates: [DateTime(2026, 1, 16)],
        incompleteDates: [],
        completeDates: [DateTime(2026, 1, 15)],
      );

      expect(result.isComplete, isFalse);
    });

    test('isComplete returns false when has incomplete dates', () {
      final result = MissingDatesResult(
        missingDates: [],
        incompleteDates: [DateTime(2026, 1, 16)],
        completeDates: [DateTime(2026, 1, 15)],
      );

      expect(result.isComplete, isFalse);
    });

    test('datesToFetch combines missing and incomplete dates sorted', () {
      final jan15 = DateTime(2026, 1, 15);
      final jan16 = DateTime(2026, 1, 16);
      final jan17 = DateTime(2026, 1, 17);

      final result = MissingDatesResult(
        missingDates: [jan17],
        incompleteDates: [jan15],
        completeDates: [jan16],
      );

      expect(result.datesToFetch, equals([jan15, jan17]));
    });

    test('fetchCount returns sum of missing and incomplete', () {
      final result = MissingDatesResult(
        missingDates: [DateTime(2026, 1, 15), DateTime(2026, 1, 16)],
        incompleteDates: [DateTime(2026, 1, 17)],
        completeDates: [],
      );

      expect(result.fetchCount, equals(3));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/day_data_status_test.dart`
Expected: FAIL with "Target of URI hasn't been generated"

**Step 3: Write minimal implementation**

Create `lib/data/models/day_data_status.dart`:

```dart
/// 单日数据状态
enum DayDataStatus {
  /// 数据完整（分钟K线 >= 220）
  complete,

  /// 历史日期数据不完整（< 220，需要补全）
  incomplete,

  /// 完全没有数据
  missing,

  /// 当天，交易进行中（不视为缺失，不缓存）
  inProgress,
}

/// 日期缺失检测结果
class MissingDatesResult {
  /// 缺失的日期列表（完全没有数据）
  final List<DateTime> missingDates;

  /// 不完整的日期列表（数据 < 220，需要重新拉取）
  final List<DateTime> incompleteDates;

  /// 完整的日期列表
  final List<DateTime> completeDates;

  const MissingDatesResult({
    required this.missingDates,
    required this.incompleteDates,
    required this.completeDates,
  });

  /// 是否全部完整
  bool get isComplete => missingDates.isEmpty && incompleteDates.isEmpty;

  /// 需要拉取的日期（合并 missing + incomplete，已排序）
  List<DateTime> get datesToFetch =>
      [...missingDates, ...incompleteDates]..sort();

  /// 需要拉取的日期数量
  int get fetchCount => missingDates.length + incompleteDates.length;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/day_data_status_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/models/day_data_status.dart test/data/models/day_data_status_test.dart
git commit -m "$(cat <<'EOF'
feat: add DayDataStatus enum and MissingDatesResult model

Adds data models for minute data freshness detection:
- DayDataStatus: complete/incomplete/missing/inProgress
- MissingDatesResult: holds detection results with helper methods

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Update database schema to version 2

**Files:**
- Modify: `lib/data/storage/database_schema.dart`
- Test: `test/data/storage/market_database_test.dart`

**Step 1: Write the failing test**

Add to `test/data/storage/market_database_test.dart`:

```dart
group('Database schema version 2', () {
  test('should have date_check_status table after initialization', () async {
    final db = await database.database;

    // Query sqlite_master to check if table exists
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='date_check_status'"
    );

    expect(tables, isNotEmpty);
    expect(tables.first['name'], equals('date_check_status'));
  });

  test('date_check_status table should have correct columns', () async {
    final db = await database.database;

    final columns = await db.rawQuery("PRAGMA table_info(date_check_status)");
    final columnNames = columns.map((c) => c['name'] as String).toList();

    expect(columnNames, contains('stock_code'));
    expect(columnNames, contains('data_type'));
    expect(columnNames, contains('date'));
    expect(columnNames, contains('status'));
    expect(columnNames, contains('bar_count'));
    expect(columnNames, contains('checked_at'));
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/market_database_test.dart`
Expected: FAIL - table does not exist

**Step 3: Write minimal implementation**

Modify `lib/data/storage/database_schema.dart`:

```dart
class DatabaseSchema {
  static const int version = 2;  // Changed from 1
  static const String databaseName = 'market_data.db';

  // ... existing table definitions ...

  // 日期检测状态表（新增）
  static const String createDateCheckStatusTable = '''
    CREATE TABLE date_check_status (
      stock_code TEXT NOT NULL,
      data_type TEXT NOT NULL,
      date INTEGER NOT NULL,
      status TEXT NOT NULL,
      bar_count INTEGER DEFAULT 0,
      checked_at INTEGER NOT NULL,
      PRIMARY KEY (stock_code, data_type, date)
    )
  ''';

  static const String createDateCheckStatusIndex = '''
    CREATE INDEX idx_date_check_pending
    ON date_check_status(stock_code, data_type, status)
    WHERE status != 'complete'
  ''';
}
```

Modify `lib/data/storage/market_database.dart` `_onCreate`:

```dart
Future<void> _onCreate(Database db, int version) async {
  // 创建表
  await db.execute(DatabaseSchema.createStocksTable);
  await db.execute(DatabaseSchema.createKlineFilesTable);
  await db.execute(DatabaseSchema.createDataVersionsTable);
  await db.execute(DatabaseSchema.createDateCheckStatusTable);  // 新增

  // 创建索引
  await db.execute(DatabaseSchema.createKlineFilesStockIndex);
  await db.execute(DatabaseSchema.createKlineFilesDateIndex);
  await db.execute(DatabaseSchema.createDateCheckStatusIndex);  // 新增

  // 插入初始版本
  await db.rawInsert(
    DatabaseSchema.insertInitialVersion,
    [DateTime.now().millisecondsSinceEpoch],
  );
}
```

Modify `lib/data/storage/market_database.dart` `_onUpgrade`:

```dart
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    // Version 1 -> 2: Add date_check_status table
    await db.execute(DatabaseSchema.createDateCheckStatusTable);
    await db.execute(DatabaseSchema.createDateCheckStatusIndex);
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/market_database_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/storage/database_schema.dart lib/data/storage/market_database.dart test/data/storage/market_database_test.dart
git commit -m "$(cat <<'EOF'
feat: add date_check_status table for freshness detection cache

Database schema version 2:
- New date_check_status table to cache per-date detection results
- Partial index for fast pending date queries
- Migration from version 1

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create DateCheckStorage class

**Files:**
- Create: `lib/data/storage/date_check_storage.dart`
- Test: `test/data/storage/date_check_storage_test.dart`

**Step 1: Write the failing test**

Create `test/data/storage/date_check_storage_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/storage/date_check_storage.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';

void main() {
  late DateCheckStorage storage;
  late MarketDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    database = MarketDatabase();
    await database.database;
    storage = DateCheckStorage(database: database);
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {}
    MarketDatabase.resetInstance();

    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/market_data.db';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  group('DateCheckStorage', () {
    test('saveCheckStatus and getCheckedStatus round trip', () async {
      final date = DateTime(2026, 1, 15);

      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: date,
        status: DayDataStatus.complete,
        barCount: 240,
      );

      final result = await storage.getCheckedStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        dates: [date],
      );

      expect(result[date], equals(DayDataStatus.complete));
    });

    test('getCheckedStatus returns null for unchecked dates', () async {
      final date = DateTime(2026, 1, 15);

      final result = await storage.getCheckedStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        dates: [date],
      );

      expect(result[date], isNull);
    });

    test('getPendingDates returns incomplete and missing dates', () async {
      final jan15 = DateTime(2026, 1, 15);
      final jan16 = DateTime(2026, 1, 16);
      final jan17 = DateTime(2026, 1, 17);

      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: jan15,
        status: DayDataStatus.complete,
        barCount: 240,
      );
      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: jan16,
        status: DayDataStatus.incomplete,
        barCount: 100,
      );
      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: jan17,
        status: DayDataStatus.missing,
        barCount: 0,
      );

      final pending = await storage.getPendingDates(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
      );

      expect(pending, containsAll([jan16, jan17]));
      expect(pending, isNot(contains(jan15)));
    });

    test('getPendingDates excludes today when excludeToday is true', () async {
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);

      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: todayOnly,
        status: DayDataStatus.incomplete,
        barCount: 50,
      );

      final pendingWithToday = await storage.getPendingDates(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        excludeToday: false,
      );

      final pendingWithoutToday = await storage.getPendingDates(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        excludeToday: true,
      );

      expect(pendingWithToday, contains(todayOnly));
      expect(pendingWithoutToday, isNot(contains(todayOnly)));
    });

    test('getLatestCheckedDate returns most recent complete date', () async {
      final jan15 = DateTime(2026, 1, 15);
      final jan16 = DateTime(2026, 1, 16);

      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: jan15,
        status: DayDataStatus.complete,
        barCount: 240,
      );
      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: jan16,
        status: DayDataStatus.complete,
        barCount: 235,
      );

      final latest = await storage.getLatestCheckedDate(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
      );

      expect(latest, equals(jan16));
    });

    test('getLatestCheckedDate returns null when no data', () async {
      final latest = await storage.getLatestCheckedDate(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
      );

      expect(latest, isNull);
    });

    test('saveCheckStatus updates existing record', () async {
      final date = DateTime(2026, 1, 15);

      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: date,
        status: DayDataStatus.incomplete,
        barCount: 100,
      );

      await storage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: date,
        status: DayDataStatus.complete,
        barCount: 240,
      );

      final result = await storage.getCheckedStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        dates: [date],
      );

      expect(result[date], equals(DayDataStatus.complete));
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/date_check_storage_test.dart`
Expected: FAIL - DateCheckStorage not found

**Step 3: Write minimal implementation**

Create `lib/data/storage/date_check_storage.dart`:

```dart
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';

/// 日期检测状态存储
class DateCheckStorage {
  final MarketDatabase _database;

  DateCheckStorage({MarketDatabase? database})
      : _database = database ?? MarketDatabase();

  /// 保存检测状态
  Future<void> saveCheckStatus({
    required String stockCode,
    required KLineDataType dataType,
    required DateTime date,
    required DayDataStatus status,
    required int barCount,
  }) async {
    final db = await _database.database;
    final dateOnly = DateTime(date.year, date.month, date.day);

    await db.insert(
      'date_check_status',
      {
        'stock_code': stockCode,
        'data_type': dataType.name,
        'date': dateOnly.millisecondsSinceEpoch,
        'status': status.name,
        'bar_count': barCount,
        'checked_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 查询多个日期的检测状态
  Future<Map<DateTime, DayDataStatus?>> getCheckedStatus({
    required String stockCode,
    required KLineDataType dataType,
    required List<DateTime> dates,
  }) async {
    if (dates.isEmpty) return {};

    final db = await _database.database;
    final result = <DateTime, DayDataStatus?>{};

    // Initialize all dates as null
    for (final date in dates) {
      final dateOnly = DateTime(date.year, date.month, date.day);
      result[dateOnly] = null;
    }

    // Query database
    final dateTimestamps = dates
        .map((d) => DateTime(d.year, d.month, d.day).millisecondsSinceEpoch)
        .toList();

    final placeholders = List.filled(dateTimestamps.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT date, status FROM date_check_status
      WHERE stock_code = ? AND data_type = ? AND date IN ($placeholders)
      ''',
      [stockCode, dataType.name, ...dateTimestamps],
    );

    for (final row in rows) {
      final dateMs = row['date'] as int;
      final statusName = row['status'] as String;
      final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
      result[date] = DayDataStatus.values.byName(statusName);
    }

    return result;
  }

  /// 获取未完成的日期（incomplete 或 missing）
  Future<List<DateTime>> getPendingDates({
    required String stockCode,
    required KLineDataType dataType,
    bool excludeToday = false,
  }) async {
    final db = await _database.database;

    String query = '''
      SELECT date FROM date_check_status
      WHERE stock_code = ? AND data_type = ? AND status != 'complete'
    ''';

    final args = <dynamic>[stockCode, dataType.name];

    if (excludeToday) {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      query += ' AND date < ?';
      args.add(todayStart.millisecondsSinceEpoch);
    }

    query += ' ORDER BY date';

    final rows = await db.rawQuery(query, args);

    return rows.map((row) {
      final dateMs = row['date'] as int;
      return DateTime.fromMillisecondsSinceEpoch(dateMs);
    }).toList();
  }

  /// 获取最新的已检测完成日期
  Future<DateTime?> getLatestCheckedDate({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    final db = await _database.database;

    final rows = await db.rawQuery(
      '''
      SELECT date FROM date_check_status
      WHERE stock_code = ? AND data_type = ? AND status = 'complete'
      ORDER BY date DESC
      LIMIT 1
      ''',
      [stockCode, dataType.name],
    );

    if (rows.isEmpty) return null;

    final dateMs = rows.first['date'] as int;
    return DateTime.fromMillisecondsSinceEpoch(dateMs);
  }
}
```

Add import to file:

```dart
import 'package:sqflite/sqflite.dart';
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/date_check_storage_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/storage/date_check_storage.dart test/data/storage/date_check_storage_test.dart
git commit -m "$(cat <<'EOF'
feat: add DateCheckStorage for caching detection results

Implements CRUD operations for date_check_status table:
- saveCheckStatus: insert/update detection result
- getCheckedStatus: batch query by dates
- getPendingDates: get incomplete/missing dates
- getLatestCheckedDate: get most recent complete date

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add getTradingDates to KLineMetadataManager

**Files:**
- Modify: `lib/data/storage/kline_metadata_manager.dart`
- Test: `test/data/storage/kline_metadata_manager_test.dart`

**Step 1: Write the failing test**

Add to `test/data/storage/kline_metadata_manager_test.dart`:

```dart
group('getTradingDates', () {
  test('returns unique dates from daily kline data', () async {
    // Save daily data for two different days
    final jan15 = DateTime(2026, 1, 15);
    final jan16 = DateTime(2026, 1, 16);

    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [_createKLine(jan15, 10.0)],
      dataType: KLineDataType.daily,
    );
    await manager.saveKlineData(
      stockCode: '000002',
      newBars: [_createKLine(jan15, 11.0), _createKLine(jan16, 11.5)],
      dataType: KLineDataType.daily,
    );

    final tradingDates = await manager.getTradingDates(
      DateRange(jan15, jan16),
    );

    expect(tradingDates, containsAll([jan15, jan16]));
    expect(tradingDates.length, equals(2));
  });

  test('returns empty list when no daily data', () async {
    final tradingDates = await manager.getTradingDates(
      DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31)),
    );

    expect(tradingDates, isEmpty);
  });

  test('returns dates within range only', () async {
    final jan14 = DateTime(2026, 1, 14);
    final jan15 = DateTime(2026, 1, 15);
    final jan16 = DateTime(2026, 1, 16);

    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [
        _createKLine(jan14, 10.0),
        _createKLine(jan15, 10.5),
        _createKLine(jan16, 11.0),
      ],
      dataType: KLineDataType.daily,
    );

    final tradingDates = await manager.getTradingDates(
      DateRange(jan15, jan15),
    );

    expect(tradingDates, equals([jan15]));
  });
});

KLine _createKLine(DateTime datetime, double price) {
  return KLine(
    datetime: datetime,
    open: price,
    close: price + 0.05,
    high: price + 0.1,
    low: price - 0.05,
    volume: 1000,
    amount: 10000,
  );
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/kline_metadata_manager_test.dart`
Expected: FAIL - getTradingDates not defined

**Step 3: Write minimal implementation**

Add to `lib/data/storage/kline_metadata_manager.dart`:

```dart
/// 获取交易日列表（从日K数据推断）
///
/// 某天只要有任意股票有日K数据，就认为是交易日
Future<List<DateTime>> getTradingDates(DateRange range) async {
  final database = await _db.database;

  // Query all daily kline files that overlap with the range
  final rows = await database.query(
    'kline_files',
    columns: ['start_date', 'end_date'],
    where: 'data_type = ? AND end_date >= ? AND start_date <= ?',
    whereArgs: [
      KLineDataType.daily.name,
      range.start.millisecondsSinceEpoch,
      range.end.millisecondsSinceEpoch,
    ],
  );

  if (rows.isEmpty) return [];

  // Collect all unique dates
  final tradingDates = <DateTime>{};

  for (final row in rows) {
    final startMs = row['start_date'] as int?;
    final endMs = row['end_date'] as int?;

    if (startMs == null || endMs == null) continue;

    // For daily data, each record represents one day
    // We need to load the actual files to get exact dates
    // But for efficiency, we can infer from metadata
    var current = DateTime.fromMillisecondsSinceEpoch(startMs);
    final end = DateTime.fromMillisecondsSinceEpoch(endMs);

    while (!current.isAfter(end)) {
      final dateOnly = DateTime(current.year, current.month, current.day);
      if (range.contains(dateOnly)) {
        tradingDates.add(dateOnly);
      }
      current = current.add(const Duration(days: 1));
    }
  }

  final sortedDates = tradingDates.toList()..sort();
  return sortedDates;
}
```

Add import at top:

```dart
import 'package:stock_rtwatcher/data/models/date_range.dart';
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/kline_metadata_manager_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/storage/kline_metadata_manager.dart test/data/storage/kline_metadata_manager_test.dart
git commit -m "$(cat <<'EOF'
feat: add getTradingDates to infer trading days from daily K-line

Uses daily K-line metadata to determine which dates were trading days.
Any date with daily K-line data from any stock is considered a trading day.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add countBarsForDate to KLineMetadataManager

**Files:**
- Modify: `lib/data/storage/kline_metadata_manager.dart`
- Test: `test/data/storage/kline_metadata_manager_test.dart`

**Step 1: Write the failing test**

Add to `test/data/storage/kline_metadata_manager_test.dart`:

```dart
group('countBarsForDate', () {
  test('returns correct count for a date with data', () async {
    final date = DateTime(2026, 1, 15);

    // Create 50 minute bars for the day
    final klines = <KLine>[];
    for (var i = 0; i < 50; i++) {
      klines.add(_createKLine(
        DateTime(date.year, date.month, date.day, 9, 30 + i),
        10.0 + i * 0.01,
      ));
    }

    await manager.saveKlineData(
      stockCode: '000001',
      newBars: klines,
      dataType: KLineDataType.oneMinute,
    );

    final count = await manager.countBarsForDate(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: date,
    );

    expect(count, equals(50));
  });

  test('returns 0 for a date with no data', () async {
    final count = await manager.countBarsForDate(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: DateTime(2026, 1, 15),
    );

    expect(count, equals(0));
  });

  test('counts only bars for the specified date', () async {
    final jan15 = DateTime(2026, 1, 15);
    final jan16 = DateTime(2026, 1, 16);

    // Create bars for two days
    final klines = [
      _createKLine(DateTime(jan15.year, jan15.month, jan15.day, 10, 0), 10.0),
      _createKLine(DateTime(jan15.year, jan15.month, jan15.day, 10, 1), 10.1),
      _createKLine(DateTime(jan16.year, jan16.month, jan16.day, 10, 0), 11.0),
    ];

    await manager.saveKlineData(
      stockCode: '000001',
      newBars: klines,
      dataType: KLineDataType.oneMinute,
    );

    final countJan15 = await manager.countBarsForDate(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: jan15,
    );

    final countJan16 = await manager.countBarsForDate(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: jan16,
    );

    expect(countJan15, equals(2));
    expect(countJan16, equals(1));
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/kline_metadata_manager_test.dart`
Expected: FAIL - countBarsForDate not defined

**Step 3: Write minimal implementation**

Add to `lib/data/storage/kline_metadata_manager.dart`:

```dart
/// 统计指定日期的K线数量
///
/// [stockCode] 股票代码
/// [dataType] 数据类型
/// [date] 日期（只使用年月日部分）
Future<int> countBarsForDate({
  required String stockCode,
  required KLineDataType dataType,
  required DateTime date,
}) async {
  final dateOnly = DateTime(date.year, date.month, date.day);
  final nextDay = dateOnly.add(const Duration(days: 1));

  // Load the month's data
  final klines = await _fileStorage.loadMonthlyKlineFile(
    stockCode,
    dataType,
    date.year,
    date.month,
  );

  // Count bars for the specific date
  return klines.where((k) {
    return !k.datetime.isBefore(dateOnly) && k.datetime.isBefore(nextDay);
  }).length;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/kline_metadata_manager_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/storage/kline_metadata_manager.dart test/data/storage/kline_metadata_manager_test.dart
git commit -m "$(cat <<'EOF'
feat: add countBarsForDate to count K-lines for a specific date

Counts the number of K-line bars for a given stock and date.
Used by freshness detection to determine if data is complete (>= 220).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Update DataRepository interface

**Files:**
- Modify: `lib/data/repository/data_repository.dart`

**Step 1: No failing test needed - interface only**

**Step 2: Write implementation**

Add to `lib/data/repository/data_repository.dart`:

```dart
import '../models/day_data_status.dart';

// Inside abstract class DataRepository, add:

  /// 查找缺失的分钟数据日期
  ///
  /// [stockCode] 股票代码
  /// [dateRange] 检测的日期范围
  ///
  /// 利用缓存加速：已标记为 complete 的日期会跳过
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  });

  /// 批量查找多只股票的缺失日期
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  });

  /// 获取交易日列表（从日K数据推断）
  ///
  /// 某天只要有任意股票有日K数据，就认为是交易日
  Future<List<DateTime>> getTradingDates(DateRange dateRange);
```

**Step 3: Run existing tests to ensure nothing broke**

Run: `flutter test test/data/repository/market_data_repository_test.dart`
Expected: FAIL - MarketDataRepository missing new methods

**Step 4: Commit**

```bash
git add lib/data/repository/data_repository.dart
git commit -m "$(cat <<'EOF'
feat: add findMissingMinuteDates API to DataRepository interface

New interface methods:
- findMissingMinuteDates: detect missing minute data for one stock
- findMissingMinuteDatesBatch: batch detection for multiple stocks
- getTradingDates: get trading days from daily K-line data

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Implement findMissingMinuteDates in MarketDataRepository

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Test: `test/data/repository/data_freshness_test.dart`

**Step 1: Write the failing test**

Update `test/data/repository/data_freshness_test.dart`, add new group:

```dart
group('findMissingMinuteDates', () {
  test('detects missing dates correctly', () async {
    // Save daily data to define trading days
    final jan15 = DateTime(2026, 1, 15);
    final jan16 = DateTime(2026, 1, 16);
    final jan17 = DateTime(2026, 1, 17);

    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [
        _createKLine(jan15, 10.0),
        _createKLine(jan16, 10.5),
        _createKLine(jan17, 11.0),
      ],
      dataType: KLineDataType.daily,
    );

    // Save complete minute data for jan15 only (220+ bars)
    final jan15Minutes = <KLine>[];
    for (var i = 0; i < 230; i++) {
      jan15Minutes.add(_createKLine(
        DateTime(2026, 1, 15, 9, 30).add(Duration(minutes: i)),
        10.0 + i * 0.001,
      ));
    }
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: jan15Minutes,
      dataType: KLineDataType.oneMinute,
    );

    // jan16 and jan17 have no minute data

    final result = await repository.findMissingMinuteDates(
      stockCode: '000001',
      dateRange: DateRange(jan15, jan17),
    );

    expect(result.completeDates, contains(jan15));
    expect(result.missingDates, containsAll([jan16, jan17]));
    expect(result.isComplete, isFalse);
  });

  test('detects incomplete dates (< 220 bars)', () async {
    final jan15 = DateTime(2026, 1, 15);

    // Define trading day
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [_createKLine(jan15, 10.0)],
      dataType: KLineDataType.daily,
    );

    // Save incomplete minute data (only 100 bars)
    final incompleteMinutes = <KLine>[];
    for (var i = 0; i < 100; i++) {
      incompleteMinutes.add(_createKLine(
        DateTime(2026, 1, 15, 9, 30).add(Duration(minutes: i)),
        10.0 + i * 0.001,
      ));
    }
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: incompleteMinutes,
      dataType: KLineDataType.oneMinute,
    );

    final result = await repository.findMissingMinuteDates(
      stockCode: '000001',
      dateRange: DateRange(jan15, jan15),
    );

    expect(result.incompleteDates, contains(jan15));
    expect(result.completeDates, isEmpty);
  });

  test('caches detection results and skips complete dates', () async {
    final jan15 = DateTime(2026, 1, 15);

    // Define trading day
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [_createKLine(jan15, 10.0)],
      dataType: KLineDataType.daily,
    );

    // Save complete minute data
    final completeMinutes = <KLine>[];
    for (var i = 0; i < 230; i++) {
      completeMinutes.add(_createKLine(
        DateTime(2026, 1, 15, 9, 30).add(Duration(minutes: i)),
        10.0 + i * 0.001,
      ));
    }
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: completeMinutes,
      dataType: KLineDataType.oneMinute,
    );

    // First detection
    final result1 = await repository.findMissingMinuteDates(
      stockCode: '000001',
      dateRange: DateRange(jan15, jan15),
    );
    expect(result1.completeDates, contains(jan15));

    // Second detection should use cache (verify via result)
    final result2 = await repository.findMissingMinuteDates(
      stockCode: '000001',
      dateRange: DateRange(jan15, jan15),
    );
    expect(result2.completeDates, contains(jan15));
    expect(result2.isComplete, isTrue);
  });

  test('treats today as inProgress when incomplete', () async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Define today as trading day
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [_createKLine(todayDate, 10.0)],
      dataType: KLineDataType.daily,
    );

    // Save incomplete minute data for today (50 bars)
    final todayMinutes = <KLine>[];
    for (var i = 0; i < 50; i++) {
      todayMinutes.add(_createKLine(
        DateTime(todayDate.year, todayDate.month, todayDate.day, 9, 30 + i),
        10.0 + i * 0.001,
      ));
    }
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: todayMinutes,
      dataType: KLineDataType.oneMinute,
    );

    final result = await repository.findMissingMinuteDates(
      stockCode: '000001',
      dateRange: DateRange(todayDate, todayDate),
    );

    // Today should not be in missing or incomplete (it's inProgress)
    expect(result.missingDates, isNot(contains(todayDate)));
    expect(result.incompleteDates, isNot(contains(todayDate)));
    // And not in complete either
    expect(result.completeDates, isNot(contains(todayDate)));
  });
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/repository/data_freshness_test.dart`
Expected: FAIL - findMissingMinuteDates not implemented

**Step 3: Write minimal implementation**

Add to `lib/data/repository/market_data_repository.dart`:

```dart
import '../models/day_data_status.dart';
import '../storage/date_check_storage.dart';

// Add field in class:
final DateCheckStorage _dateCheckStorage;

// Update constructor:
MarketDataRepository({
  KLineMetadataManager? metadataManager,
  TdxClient? tdxClient,
  DateCheckStorage? dateCheckStorage,
})  : _metadataManager = metadataManager ?? KLineMetadataManager(),
      _tdxClient = tdxClient ?? TdxClient(),
      _dateCheckStorage = dateCheckStorage ?? DateCheckStorage() {
  _statusController.add(const DataReady(0));
}

// Add constant:
static const int _minCompleteBars = 220;

// Add implementation:
@override
Future<MissingDatesResult> findMissingMinuteDates({
  required String stockCode,
  required DateRange dateRange,
}) async {
  // 1. Get trading dates from daily K-line data
  final tradingDates = await getTradingDates(dateRange);

  if (tradingDates.isEmpty) {
    return const MissingDatesResult(
      missingDates: [],
      incompleteDates: [],
      completeDates: [],
    );
  }

  // 2. Query cached status
  final checkedStatus = await _dateCheckStorage.getCheckedStatus(
    stockCode: stockCode,
    dataType: KLineDataType.oneMinute,
    dates: tradingDates,
  );

  // 3. Categorize dates
  final missingDates = <DateTime>[];
  final incompleteDates = <DateTime>[];
  final completeDates = <DateTime>[];
  final toCheckDates = <DateTime>[];

  for (final date in tradingDates) {
    final status = checkedStatus[date];

    if (status == null) {
      toCheckDates.add(date);
    } else if (status == DayDataStatus.complete) {
      completeDates.add(date);
    } else {
      // incomplete or missing - re-check
      toCheckDates.add(date);
    }
  }

  // 4. Check uncached dates
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);

  for (final date in toCheckDates) {
    final barCount = await _metadataManager.countBarsForDate(
      stockCode: stockCode,
      dataType: KLineDataType.oneMinute,
      date: date,
    );

    final dateOnly = DateTime(date.year, date.month, date.day);
    final isToday = dateOnly == todayDate;

    DayDataStatus status;
    if (barCount == 0) {
      status = DayDataStatus.missing;
      missingDates.add(dateOnly);
    } else if (barCount >= _minCompleteBars) {
      status = DayDataStatus.complete;
      completeDates.add(dateOnly);
    } else if (isToday) {
      status = DayDataStatus.inProgress;
      // Don't add to any list, don't cache
    } else {
      status = DayDataStatus.incomplete;
      incompleteDates.add(dateOnly);
    }

    // 5. Save to cache (skip inProgress)
    if (status != DayDataStatus.inProgress) {
      await _dateCheckStorage.saveCheckStatus(
        stockCode: stockCode,
        dataType: KLineDataType.oneMinute,
        date: dateOnly,
        status: status,
        barCount: barCount,
      );
    }
  }

  return MissingDatesResult(
    missingDates: missingDates,
    incompleteDates: incompleteDates,
    completeDates: completeDates,
  );
}

@override
Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
  required List<String> stockCodes,
  required DateRange dateRange,
  ProgressCallback? onProgress,
}) async {
  final result = <String, MissingDatesResult>{};
  var completed = 0;

  for (final stockCode in stockCodes) {
    result[stockCode] = await findMissingMinuteDates(
      stockCode: stockCode,
      dateRange: dateRange,
    );
    completed++;
    onProgress?.call(completed, stockCodes.length);
  }

  return result;
}

@override
Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
  return await _metadataManager.getTradingDates(dateRange);
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/data_freshness_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/data_freshness_test.dart
git commit -m "$(cat <<'EOF'
feat: implement findMissingMinuteDates with caching

Implements precise minute data detection:
- Gets trading days from daily K-line data
- Checks cached status, skips complete dates
- Counts bars for unchecked dates
- Caches results (except inProgress for today)
- Threshold: 220 bars = complete

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update checkFreshness to use cache

**Files:**
- Modify: `lib/data/repository/market_data_repository.dart`
- Modify: `test/data/repository/data_freshness_test.dart`

**Step 1: Write the failing test**

Update tests in `test/data/repository/data_freshness_test.dart`:

```dart
group('checkFreshness with cache', () {
  test('returns Stale when cache has pending dates', () async {
    final jan15 = DateTime(2026, 1, 15);

    // Manually save incomplete status to cache
    final dateCheckStorage = DateCheckStorage(database: database);
    await dateCheckStorage.saveCheckStatus(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: jan15,
      status: DayDataStatus.incomplete,
      barCount: 100,
    );

    final freshness = await repository.checkFreshness(
      stockCodes: ['000001'],
      dataType: KLineDataType.oneMinute,
    );

    expect(freshness['000001'], isA<Stale>());
  });

  test('returns Fresh when all cached dates are complete', () async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayDate = DateTime(yesterday.year, yesterday.month, yesterday.day);

    // Save complete status
    final dateCheckStorage = DateCheckStorage(database: database);
    await dateCheckStorage.saveCheckStatus(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: yesterdayDate,
      status: DayDataStatus.complete,
      barCount: 240,
    );

    final freshness = await repository.checkFreshness(
      stockCodes: ['000001'],
      dataType: KLineDataType.oneMinute,
    );

    expect(freshness['000001'], isA<Fresh>());
  });

  test('returns Missing when no cached data', () async {
    final freshness = await repository.checkFreshness(
      stockCodes: ['999999'],
      dataType: KLineDataType.oneMinute,
    );

    expect(freshness['999999'], isA<Missing>());
  });

  test('excludes today from pending check', () async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Save incomplete status for today only
    final dateCheckStorage = DateCheckStorage(database: database);
    await dateCheckStorage.saveCheckStatus(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: todayDate,
      status: DayDataStatus.incomplete,
      barCount: 50,
    );

    // Also save a complete date for yesterday so it's not Missing
    final yesterday = todayDate.subtract(const Duration(days: 1));
    await dateCheckStorage.saveCheckStatus(
      stockCode: '000001',
      dataType: KLineDataType.oneMinute,
      date: yesterday,
      status: DayDataStatus.complete,
      barCount: 240,
    );

    final freshness = await repository.checkFreshness(
      stockCodes: ['000001'],
      dataType: KLineDataType.oneMinute,
    );

    // Should be Fresh because today's incomplete is ignored
    expect(freshness['000001'], isA<Fresh>());
  });
});
```

**Step 2: Run test to verify current behavior**

Run: `flutter test test/data/repository/data_freshness_test.dart`
Expected: Some tests may fail with old logic

**Step 3: Write implementation**

Replace `checkFreshness` in `lib/data/repository/market_data_repository.dart`:

```dart
@override
Future<Map<String, DataFreshness>> checkFreshness({
  required List<String> stockCodes,
  required KLineDataType dataType,
}) async {
  final result = <String, DataFreshness>{};

  for (final stockCode in stockCodes) {
    // 1. Check for pending dates (excluding today)
    final pendingDates = await _dateCheckStorage.getPendingDates(
      stockCode: stockCode,
      dataType: dataType,
      excludeToday: true,
    );

    if (pendingDates.isNotEmpty) {
      // Has incomplete historical dates -> Stale
      result[stockCode] = Stale(
        missingRange: DateRange(
          pendingDates.first,
          pendingDates.last,
        ),
      );
      continue;
    }

    // 2. Check latest checked date
    final latestCheckedDate = await _dateCheckStorage.getLatestCheckedDate(
      stockCode: stockCode,
      dataType: dataType,
    );

    if (latestCheckedDate == null) {
      // Never checked -> Missing
      result[stockCode] = const Missing();
      continue;
    }

    // 3. Check if there might be new unchecked dates
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceLastCheck = today.difference(latestCheckedDate).inDays;

    if (daysSinceLastCheck > 1) {
      // Might have new trading days not yet checked -> Stale
      result[stockCode] = Stale(
        missingRange: DateRange(
          latestCheckedDate.add(const Duration(days: 1)),
          now,
        ),
      );
    } else {
      // Data is complete -> Fresh
      result[stockCode] = const Fresh();
    }
  }

  return result;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/repository/data_freshness_test.dart`
Expected: All tests pass

**Step 5: Commit**

```bash
git add lib/data/repository/market_data_repository.dart test/data/repository/data_freshness_test.dart
git commit -m "$(cat <<'EOF'
feat: update checkFreshness to use detection cache

checkFreshness now reads from date_check_status cache:
- Returns Stale if any historical pending dates exist
- Returns Missing if never checked
- Returns Fresh if all recent dates are complete
- Excludes today from pending check (inProgress is ok)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Run full test suite and fix any issues

**Step 1: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 2: Fix any failing tests**

If any tests fail, analyze and fix them.

**Step 3: Commit fixes if needed**

```bash
git add -A
git commit -m "$(cat <<'EOF'
fix: resolve test failures from freshness detection changes

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Update existing freshness tests

**Files:**
- Modify: `test/data/repository/data_freshness_test.dart`

**Step 1: Update BUG tests to reflect fixed behavior**

Update the "BUG:" tests to expect correct behavior now:

```dart
group('历史数据缺失检测 - 修复后的行为', () {
  test('中间日期缺失时，findMissingMinuteDates 能正确检测', () async {
    // Setup: jan15 and jan25 have data, jan16-24 missing
    final jan15 = DateTime(2026, 1, 15);
    final jan20 = DateTime(2026, 1, 20);
    final jan25 = DateTime(2026, 1, 25);

    // Define trading days via daily data
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [
        _createKLine(jan15, 10.0),
        _createKLine(jan20, 10.5),
        _createKLine(jan25, 11.0),
      ],
      dataType: KLineDataType.daily,
    );

    // Only jan15 has complete minute data
    final jan15Minutes = <KLine>[];
    for (var i = 0; i < 230; i++) {
      jan15Minutes.add(_createKLine(
        DateTime(2026, 1, 15, 9, 30).add(Duration(minutes: i)),
        10.0,
      ));
    }
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: jan15Minutes,
      dataType: KLineDataType.oneMinute,
    );

    final result = await repository.findMissingMinuteDates(
      stockCode: '000001',
      dateRange: DateRange(jan15, jan25),
    );

    expect(result.completeDates, contains(jan15));
    expect(result.missingDates, containsAll([jan20, jan25]));
    expect(result.isComplete, isFalse);
  });

  test('某天数据不完整时，能正确标记为 incomplete', () async {
    final jan15 = DateTime(2026, 1, 15);

    // Define trading day
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [_createKLine(jan15, 10.0)],
      dataType: KLineDataType.daily,
    );

    // Only 100 bars (incomplete)
    final incompleteMinutes = <KLine>[];
    for (var i = 0; i < 100; i++) {
      incompleteMinutes.add(_createKLine(
        DateTime(2026, 1, 15, 9, 30 + i),
        10.0,
      ));
    }
    await manager.saveKlineData(
      stockCode: '000001',
      newBars: incompleteMinutes,
      dataType: KLineDataType.oneMinute,
    );

    final result = await repository.findMissingMinuteDates(
      stockCode: '000001',
      dateRange: DateRange(jan15, jan15),
    );

    expect(result.incompleteDates, contains(jan15));
    expect(result.completeDates, isEmpty);
  });
});
```

**Step 2: Run updated tests**

Run: `flutter test test/data/repository/data_freshness_test.dart`
Expected: All tests pass

**Step 3: Commit**

```bash
git add test/data/repository/data_freshness_test.dart
git commit -m "$(cat <<'EOF'
test: update freshness tests to verify fixed behavior

Updates BUG tests to verify the new detection logic correctly:
- Detects gaps in historical data
- Marks incomplete data (< 220 bars) correctly
- Uses findMissingMinuteDates for precise detection

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add DayDataStatus + MissingDatesResult | model + test |
| 2 | Database schema v2 with date_check_status | schema + migration |
| 3 | DateCheckStorage CRUD | storage + test |
| 4 | getTradingDates | metadata manager |
| 5 | countBarsForDate | metadata manager |
| 6 | DataRepository interface | interface |
| 7 | findMissingMinuteDates implementation | repository |
| 8 | checkFreshness cache integration | repository |
| 9 | Full test suite | all |
| 10 | Update existing tests | tests |

**Key Parameters:**
- Complete threshold: 220 bars
- Trading days: from daily K-line data
- Cache: complete dates cached permanently, incomplete/missing re-checked
