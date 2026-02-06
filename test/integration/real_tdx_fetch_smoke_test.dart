import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

void main() {
  final runRealFetch = Platform.environment['RUN_REAL_TDX_TEST'] == '1';

  group('RealTDX Smoke', () {
    late Directory testDir;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late KLineMetadataManager manager;
    late TdxClient tdxClient;
    late MarketDataRepository repository;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp('real_tdx_repo_test_');

      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();

      database = MarketDatabase();
      await database.database;

      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
      );

      tdxClient = TdxClient();
      repository = MarketDataRepository(
        metadataManager: manager,
        tdxClient: tdxClient,
      );
    });

    tearDown(() async {
      await repository.dispose();
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
      'fetchMissingData pulls real minute bars from TDX',
      () async {
        // Step 1: Probe real minute bars to pick a concrete trading day.
        final connected = await tdxClient.autoConnect();
        expect(connected, isTrue);

        final probeBars = await tdxClient.getSecurityBars(
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

        // Step 2: Seed daily bar so repository can infer trading dates.
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

        // Step 3: Ensure minute layer starts empty.
        await repository.cleanupOldData(
          beforeDate: probeDate.add(const Duration(days: 1)),
          dataType: KLineDataType.oneMinute,
        );

        final dateRange = DateRange(
          probeDate,
          probeDate.add(const Duration(hours: 23, minutes: 59)),
        );

        // Step 4: Real fetch via repository pipeline.
        final result = await repository.fetchMissingData(
          stockCodes: ['000001'],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );

        expect(result.failureCount, equals(0));
        expect(result.totalRecords, greaterThan(0));

        final loaded = await repository.getKlines(
          stockCodes: ['000001'],
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
        );
        expect(loaded['000001'], isNotEmpty);
      },
      skip: runRealFetch
          ? false
          : 'Set RUN_REAL_TDX_TEST=1 to run real network smoke test',
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
