// test/data/storage/kline_file_storage_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

void main() {
  late KLineFileStorage storage;
  late Directory testDir;

  setUpAll(() async {
    // Initialize Flutter bindings for tests
    TestWidgetsFlutterBinding.ensureInitialized();
    // Create a temporary test directory
    testDir = await Directory.systemTemp.createTemp('kline_test_');
  });

  setUp(() async {
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(testDir.path);
    await storage.initialize();
  });

  tearDown(() async {
    // Clean up test files
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('KLineFileStorage', () {
    test('should initialize and create base directory', () async {
      final baseDir = Directory(testDir.path);
      expect(await baseDir.exists(), isTrue);
    });

    test('should save and load monthly kline file', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;
      const year = 2025;
      const month = 1;

      // Create test data
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

      // Save
      await storage.saveMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
        klines,
      );

      // Load
      final loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );

      // Verify
      expect(loaded.length, equals(2));
      expect(loaded[0].datetime, equals(klines[0].datetime));
      expect(loaded[0].close, equals(101.0));
      expect(loaded[1].datetime, equals(klines[1].datetime));
      expect(loaded[1].close, equals(103.0));
    });

    test('should return empty list for non-existent file', () async {
      const stockCode = 'SH999999';
      const dataType = KLineDataType.daily;
      const year = 2025;
      const month = 1;

      final loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );

      expect(loaded, isEmpty);
    });

    test('should handle empty save (no-op)', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;
      const year = 2025;
      const month = 1;

      // Save empty list should not create file
      await storage.saveMonthlyKlineFile(stockCode, dataType, year, month, []);

      // Try to load
      final loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );
      expect(loaded, isEmpty);
    });

    test('should append and deduplicate kline data', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;
      const year = 2025;
      const month = 1;

      // Initial data
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

      await storage.saveMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
        initialKlines,
      );

      // New data with overlap
      final newKlines = [
        KLine(
          datetime: DateTime(
            2025,
            1,
            2,
            10,
            0,
          ), // Duplicate, should be replaced
          open: 101.0,
          close: 103.5, // Different close
          high: 104.5,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
        KLine(
          datetime: DateTime(2025, 1, 3, 10, 0), // New
          open: 103.5,
          close: 105.0,
          high: 106.0,
          low: 102.0,
          volume: 2000.0,
          amount: 200000.0,
        ),
      ];

      await storage.appendKlineData(
        stockCode,
        dataType,
        year,
        month,
        newKlines,
      );

      // Load and verify
      final loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );

      expect(loaded.length, equals(3));
      expect(loaded[0].datetime, equals(DateTime(2025, 1, 1, 10, 0)));
      expect(loaded[1].datetime, equals(DateTime(2025, 1, 2, 10, 0)));
      expect(loaded[1].close, equals(103.5)); // Updated value
      expect(loaded[2].datetime, equals(DateTime(2025, 1, 3, 10, 0)));
    });

    test('should skip rewrite when append data is identical', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;
      const year = 2025;
      const month = 1;

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

      await storage.saveMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
        initialKlines,
      );

      final filePath = storage.getFilePath(stockCode, dataType, year, month);
      final file = File(filePath);
      final bytesBefore = await file.readAsBytes();

      final appendResult = await storage
          .appendKlineData(stockCode, dataType, year, month, [
            KLine(
              datetime: DateTime(2025, 1, 2, 10, 0),
              open: 101.0,
              close: 103.0,
              high: 104.0,
              low: 100.0,
              volume: 1500.0,
              amount: 150000.0,
            ),
          ]);

      expect(appendResult, isNotNull);
      expect(appendResult!.changed, isFalse);
      expect(appendResult.recordCount, equals(2));

      final bytesAfter = await file.readAsBytes();
      expect(bytesAfter, orderedEquals(bytesBefore));
    });

    test(
      'should merge unsorted incoming bars and keep latest duplicate value',
      () async {
        const stockCode = 'SH600000';
        const dataType = KLineDataType.daily;
        const year = 2025;
        const month = 1;

        await storage.saveMonthlyKlineFile(stockCode, dataType, year, month, [
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
            close: 102.0,
            high: 103.0,
            low: 100.0,
            volume: 1200.0,
            amount: 120000.0,
          ),
        ]);

        await storage.appendKlineData(stockCode, dataType, year, month, [
          KLine(
            datetime: DateTime(2025, 1, 3, 10, 0),
            open: 103.0,
            close: 104.0,
            high: 105.0,
            low: 102.0,
            volume: 1300.0,
            amount: 130000.0,
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
          KLine(
            datetime: DateTime(2025, 1, 2, 10, 0),
            open: 101.0,
            close: 103.5,
            high: 104.5,
            low: 100.0,
            volume: 1600.0,
            amount: 160000.0,
          ),
        ]);

        final loaded = await storage.loadMonthlyKlineFile(
          stockCode,
          dataType,
          year,
          month,
        );

        expect(loaded.length, 3);
        expect(loaded[0].datetime, DateTime(2025, 1, 1, 10, 0));
        expect(loaded[1].datetime, DateTime(2025, 1, 2, 10, 0));
        expect(loaded[2].datetime, DateTime(2025, 1, 3, 10, 0));
        expect(loaded[1].close, 103.5);
        expect(loaded[1].amount, 160000.0);
      },
    );

    test('should handle cross-month data correctly', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;
      const year = 2025;

      // Data spanning across months
      final klines = [
        KLine(
          datetime: DateTime(2025, 1, 31, 10, 0),
          open: 100.0,
          close: 101.0,
          high: 102.0,
          low: 99.0,
          volume: 1000.0,
          amount: 100000.0,
        ),
        KLine(
          datetime: DateTime(2025, 2, 1, 10, 0),
          open: 101.0,
          close: 103.0,
          high: 104.0,
          low: 100.0,
          volume: 1500.0,
          amount: 150000.0,
        ),
      ];

      // Save to January
      await storage.saveMonthlyKlineFile(stockCode, dataType, year, 1, [
        klines[0],
      ]);

      // Save to February
      await storage.saveMonthlyKlineFile(stockCode, dataType, year, 2, [
        klines[1],
      ]);

      // Load and verify each month
      final janKlines = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        1,
      );
      final febKlines = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        2,
      );

      expect(janKlines.length, equals(1));
      expect(janKlines[0].datetime.month, equals(1));
      expect(febKlines.length, equals(1));
      expect(febKlines[0].datetime.month, equals(2));
    });

    test('should delete monthly file', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;
      const year = 2025;
      const month = 1;

      // Create test data
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

      // Save
      await storage.saveMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
        klines,
      );

      // Verify file exists
      var loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );
      expect(loaded.isNotEmpty, isTrue);

      // Delete
      await storage.deleteMonthlyFile(stockCode, dataType, year, month);

      // Verify file is gone
      loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );
      expect(loaded.isEmpty, isTrue);
    });

    test('should handle multiple data types correctly', () async {
      const stockCode = 'SH600000';
      const year = 2025;
      const month = 1;

      // Create test data
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

      // Save both 1-minute and daily data
      await storage.saveMonthlyKlineFile(
        stockCode,
        KLineDataType.oneMinute,
        year,
        month,
        klines,
      );
      await storage.saveMonthlyKlineFile(
        stockCode,
        KLineDataType.daily,
        year,
        month,
        klines,
      );

      // Load and verify both exist
      final oneMinKlines = await storage.loadMonthlyKlineFile(
        stockCode,
        KLineDataType.oneMinute,
        year,
        month,
      );
      final dailyKlines = await storage.loadMonthlyKlineFile(
        stockCode,
        KLineDataType.daily,
        year,
        month,
      );

      expect(oneMinKlines.length, equals(1));
      expect(dailyKlines.length, equals(1));
    });

    test(
      'should preserve data precision through compress/decompress cycle',
      () async {
        const stockCode = 'SH600000';
        const dataType = KLineDataType.daily;
        const year = 2025;
        const month = 1;

        // Create data with precise values
        final klines = [
          KLine(
            datetime: DateTime(2025, 1, 1, 10, 30, 45),
            open: 100.123456,
            close: 101.654321,
            high: 102.987654,
            low: 99.123456,
            volume: 1000.5,
            amount: 100000.123456,
          ),
        ];

        // Save and load
        await storage.saveMonthlyKlineFile(
          stockCode,
          dataType,
          year,
          month,
          klines,
        );
        final loaded = await storage.loadMonthlyKlineFile(
          stockCode,
          dataType,
          year,
          month,
        );

        // Verify precision
        expect(loaded.length, equals(1));
        expect(loaded[0].datetime, equals(klines[0].datetime));
        expect(loaded[0].open, equals(100.123456));
        expect(loaded[0].close, equals(101.654321));
        expect(loaded[0].high, equals(102.987654));
        expect(loaded[0].low, equals(99.123456));
        expect(loaded[0].volume, equals(1000.5));
        expect(loaded[0].amount, equals(100000.123456));
      },
    );

    test('should handle large dataset efficiently', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.oneMinute;
      const year = 2025;
      const month = 1;

      // Create large dataset (1000 klines)
      final klines = List.generate(
        1000,
        (i) => KLine(
          datetime: DateTime(2025, 1, 1, 0, 0).add(Duration(minutes: i)),
          open: 100.0 + i * 0.01,
          close: 100.5 + i * 0.01,
          high: 101.0 + i * 0.01,
          low: 99.5 + i * 0.01,
          volume: 1000.0 + i,
          amount: 100000.0 + i * 100,
        ),
      );

      // Save
      final stopwatch = Stopwatch()..start();
      await storage.saveMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
        klines,
      );
      stopwatch.stop();

      // Load
      stopwatch.reset();
      stopwatch.start();
      final loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );
      stopwatch.stop();

      expect(loaded.length, equals(1000));
      expect(loaded[0].datetime, equals(klines[0].datetime));
      expect(loaded[999].datetime, equals(klines[999].datetime));
    });

    test('should maintain data integrity through append operations', () async {
      const stockCode = 'SH600000';
      const dataType = KLineDataType.daily;
      const year = 2025;
      const month = 1;

      // Create initial data
      final initialKlines = List.generate(
        10,
        (i) => KLine(
          datetime: DateTime(2025, 1, 1, 10, 0).add(Duration(days: i)),
          open: 100.0 + i,
          close: 101.0 + i,
          high: 102.0 + i,
          low: 99.0 + i,
          volume: 1000.0 + i * 100,
          amount: 100000.0 + i * 1000,
        ),
      );

      await storage.saveMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
        initialKlines,
      );

      // Append multiple times
      for (int batch = 0; batch < 5; batch++) {
        final newKlines = List.generate(
          5,
          (i) => KLine(
            datetime: DateTime(
              2025,
              1,
              11,
              10,
              0,
            ).add(Duration(days: batch * 5 + i)),
            open: 110.0 + batch * 5 + i,
            close: 111.0 + batch * 5 + i,
            high: 112.0 + batch * 5 + i,
            low: 109.0 + batch * 5 + i,
            volume: 2000.0 + (batch * 5 + i) * 100,
            amount: 200000.0 + (batch * 5 + i) * 1000,
          ),
        );

        await storage.appendKlineData(
          stockCode,
          dataType,
          year,
          month,
          newKlines,
        );
      }

      // Load and verify
      final loaded = await storage.loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );

      // Should have initial 10 + 5 batches of 5 = 35 total
      expect(loaded.length, equals(35));

      // Verify sorted by datetime
      for (int i = 0; i < loaded.length - 1; i++) {
        expect(
          loaded[i].datetime.isBefore(loaded[i + 1].datetime) ||
              loaded[i].datetime == loaded[i + 1].datetime,
          isTrue,
        );
      }
    });
  });
}
