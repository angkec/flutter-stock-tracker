import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/config/minute_sync_config.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

void main() {
  final runBench = Platform.environment['RUN_REAL_TDX_WEEKLY_BENCH'] == '1';
  final stockLimit =
      int.tryParse(Platform.environment['WEEKLY_BENCH_STOCK_LIMIT'] ?? '') ??
      200;
  final poolSize =
      int.tryParse(Platform.environment['WEEKLY_BENCH_POOL_SIZE'] ?? '') ?? 12;

  group('WeeklyPipeline Benchmark', () {
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
    });

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp('weekly_pipeline_bench_');

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
      pool = TdxPool(poolSize: poolSize);
      final adapter = TdxPoolFetchAdapter(pool: pool);
      repository = MarketDataRepository(
        metadataManager: manager,
        minuteFetchAdapter: adapter,
        klineFetchAdapter: adapter,
        minuteSyncConfig: const MinuteSyncConfig(
          enablePoolMinutePipeline: true,
          enableMinutePipelineLogs: true,
          minutePipelineFallbackToLegacyOnError: false,
          poolBatchCount: 800,
          poolMaxBatches: 10,
          minuteWriteConcurrency: 8,
        ),
      );
    });

    tearDown(() async {
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
      'benchmarks weekly refetch throughput with real TDX pool',
      () async {
        final connected = await pool.ensureConnected();
        expect(connected, isTrue);

        final stockService = StockService(pool);
        final allStocks = await stockService.getAllStocks();
        expect(allStocks, isNotEmpty);

        final selectedStocks = stockLimit > 0 && stockLimit < allStocks.length
            ? allStocks.take(stockLimit).toList(growable: false)
            : allStocks;
        final stockCodes = selectedStocks
            .map((stock) => stock.code)
            .toList(growable: false);

        final now = DateTime.now();
        final dateRange = DateRange(
          now.subtract(const Duration(days: 760)),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );

        DateTime? firstFetchAt;
        DateTime? firstWriteAt;
        DateTime? lastWriteAt;
        var writeCurrent = 0;
        var writeTotal = 0;

        final sub = repository.statusStream.listen((status) {
          if (status is! DataFetching) return;

          if (status.currentStock == '__WRITE__') {
            firstWriteAt ??= DateTime.now();
            lastWriteAt = DateTime.now();
            writeCurrent = status.current;
            writeTotal = status.total;
            return;
          }

          if (status.currentStock != '__PRECHECK__') {
            firstFetchAt ??= DateTime.now();
          }
        });

        final totalStopwatch = Stopwatch()..start();
        final result = await repository.refetchData(
          stockCodes: stockCodes,
          dateRange: dateRange,
          dataType: KLineDataType.weekly,
        );
        totalStopwatch.stop();
        await sub.cancel();

        final totalMs = totalStopwatch.elapsedMilliseconds;
        final fetchMs = firstFetchAt == null || firstWriteAt == null
            ? 0
            : firstWriteAt!.difference(firstFetchAt!).inMilliseconds;
        final writeMs = firstWriteAt == null || lastWriteAt == null
            ? 0
            : lastWriteAt!.difference(firstWriteAt!).inMilliseconds;

        final totalRate = totalMs <= 0
            ? 0.0
            : stockCodes.length * 1000 / totalMs;
        final writeRate = writeMs <= 0 || writeTotal <= 0
            ? 0.0
            : writeTotal * 1000 / writeMs;

        // ignore: avoid_print
        print(
          '[WEEKLY_BENCH] stocks=${stockCodes.length} poolSize=$poolSize '
          'totalMs=$totalMs fetchMs=$fetchMs writeMs=$writeMs '
          'writeProgress=$writeCurrent/$writeTotal totalRecords=${result.totalRecords}',
        );
        // ignore: avoid_print
        print(
          '[WEEKLY_BENCH] totalRate=${totalRate.toStringAsFixed(2)} stocks/s '
          'writeRate=${writeRate.toStringAsFixed(2)} stocks/s '
          'failure=${result.failureCount}',
        );

        expect(result.totalStocks, stockCodes.length);
        expect(writeTotal, equals(stockCodes.length));
      },
      skip: runBench
          ? false
          : 'Set RUN_REAL_TDX_WEEKLY_BENCH=1 to run real weekly benchmark',
      timeout: const Timeout(Duration(minutes: 20)),
    );
  });
}
