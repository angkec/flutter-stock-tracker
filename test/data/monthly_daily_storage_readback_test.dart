import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  late Directory tempDir;
  late MarketDatabase database;
  late KLineFileStorage storage;
  late KLineMetadataManager manager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> deleteTestDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/market_data.db';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  setUp(() async {
    MarketDatabase.resetInstance();
    await deleteTestDatabase();

    tempDir = await Directory.systemTemp.createTemp(
      'monthly-daily-storage-readback-',
    );

    storage = KLineFileStorage()..setBaseDirPathForTesting(tempDir.path);
    await storage.initialize();

    database = MarketDatabase();
    await database.database;

    manager = KLineMetadataManager(
      database: database,
      fileStorage: storage,
    );
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {}
    MarketDatabase.resetInstance();

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }

    await deleteTestDatabase();
  });

  test('reads back daily bars from monthly storage on disk', () async {
    const stockCode = 'SH600000';

    final bars = [
      KLine(
        datetime: DateTime(2026, 1, 5, 10, 0),
        open: 10.0,
        close: 10.4,
        high: 10.6,
        low: 9.8,
        volume: 1200.0,
        amount: 12000.0,
      ),
      KLine(
        datetime: DateTime(2026, 1, 2, 10, 0),
        open: 10.1,
        close: 10.2,
        high: 10.5,
        low: 9.9,
        volume: 1100.0,
        amount: 11000.0,
      ),
      KLine(
        datetime: DateTime(2026, 1, 3, 10, 0),
        open: 10.2,
        close: 10.1,
        high: 10.4,
        low: 9.7,
        volume: 1150.0,
        amount: 11500.0,
      ),
    ];

    await manager.saveKlineData(
      stockCode: stockCode,
      newBars: bars,
      dataType: KLineDataType.daily,
    );

    try {
      await database.close();
    } catch (_) {}
    MarketDatabase.resetInstance();

    storage = KLineFileStorage()..setBaseDirPathForTesting(tempDir.path);
    await storage.initialize();
    database = MarketDatabase();
    await database.database;
    manager = KLineMetadataManager(
      database: database,
      fileStorage: storage,
    );

    final loaded = await manager.loadKlineData(
      stockCode: stockCode,
      dataType: KLineDataType.daily,
      dateRange: DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31)),
    );

    expect(loaded, isNotEmpty);

    final loadedDates = loaded.map((kline) => kline.datetime).toList();
    final sortedDates = [...loadedDates]
      ..sort((a, b) => a.compareTo(b));

    expect(loadedDates, orderedEquals(sortedDates));
  });
}
