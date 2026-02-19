import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/config/minute_sync_config.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

void main() {
  final runRealFetch = Platform.environment['RUN_REAL_TDX_TEST'] == '1';

  group('MinutePipeline Smoke', () {
    late Directory testDir;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late KLineFileStorageV2 dailyFileStorage;
    late KLineMetadataManager manager;
    late TdxPool pool;
    late MarketDataRepository repository;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      TestWidgetsFlutterBinding.ensureInitialized();

      testDir = await Directory.systemTemp.createTemp(
        'minute_pipeline_smoke_test_',
      );

      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();

      dailyFileStorage = KLineFileStorageV2();
      dailyFileStorage.setBaseDirPathForTesting(testDir.path);
      await dailyFileStorage.initialize();

      database = MarketDatabase();
      await database.database;

      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
        dailyFileStorage: dailyFileStorage,
      );
      pool = TdxPool(poolSize: 3);
      repository = MarketDataRepository(
        metadataManager: manager,
        minuteFetchAdapter: TdxPoolFetchAdapter(pool: pool),
        minuteSyncConfig: const MinuteSyncConfig(
          enablePoolMinutePipeline: true,
          enableMinutePipelineLogs: true,
          minutePipelineFallbackToLegacyOnError: false,
          poolBatchCount: 800,
        ),
      );
    });

    tearDownAll(() async {
      await repository.dispose();
      await pool.disconnect();

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

    test(
      'fetches minute bars with pool pipeline for sample stocks',
      () async {
        final probeClient = TdxClient();
        final connected = await probeClient.autoConnect();
        expect(connected, isTrue);

        final probeBars = await probeClient.getSecurityBars(
          market: 0,
          code: '000001',
          category: 7,
          start: 0,
          count: 30,
        );
        expect(probeBars, isNotEmpty);

        final probeDate = DateTime(
          probeBars.first.datetime.year,
          probeBars.first.datetime.month,
          probeBars.first.datetime.day,
        );

        await manager.saveKlineData(
          stockCode: '000001',
          newBars: [
            KLine(
              datetime: probeDate,
              open: probeBars.first.open,
              close: probeBars.first.close,
              high: probeBars.first.high,
              low: probeBars.first.low,
              volume: probeBars.first.volume,
              amount: probeBars.first.amount,
            ),
          ],
          dataType: KLineDataType.daily,
        );

        final sampleCodes = ['000001', '000002', '000858', '300750', '600000'];
        final dateRange = DateRange(
          probeDate,
          probeDate.add(const Duration(hours: 23, minutes: 59)),
        );

        final result = await repository.fetchMissingData(
          stockCodes: sampleCodes,
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );

        expect(result.totalStocks, sampleCodes.length);
        expect(result.totalRecords, greaterThan(0));

        await probeClient.disconnect();
      },
      skip: runRealFetch
          ? false
          : 'Set RUN_REAL_TDX_TEST=1 to run real minute pipeline smoke test',
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });
}
