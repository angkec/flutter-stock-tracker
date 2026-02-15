import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/minute_sync_state.dart';
import 'package:stock_rtwatcher/data/storage/database_schema.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/minute_sync_state_storage.dart';

void main() {
  late MinuteSyncStateStorage storage;
  late MarketDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    database = MarketDatabase();
    storage = MinuteSyncStateStorage(database: database);
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

  group('MinuteSyncStateStorage', () {
    test('upsert + read should persist minute sync state', () async {
      final state = MinuteSyncState(
        stockCode: '000001',
        lastCompleteTradingDay: DateTime(2026, 2, 13),
        lastSuccessFetchAt: DateTime(2026, 2, 14, 9, 31),
        lastAttemptAt: DateTime(2026, 2, 14, 9, 30),
        consecutiveFailures: 0,
        lastError: null,
        updatedAt: DateTime(2026, 2, 14, 9, 32),
      );

      await storage.upsert(state);
      final loaded = await storage.getByStockCode('000001');

      expect(loaded, isNotNull);
      expect(loaded!.stockCode, '000001');
      expect(loaded.lastCompleteTradingDay, DateTime(2026, 2, 13));
      expect(loaded.consecutiveFailures, 0);
    });

    test('getBatchByStockCodes should return existing states only', () async {
      await storage.upsert(
        MinuteSyncState(
          stockCode: '000001',
          lastCompleteTradingDay: DateTime(2026, 2, 13),
          updatedAt: DateTime(2026, 2, 14, 10, 0),
        ),
      );

      final batch = await storage.getBatchByStockCodes(['000001', '000002']);

      expect(batch.keys, contains('000001'));
      expect(batch.keys, isNot(contains('000002')));
    });

    test('markFetchFailure should increment failure count', () async {
      await storage.markFetchFailure('000001', 'timeout');
      await storage.markFetchFailure('000001', 'timeout-again');

      final loaded = await storage.getByStockCode('000001');
      expect(loaded, isNotNull);
      expect(loaded!.consecutiveFailures, 2);
      expect(loaded.lastError, 'timeout-again');
      expect(loaded.lastAttemptAt, isNotNull);
    });

    test(
      'markFetchSuccessBatch should clear failures and update timestamps',
      () async {
        await storage.markFetchFailure('000001', 'timeout');
        await storage.markFetchFailure('000002', 'timeout');

        final tradingDay = DateTime(2026, 2, 13);
        await storage.markFetchSuccessBatch([
          '000001',
          '000002',
        ], lastCompleteTradingDay: tradingDay);

        final batch = await storage.getBatchByStockCodes(['000001', '000002']);
        expect(batch.length, 2);

        for (final stockCode in ['000001', '000002']) {
          final state = batch[stockCode];
          expect(state, isNotNull);
          expect(state!.consecutiveFailures, 0);
          expect(state.lastError, isNull);
          expect(state.lastSuccessFetchAt, isNotNull);
          expect(state.lastAttemptAt, isNotNull);
          expect(state.lastCompleteTradingDay, DateTime(2026, 2, 13));
        }
      },
    );

    test(
      'getBatchByStockCodes should support large input via chunking',
      () async {
        final existingCodes = List.generate(
          1200,
          (index) => '6${index.toString().padLeft(5, '0')}',
        );
        for (final code in existingCodes) {
          await storage.upsert(
            MinuteSyncState(
              stockCode: code,
              updatedAt: DateTime(2026, 2, 14, 10, 0),
            ),
          );
        }

        final loaded = await storage.getBatchByStockCodes(existingCodes);
        expect(loaded.length, existingCodes.length);
        expect(loaded.keys.first, isNotEmpty);
      },
    );
  });
}
