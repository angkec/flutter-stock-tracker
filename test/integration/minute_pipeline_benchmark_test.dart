import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
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
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

void main() {
  final runBench = Platform.environment['RUN_REAL_TDX_BENCH'] == '1';

  final benchDays =
      int.tryParse(Platform.environment['BENCH_DAYS'] ?? '') ?? 20;
  final stockLimit =
      int.tryParse(Platform.environment['BENCH_STOCK_LIMIT'] ?? '') ?? 0;
  final poolSize =
      int.tryParse(Platform.environment['BENCH_POOL_SIZE'] ?? '') ?? 12;
  final batchCount =
      int.tryParse(Platform.environment['BENCH_BATCH_COUNT'] ?? '') ?? 800;
  final maxBatches =
      int.tryParse(Platform.environment['BENCH_MAX_BATCHES'] ?? '') ?? 10;
  final writeConcurrency =
      int.tryParse(Platform.environment['BENCH_WRITE_CONCURRENCY'] ?? '') ?? 6;

  group('MinutePipeline Benchmark', () {
    late Directory testDir;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late KLineFileStorageV2 dailyFileStorage;
    late KLineMetadataManager manager;
    late TdxPool pool;
    late MarketDataRepository repository;
    late TdxClient probeClient;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp('minute_pipeline_bench_');

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
      probeClient = TdxClient();

      repository = MarketDataRepository(
        metadataManager: manager,
        minuteFetchAdapter: TdxPoolFetchAdapter(pool: pool),
        minuteSyncConfig: MinuteSyncConfig(
          enablePoolMinutePipeline: true,
          enableMinutePipelineLogs: true,
          minutePipelineFallbackToLegacyOnError: false,
          poolBatchCount: batchCount,
          poolMaxBatches: maxBatches,
          minuteWriteConcurrency: writeConcurrency,
        ),
      );
    });

    tearDown(() async {
      await repository.dispose();
      await pool.disconnect();
      await probeClient.disconnect();

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
      'compares first full fetch vs second incremental fetch on A-shares',
      () async {
        final connectedPool = await pool.ensureConnected();
        expect(connectedPool, isTrue);

        final stockService = StockService(pool);

        final allStocks = await stockService.getAllStocks();
        expect(allStocks, isNotEmpty);

        final selectedStocks = stockLimit > 0 && stockLimit < allStocks.length
            ? allStocks.take(stockLimit).toList(growable: false)
            : allStocks;

        final stockCodes = selectedStocks
            .map((stock) => stock.code)
            .toList(growable: false);

        final connected = await probeClient.autoConnect();
        expect(connected, isTrue);

        final dailyBars = await probeClient.getSecurityBars(
          market: 0,
          code: '000001',
          category: klineTypeDaily,
          start: 0,
          count: 180,
        );
        expect(dailyBars, isNotEmpty);

        final dailyByDate = <DateTime, KLine>{};
        for (final bar in dailyBars) {
          final dateOnly = DateTime(
            bar.datetime.year,
            bar.datetime.month,
            bar.datetime.day,
          );
          dailyByDate[dateOnly] = KLine(
            datetime: dateOnly,
            open: bar.open,
            close: bar.close,
            high: bar.high,
            low: bar.low,
            volume: bar.volume,
            amount: bar.amount,
          );
        }

        final tradingDates = dailyByDate.keys.toList()..sort();
        expect(tradingDates.length, greaterThanOrEqualTo(benchDays));

        final selectedDates = tradingDates.sublist(
          tradingDates.length - benchDays,
        );
        final dailySeedBars = [
          for (final day in selectedDates) dailyByDate[day]!,
        ];

        await manager.saveKlineData(
          stockCode: '000001',
          newBars: dailySeedBars,
          dataType: KLineDataType.daily,
        );

        final dateRange = DateRange(
          selectedDates.first,
          DateTime(
            selectedDates.last.year,
            selectedDates.last.month,
            selectedDates.last.day,
            23,
            59,
            59,
          ),
        );

        var lastFirstProgress = 0;
        final firstResult = await repository.fetchMissingData(
          stockCodes: stockCodes,
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
          onProgress: (current, total) {
            if (total <= 0) return;
            final percent = (current * 100 ~/ total);
            if (percent >= lastFirstProgress + 10) {
              lastFirstProgress = percent;
              // ignore: avoid_print
              print('[BENCH][first] progress=$percent% ($current/$total)');
            }
          },
        );

        var lastSecondProgress = 0;
        final secondResult = await repository.fetchMissingData(
          stockCodes: stockCodes,
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
          onProgress: (current, total) {
            if (total <= 0) return;
            final percent = (current * 100 ~/ total);
            if (percent >= lastSecondProgress + 10) {
              lastSecondProgress = percent;
              // ignore: avoid_print
              print('[BENCH][second] progress=$percent% ($current/$total)');
            }
          },
        );

        final firstMs = firstResult.duration.inMilliseconds;
        final secondMs = secondResult.duration.inMilliseconds;
        final speedup = secondMs == 0 ? 0.0 : firstMs / secondMs;

        final firstStocksPerMinute = firstMs == 0
            ? 0.0
            : stockCodes.length * 60000 / firstMs;
        final secondStocksPerMinute = secondMs == 0
            ? 0.0
            : stockCodes.length * 60000 / secondMs;

        // ignore: avoid_print
        print(
          '[BENCH] stocks=${stockCodes.length} days=$benchDays '
          'poolSize=$poolSize batchCount=$batchCount maxBatches=$maxBatches '
          'writeConcurrency=$writeConcurrency',
        );
        // ignore: avoid_print
        print(
          '[BENCH][first] durationMs=$firstMs totalRecords=${firstResult.totalRecords} '
          'success=${firstResult.successCount} failure=${firstResult.failureCount} '
          'stocksPerMin=${firstStocksPerMinute.toStringAsFixed(2)}',
        );
        // ignore: avoid_print
        print(
          '[BENCH][second] durationMs=$secondMs totalRecords=${secondResult.totalRecords} '
          'success=${secondResult.successCount} failure=${secondResult.failureCount} '
          'stocksPerMin=${secondStocksPerMinute.toStringAsFixed(2)}',
        );
        // ignore: avoid_print
        print(
          '[BENCH][compare] speedup=${speedup.toStringAsFixed(2)}x '
          'deltaMs=${firstMs - secondMs}',
        );

        expect(firstResult.totalStocks, stockCodes.length);
        expect(secondResult.totalStocks, stockCodes.length);
      },
      skip: runBench
          ? false
          : 'Set RUN_REAL_TDX_BENCH=1 to run minute pipeline benchmark',
      timeout: const Timeout(Duration(minutes: 30)),
    );
  });
}
