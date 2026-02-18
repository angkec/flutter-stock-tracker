import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/minute_sync_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/minute_sync_state_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class FailingSaveMetadataManager extends KLineMetadataManager {
  final Set<String> failingStockCodes;

  FailingSaveMetadataManager({
    required super.database,
    required super.fileStorage,
    required this.failingStockCodes,
  });

  @override
  Future<void> saveKlineData({
    required String stockCode,
    required List<KLine> newBars,
    required KLineDataType dataType,
    bool bumpVersion = true,
  }) async {
    if (failingStockCodes.contains(stockCode)) {
      throw StateError('persist fail: $stockCode');
    }
    await super.saveKlineData(
      stockCode: stockCode,
      newBars: newBars,
      dataType: dataType,
      bumpVersion: bumpVersion,
    );
  }
}

void main() {
  late MarketDatabase database;
  late KLineFileStorage fileStorage;
  late KLineMetadataManager metadataManager;
  late MinuteSyncStateStorage syncStateStorage;
  late MinuteSyncWriter writer;
  late Directory testDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('minute_sync_writer_test_');

    fileStorage = KLineFileStorage();
    fileStorage.setBaseDirPathForTesting(testDir.path);
    await fileStorage.initialize();

    database = MarketDatabase();
    await database.database;

    metadataManager = KLineMetadataManager(
      database: database,
      fileStorage: fileStorage,
    );
    syncStateStorage = MinuteSyncStateStorage(database: database);
    writer = MinuteSyncWriter(
      metadataManager: metadataManager,
      syncStateStorage: syncStateStorage,
    );
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {}
    MarketDatabase.resetInstance();

    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }

    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/market_data.db';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  KLine buildBar(DateTime time) {
    return KLine(
      datetime: time,
      open: 10.0,
      close: 10.2,
      high: 10.3,
      low: 9.9,
      volume: 1000,
      amount: 10000,
    );
  }

  group('MinuteSyncWriter', () {
    test(
      'writeBatch bumps data version once for multiple updated stocks',
      () async {
        final initialVersion = await metadataManager.getCurrentVersion();

        final result = await writer.writeBatch(
          barsByStock: {
            '000001': [buildBar(DateTime(2026, 2, 13, 9, 30))],
            '000002': [buildBar(DateTime(2026, 2, 13, 9, 31))],
          },
          dataType: KLineDataType.oneMinute,
          fetchedTradingDay: DateTime(2026, 2, 13),
        );

        final versionAfterWrite = await metadataManager.getCurrentVersion();
        expect(versionAfterWrite, initialVersion + 1);
        expect(result.persistDurationMs, greaterThanOrEqualTo(0));
        expect(result.versionDurationMs, greaterThanOrEqualTo(0));
        expect(result.totalDurationMs, greaterThanOrEqualTo(0));
      },
    );

    test(
      'writeBatch reports zero version duration when no stock updated',
      () async {
        final result = await writer.writeBatch(
          barsByStock: {'000001': const [], '000002': const []},
          dataType: KLineDataType.oneMinute,
          fetchedTradingDay: DateTime(2026, 2, 13),
        );

        expect(result.updatedStocks, isEmpty);
        expect(result.totalRecords, 0);
        expect(result.versionDurationMs, 0);
        expect(result.totalDurationMs, greaterThanOrEqualTo(0));
      },
    );

    test('writeBatch supports configurable concurrent persistence', () async {
      final concurrentWriter = MinuteSyncWriter(
        metadataManager: metadataManager,
        syncStateStorage: syncStateStorage,
        maxConcurrentWrites: 2,
      );

      final result = await concurrentWriter.writeBatch(
        barsByStock: {
          '000001': [buildBar(DateTime(2026, 2, 13, 9, 30))],
          '000002': [buildBar(DateTime(2026, 2, 13, 9, 31))],
        },
        dataType: KLineDataType.oneMinute,
        fetchedTradingDay: DateTime(2026, 2, 13),
      );

      expect(result.updatedStocks, ['000001', '000002']);
      expect(result.totalRecords, 2);
      expect(result.persistDurationMs, greaterThanOrEqualTo(0));
    });

    test('setMaxConcurrentWrites clamps to at least one worker', () {
      writer.setMaxConcurrentWrites(0);
      expect(writer.maxConcurrentWrites, 1);

      writer.setMaxConcurrentWrites(5);
      expect(writer.maxConcurrentWrites, 5);
    });

    test('writeBatch skips empty bars and persists non-empty bars', () async {
      final fetchedDay = DateTime(2026, 2, 13);

      final result = await writer.writeBatch(
        barsByStock: {
          '000001': [
            buildBar(DateTime(2026, 2, 13, 9, 30)),
            buildBar(DateTime(2026, 2, 13, 9, 31)),
          ],
          '000002': const [],
        },
        dataType: KLineDataType.oneMinute,
        fetchedTradingDay: fetchedDay,
      );

      expect(result.updatedStocks, ['000001']);
      expect(result.totalRecords, 2);

      final loaded = await metadataManager.loadKlineData(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        dateRange: DateRange(
          DateTime(2026, 2, 13),
          DateTime(2026, 2, 13, 23, 59, 59),
        ),
      );
      expect(loaded.length, 2);

      final sync000001 = await syncStateStorage.getByStockCode('000001');
      final sync000002 = await syncStateStorage.getByStockCode('000002');

      expect(sync000001, isNotNull);
      expect(sync000001!.lastCompleteTradingDay, DateTime(2026, 2, 13));
      expect(sync000001.consecutiveFailures, 0);
      expect(sync000002, isNull);
    });

    test(
      'writeBatch reports per-stock outcomes for persist failures',
      () async {
        final failingManager = FailingSaveMetadataManager(
          database: database,
          fileStorage: fileStorage,
          failingStockCodes: {'000002'},
        );
        final failingWriter = MinuteSyncWriter(
          metadataManager: failingManager,
          syncStateStorage: syncStateStorage,
        );

        final result = await failingWriter.writeBatch(
          barsByStock: {
            '000001': [buildBar(DateTime(2026, 2, 13, 9, 30))],
            '000002': [buildBar(DateTime(2026, 2, 13, 9, 31))],
          },
          dataType: KLineDataType.oneMinute,
          fetchedTradingDay: DateTime(2026, 2, 13),
        );

        expect(result.updatedStocks, ['000001']);
        expect(result.totalRecords, 1);
        expect(result.outcomesByStock.keys, containsAll(['000001', '000002']));
        expect(result.outcomesByStock['000001']!.success, isTrue);
        expect(result.outcomesByStock['000002']!.success, isFalse);
        expect(result.errorsByStock.containsKey('000002'), isTrue);
        expect(
          result.errorsByStock['000002'],
          contains('persist fail: 000002'),
        );

        final sync000002 = await syncStateStorage.getByStockCode('000002');
        expect(sync000002, isNotNull);
        expect(sync000002!.consecutiveFailures, 1);
        expect(sync000002.lastError, contains('persist fail: 000002'));
      },
    );
  });
}
