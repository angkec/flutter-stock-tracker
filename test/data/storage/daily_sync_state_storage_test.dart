import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/daily_sync_state.dart';
import 'package:stock_rtwatcher/data/storage/database_schema.dart';
import 'package:stock_rtwatcher/data/storage/daily_sync_state_storage.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';

void main() {
  late DailySyncStateStorage storage;
  late MarketDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    database = MarketDatabase();
    storage = DailySyncStateStorage(database: database);
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {}

    MarketDatabase.resetInstance();

    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/${DatabaseSchema.databaseName}';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  group('DailySyncStateStorage', () {
    test('upsert + getByStockCode roundtrip keeps finalized date', () async {
      final state = DailySyncState(
        stockCode: '600000',
        lastIntradayDate: DateTime(2026, 2, 16),
        lastFinalizedDate: DateTime(2026, 2, 16),
        lastFingerprint: 'fp_v1',
        updatedAt: DateTime(2026, 2, 16, 15, 10),
      );

      await storage.upsert(state);
      final loaded = await storage.getByStockCode('600000');

      expect(loaded, isNotNull);
      expect(loaded!.lastFinalizedDate, DateTime(2026, 2, 16));
      expect(loaded.lastIntradayDate, DateTime(2026, 2, 16));
      expect(loaded.lastFingerprint, 'fp_v1');
    });

    test('markFinalizedSnapshot should not regress to older trade date', () async {
      await storage.markFinalizedSnapshot(
        stockCode: '600000',
        tradeDate: DateTime(2026, 2, 16),
        fingerprint: 'fp_new',
      );

      await storage.markFinalizedSnapshot(
        stockCode: '600000',
        tradeDate: DateTime(2026, 2, 15),
        fingerprint: 'fp_old',
      );

      final loaded = await storage.getByStockCode('600000');
      expect(loaded, isNotNull);
      expect(loaded!.lastFinalizedDate, DateTime(2026, 2, 16));
      expect(loaded.lastFingerprint, 'fp_new');
    });
  });
}
