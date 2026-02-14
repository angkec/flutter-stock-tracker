// test/data/storage/kline_metadata_manager_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';

void main() {
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

  setUp(() async {
    // Create temporary test directory
    testDir = await Directory.systemTemp.createTemp('kline_metadata_test_');

    // Initialize file storage with test directory
    fileStorage = KLineFileStorage();
    fileStorage.setBaseDirPathForTesting(testDir.path);
    await fileStorage.initialize();

    // Initialize database
    database = MarketDatabase();
    await database.database;

    // Create manager
    manager = KLineMetadataManager(
      database: database,
      fileStorage: fileStorage,
    );
  });

  tearDown(() async {
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

  group('KLineFileMetadata', () {
    test('should create metadata from map', () {
      final map = {
        'stock_code': 'SH600000',
        'data_type': 'daily',
        'year_month': '202501',
        'file_path': '/path/to/file.bin.gz',
        'start_date': 1704067200000,
        'end_date': 1704153600000,
        'record_count': 10,
        'checksum': 'abc123',
        'file_size': 1024,
      };

      final metadata = KLineFileMetadata.fromMap(map);

      expect(metadata.stockCode, equals('SH600000'));
      expect(metadata.dataType, equals(KLineDataType.daily));
      expect(metadata.yearMonth, equals('202501'));
      expect(metadata.recordCount, equals(10));
    });

    test('should convert metadata to map', () {
      final metadata = KLineFileMetadata(
        stockCode: 'SH600000',
        dataType: KLineDataType.daily,
        yearMonth: '202501',
        filePath: '/path/to/file.bin.gz',
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 31),
        recordCount: 10,
        checksum: 'abc123',
        fileSize: 1024,
      );

      final map = metadata.toMap();

      expect(map['stock_code'], equals('SH600000'));
      expect(map['data_type'], equals('daily'));
      expect(map['year_month'], equals('202501'));
      expect(map['record_count'], equals(10));
    });
  });

  group('KLineMetadataManager', () {
    test('should save kline data with metadata update', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      final klines = [
        KLine(
          datetime: DateTime(2025, 1, 1, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 2, 10, 0),
          open: 101.0,
          close: 103.0,
          high: 104.0,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
      ];

      // Save data
      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: klines,
        dataType: dataType,
      );

      // Verify metadata was saved
      final metadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: dataType,
      );

      expect(metadata, isNotEmpty);
      expect(metadata.first.stockCode, equals(stockCode));
      expect(metadata.first.recordCount, equals(2));
    });

    test('should handle empty save gracefully', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      // Should not throw
      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: [],
        dataType: dataType,
      );

      // Verify no metadata was created
      final metadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: dataType,
      );

      expect(metadata, isEmpty);
    });

    test('should get latest data date', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      final klines = [
        KLine(
          datetime: DateTime(2025, 1, 1, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 10, 10, 0),
          open: 101.0,
          close: 103.0,
          high: 104.0,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
      ];

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: klines,
        dataType: dataType,
      );

      final latestDate = await manager.getLatestDataDate(
        stockCode: stockCode,
        dataType: dataType,
      );

      expect(latestDate, isNotNull);
      expect(latestDate!.year, equals(2025));
      expect(latestDate.month, equals(1));
      expect(latestDate.day, equals(10));
    });

    test('should return null when no data exists', () async {
      const stockCode = 'SH999999';
      const dataType = KLineDataType.daily;

      final latestDate = await manager.getLatestDataDate(
        stockCode: stockCode,
        dataType: dataType,
      );

      expect(latestDate, isNull);
    });

    test('should load kline data by date range (single month)', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      final klines = [
        KLine(
          datetime: DateTime(2025, 1, 1, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 5, 10, 0),
          open: 101.0,
          close: 103.0,
          high: 104.0,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 10, 10, 0),
          open: 103.0,
          close: 105.0,
          high: 106.0,
          low: 102.0,
          volume: 2000.0,
          amount: 200000.0,
        ),
      ];

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: klines,
        dataType: dataType,
      );

      // Load data for first week of January
      final dateRange = DateRange(DateTime(2025, 1, 1), DateTime(2025, 1, 7));

      final loaded = await manager.loadKlineData(
        stockCode: stockCode,
        dataType: dataType,
        dateRange: dateRange,
      );

      expect(loaded.length, equals(2));
      expect(loaded[0].datetime.day, equals(1));
      expect(loaded[1].datetime.day, equals(5));
    });

    test('should load kline data across multiple months', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      // January data
      final janKlines = [
        KLine(
          datetime: DateTime(2025, 1, 30, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 31, 10, 0),
          open: 101.0,
          close: 103.0,
          high: 104.0,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
      ];

      // February data
      final febKlines = [
        KLine(
          datetime: DateTime(2025, 2, 1, 10, 0),
          open: 103.0,
          close: 104.0,
          high: 105.0,
          low: 102.0,
          volume: 1800.0,
          amount: 180000.0,
        ),
        KLine(
          datetime: DateTime(2025, 2, 5, 10, 0),
          open: 104.0,
          close: 105.0,
          high: 106.0,
          low: 103.0,
          volume: 2000.0,
          amount: 200000.0,
        ),
      ];

      // Save both months
      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: janKlines,
        dataType: dataType,
      );

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: febKlines,
        dataType: dataType,
      );

      // Load across both months
      final dateRange = DateRange(DateTime(2025, 1, 25), DateTime(2025, 2, 10));

      final loaded = await manager.loadKlineData(
        stockCode: stockCode,
        dataType: dataType,
        dateRange: dateRange,
      );

      expect(loaded.length, equals(4));
      expect(loaded[0].datetime.month, equals(1));
      expect(loaded[1].datetime.month, equals(1));
      expect(loaded[2].datetime.month, equals(2));
      expect(loaded[3].datetime.month, equals(2));
    });

    test('should handle incremental updates correctly', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      // Initial save
      final initialKlines = [
        KLine(
          datetime: DateTime(2025, 1, 1, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 2, 10, 0),
          open: 101.0,
          close: 103.0,
          high: 104.0,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
      ];

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: initialKlines,
        dataType: dataType,
      );

      // Verify initial state
      var metadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: dataType,
      );
      expect(metadata.first.recordCount, equals(2));

      // Incremental update with some overlapping data
      final newKlines = [
        KLine(
          datetime: DateTime(2025, 1, 2, 10, 0),
          open: 101.5,
          close: 103.5,
          high: 104.5,
          low: 100.5,
          volume: 1600.0,
          amount: 160000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 3, 10, 0),
          open: 103.5,
          close: 105.0,
          high: 106.0,
          low: 102.0,
          volume: 2000.0,
          amount: 200000.0,
        ),
      ];

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: newKlines,
        dataType: dataType,
      );

      // Verify updated state
      metadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: dataType,
      );
      expect(metadata.first.recordCount, equals(3));

      // Load and verify deduplicated data
      final loaded = await manager.loadKlineData(
        stockCode: stockCode,
        dataType: dataType,
        dateRange: DateRange(DateTime(2025, 1, 1), DateTime(2025, 1, 31)),
      );

      expect(loaded.length, equals(3));
      expect(loaded[1].datetime.day, equals(2));
      expect(loaded[1].close, equals(103.5)); // Updated value
    });

    test('should skip version bump when incoming bars are unchanged', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      final klines = [
        KLine(
          datetime: DateTime(2025, 1, 1, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 2, 10, 0),
          open: 101.0,
          close: 103.0,
          high: 104.0,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
      ];

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: klines,
        dataType: dataType,
      );
      final versionAfterFirst = await manager.getCurrentVersion();

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: klines,
        dataType: dataType,
      );
      final versionAfterSecond = await manager.getCurrentVersion();

      expect(versionAfterSecond, equals(versionAfterFirst));

      final metadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: dataType,
      );
      expect(metadata.length, equals(1));
      expect(metadata.first.recordCount, equals(2));
    });

    test('should delete old data correctly', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;

      // Create data for Jan, Feb, and Mar
      final janKlines = [
        KLine(
          datetime: DateTime(2025, 1, 15, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
      ];

      final febKlines = [
        KLine(
          datetime: DateTime(2025, 2, 15, 10, 0),
          open: 101.0,
          close: 102.0,
          high: 103.0,
          low: 100.0,
          volume: 1100.0,
          amount: 110000.0,
        ),
      ];

      final marKlines = [
        KLine(
          datetime: DateTime(2025, 3, 15, 10, 0),
          open: 102.0,
          close: 103.0,
          high: 104.0,
          low: 101.0,
          volume: 1200.0,
          amount: 120000.0,
        ),
      ];

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: janKlines,
        dataType: dataType,
      );
      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: febKlines,
        dataType: dataType,
      );
      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: marKlines,
        dataType: dataType,
      );

      // Verify all data exists
      var metadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: dataType,
      );
      expect(metadata.length, equals(3));

      // Delete old data before March
      await manager.deleteOldData(
        stockCode: stockCode,
        dataType: dataType,
        beforeDate: DateTime(2025, 3, 1),
      );

      // Verify only March remains
      metadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: dataType,
      );
      expect(metadata.length, equals(1));
      expect(metadata.first.yearMonth, equals('202503'));
    });

    test('should get metadata for multiple data types', () async {
      const stockCode = 'SH600000';

      final klines = [
        KLine(
          datetime: DateTime(2025, 1, 1, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
      ];

      // Save both daily and 1-minute data
      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: klines,
        dataType: KLineDataType.daily,
      );

      await manager.saveKlineData(
        stockCode: stockCode,
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      // Get metadata for each type
      final dailyMetadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: KLineDataType.daily,
      );
      final oneMinMetadata = await manager.getMetadata(
        stockCode: stockCode,
        dataType: KLineDataType.oneMinute,
      );

      expect(dailyMetadata.length, equals(1));
      expect(oneMinMetadata.length, equals(1));
      expect(dailyMetadata.first.dataType, equals(KLineDataType.daily));
      expect(oneMinMetadata.first.dataType, equals(KLineDataType.oneMinute));
    });

    test('should get all stock codes for a data type', () async {
      // Save data for multiple stocks
      final klines = [
        KLine(
          datetime: DateTime(2025, 1, 15, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.daily,
      );
      await manager.saveKlineData(
        stockCode: '000002',
        newBars: klines,
        dataType: KLineDataType.daily,
      );
      await manager.saveKlineData(
        stockCode: '600000',
        newBars: klines,
        dataType: KLineDataType.daily,
      );
      // Save oneMinute data for 000001 - should not appear in daily query
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      // Get all stock codes for daily data type
      final stockCodes = await manager.getAllStockCodes(
        dataType: KLineDataType.daily,
      );

      expect(stockCodes.length, equals(3));
      expect(stockCodes, containsAll(['000001', '000002', '600000']));
    });

    test('should return empty list when no data exists', () async {
      final stockCodes = await manager.getAllStockCodes(
        dataType: KLineDataType.daily,
      );

      expect(stockCodes, isEmpty);
    });
  });

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

    test('returns only actual trading dates, not calendar dates', () async {
      // Save daily data with gaps (jan15, jan17 - skip jan16)
      final jan15 = DateTime(2026, 1, 15);
      final jan17 = DateTime(2026, 1, 17);

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(jan15, 10.0), _createKLine(jan17, 11.0)],
        dataType: KLineDataType.daily,
      );

      final tradingDates = await manager.getTradingDates(
        DateRange(jan15, jan17),
      );

      // Should only return jan15 and jan17, NOT jan16
      expect(tradingDates.length, equals(2));
      expect(tradingDates, contains(jan15));
      expect(tradingDates, contains(jan17));
      expect(tradingDates, isNot(contains(DateTime(2026, 1, 16))));
    });
  });

  group('countBarsForDate', () {
    test('returns correct count for a date with data', () async {
      final date = DateTime(2026, 1, 15);

      // Create 50 minute bars for the day
      final klines = <KLine>[];
      for (var i = 0; i < 50; i++) {
        klines.add(
          _createKLine(
            DateTime(date.year, date.month, date.day, 9, 30 + i),
            10.0 + i * 0.01,
          ),
        );
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
}

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
