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
