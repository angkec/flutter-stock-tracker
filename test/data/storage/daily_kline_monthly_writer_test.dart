import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_monthly_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('daily monthly writer supports maxConcurrentWrites', () async {
    final dir = await Directory.systemTemp.createTemp('daily_monthly_writer_test_');
    final fileStorage = KLineFileStorage()..setBaseDirPathForTesting(dir.path);
    await fileStorage.initialize();
    final dailyFileStorage = KLineFileStorageV2()..setBaseDirPathForTesting(dir.path);
    await dailyFileStorage.initialize();
    final database = MarketDatabase();
    await database.database;
    final manager = KLineMetadataManager(
      database: database,
      fileStorage: fileStorage,
      dailyFileStorage: dailyFileStorage,
    );

    final writer = DailyKlineMonthlyWriterImpl(
      maxConcurrentWrites: 4,
      manager: manager,
    );

    final payload = <String, List<KLine>>{
      '000001': [
        KLine(
          datetime: DateTime(2026, 2, 18),
          open: 10,
          close: 11,
          high: 12,
          low: 9,
          volume: 100,
          amount: 200,
        ),
      ],
    };

    await writer(payload);

    final meta = await manager.getMetadata(
      stockCode: '000001',
      dataType: KLineDataType.daily,
    );
    expect(meta, isNotEmpty);
  });
}
