import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stock_rtwatcher/config/minute_sync_config.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

typedef _SweepConfig = ({int fetchBatchSize, int persistConcurrency});

class _ProfilingMarketDataRepository extends MarketDataRepository {
  _ProfilingMarketDataRepository({
    required super.metadataManager,
    required super.minuteFetchAdapter,
    required super.klineFetchAdapter,
    required super.minuteSyncConfig,
  });

  int getKlinesCallCount = 0;
  int getKlinesTotalMs = 0;
  int getKlinesTotalStocks = 0;
  int getKlinesTotalBars = 0;

  void resetKlineProfiling() {
    getKlinesCallCount = 0;
    getKlinesTotalMs = 0;
    getKlinesTotalStocks = 0;
    getKlinesTotalBars = 0;
  }

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    getKlinesCallCount++;
    final stopwatch = Stopwatch()..start();
    final result = await super.getKlines(
      stockCodes: stockCodes,
      dateRange: dateRange,
      dataType: dataType,
    );
    stopwatch.stop();

    getKlinesTotalMs += stopwatch.elapsedMilliseconds;
    getKlinesTotalStocks += stockCodes.length;
    getKlinesTotalBars += result.values.fold<int>(
      0,
      (sum, bars) => sum + bars.length,
    );

    return result;
  }
}

class _ProfilingAdxCacheStore extends AdxCacheStore {
  _ProfilingAdxCacheStore({required super.storage});

  int saveAllCallCount = 0;
  int saveAllTotalMs = 0;
  int savedSeriesCount = 0;

  void resetPersistProfiling() {
    saveAllCallCount = 0;
    saveAllTotalMs = 0;
    savedSeriesCount = 0;
  }

  @override
  Future<void> saveAll(
    List<AdxCacheSeries> items, {
    int? maxConcurrentWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    saveAllCallCount++;
    final stopwatch = Stopwatch()..start();
    await super.saveAll(
      items,
      maxConcurrentWrites: maxConcurrentWrites,
      onProgress: onProgress,
    );
    stopwatch.stop();

    saveAllTotalMs += stopwatch.elapsedMilliseconds;
    savedSeriesCount += items.length;
  }
}

class _ProfilingAdxIndicatorService extends AdxIndicatorService {
  _ProfilingAdxIndicatorService({
    required super.repository,
    required super.cacheStore,
  });

  int getOrComputeCallCount = 0;
  int getOrComputeTotalMs = 0;

  @override
  Future<List<AdxPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
    bool persistToDisk = true,
    void Function(AdxCacheSeries series)? onSeriesComputed,
  }) async {
    getOrComputeCallCount++;
    final stopwatch = Stopwatch()..start();
    final result = await super.getOrComputeFromBars(
      stockCode: stockCode,
      dataType: dataType,
      bars: bars,
      forceRecompute: forceRecompute,
      persistToDisk: persistToDisk,
      onSeriesComputed: onSeriesComputed,
    );
    stopwatch.stop();
    getOrComputeTotalMs += stopwatch.elapsedMilliseconds;
    return result;
  }
}

void main() {
  final runBench = Platform.environment['RUN_REAL_WEEKLY_ADX_BENCH'] == '1';
  final stockLimit =
      int.tryParse(
        Platform.environment['WEEKLY_ADX_BENCH_STOCK_LIMIT'] ?? '',
      ) ??
      200;
  final poolSize =
      int.tryParse(Platform.environment['WEEKLY_ADX_BENCH_POOL_SIZE'] ?? '') ??
      12;
  final rangeDays =
      int.tryParse(Platform.environment['WEEKLY_ADX_BENCH_RANGE_DAYS'] ?? '') ??
      760;
  final sweepRaw =
      Platform.environment['WEEKLY_ADX_BENCH_SWEEP'] ?? '40x6,80x8,120x8';
  final sweepConfigs = _parseSweepConfigs(sweepRaw);

  group('Weekly ADX Recompute Benchmark', () {
    late Directory testDir;
    late MarketDatabase database;
    late KLineFileStorage fileStorage;
    late KLineMetadataManager manager;
    late TdxPool pool;
    late _ProfilingMarketDataRepository repository;
    late _ProfilingAdxCacheStore cacheStore;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp(
        'weekly_adx_recompute_bench_',
      );

      fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(testDir.path);
      await fileStorage.initialize();

      database = MarketDatabase();
      await database.database;

      manager = KLineMetadataManager(
        database: database,
        fileStorage: fileStorage,
      );
      pool = TdxPool(poolSize: poolSize);
      final adapter = TdxPoolFetchAdapter(pool: pool);
      repository = _ProfilingMarketDataRepository(
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

      cacheStore = _ProfilingAdxCacheStore(storage: fileStorage);
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
        final file = File('$dbPath/market_data.db');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    test(
      'benchmarks weekly ADX recompute latency and throughput sweep',
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
            .where((code) => code.isNotEmpty)
            .toSet()
            .toList(growable: false);
        expect(stockCodes, isNotEmpty);

        final now = DateTime.now();
        final dateRange = DateRange(
          now.subtract(Duration(days: rangeDays)),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );

        // 先拉齐周K，避免 sweep 时重复网络开销。
        final fetchStopwatch = Stopwatch()..start();
        final fetchResult = await repository.fetchMissingData(
          stockCodes: stockCodes,
          dateRange: dateRange,
          dataType: KLineDataType.weekly,
        );
        fetchStopwatch.stop();

        // ignore: avoid_print
        print(
          '[WEEKLY_ADX_BENCH][seed] stocks=${stockCodes.length} '
          'durationMs=${fetchStopwatch.elapsedMilliseconds} '
          'records=${fetchResult.totalRecords} '
          'failure=${fetchResult.failureCount}',
        );

        expect(fetchResult.totalStocks, stockCodes.length);

        final benchRows = <Map<String, int>>[];

        for (final config in sweepConfigs) {
          await cacheStore.clearForStocks(stockCodes);
          repository.resetKlineProfiling();
          cacheStore.resetPersistProfiling();

          final service = _ProfilingAdxIndicatorService(
            repository: repository,
            cacheStore: cacheStore,
          );
          await service.load();

          final stopwatch = Stopwatch()..start();
          int? firstProgressMs;
          int progressCurrent = 0;
          int progressTotal = 0;

          await service.prewarmFromRepository(
            stockCodes: stockCodes,
            dataType: KLineDataType.weekly,
            dateRange: dateRange,
            forceRecompute: false,
            fetchBatchSize: config.fetchBatchSize,
            maxConcurrentPersistWrites: config.persistConcurrency,
            onProgress: (current, total) {
              progressCurrent = current;
              progressTotal = total;
              firstProgressMs ??= stopwatch.elapsedMilliseconds;
            },
          );
          stopwatch.stop();

          final totalMs = stopwatch.elapsedMilliseconds;
          final firstMs = firstProgressMs ?? totalMs;
          final fetchMs = repository.getKlinesTotalMs;
          final persistMs = cacheStore.saveAllTotalMs;
          final computeMs = service.getOrComputeTotalMs;
          final throughputX10 = totalMs <= 0
              ? 0
              : ((stockCodes.length * 10000) / totalMs).round();

          final row = <String, int>{
            'fetchBatchSize': config.fetchBatchSize,
            'persistConcurrency': config.persistConcurrency,
            'firstProgressMs': firstMs,
            'fetchMs': fetchMs,
            'computeMs': computeMs,
            'persistMs': persistMs,
            'totalMs': totalMs,
            'stocks': stockCodes.length,
            'bars': repository.getKlinesTotalBars,
            'klineCalls': repository.getKlinesCallCount,
            'persistCalls': cacheStore.saveAllCallCount,
            'savedSeries': cacheStore.savedSeriesCount,
            'computeCalls': service.getOrComputeCallCount,
            'progressCurrent': progressCurrent,
            'progressTotal': progressTotal,
            'throughputX10': throughputX10,
          };
          benchRows.add(row);

          // ignore: avoid_print
          print(
            '[WEEKLY_ADX_BENCH][run] fetchBatch=${config.fetchBatchSize} '
            'persistConcurrency=${config.persistConcurrency} '
            'firstProgressMs=${row['firstProgressMs']} '
            'fetchMs=${row['fetchMs']} computeMs=${row['computeMs']} '
            'persistMs=${row['persistMs']} totalMs=${row['totalMs']} '
            'stocks=${row['stocks']} '
            'klineCalls=${row['klineCalls']} persistCalls=${row['persistCalls']} '
            'savedSeries=${row['savedSeries']} computeCalls=${row['computeCalls']} '
            'progress=${row['progressCurrent']}/${row['progressTotal']} '
            'stocksPerSec=${(row['throughputX10']! / 10).toStringAsFixed(1)}',
          );
        }

        const stallThresholdMs = 5000;
        final acceptableRows = benchRows
            .where((row) => (row['firstProgressMs'] ?? 0) <= stallThresholdMs)
            .toList(growable: false);
        final rankingBase = acceptableRows.isNotEmpty
            ? acceptableRows
            : List<Map<String, int>>.from(benchRows, growable: false);
        rankingBase.sort((a, b) {
          final totalCmp = (a['totalMs'] ?? 0).compareTo(b['totalMs'] ?? 0);
          if (totalCmp != 0) {
            return totalCmp;
          }
          return (a['firstProgressMs'] ?? 0).compareTo(
            b['firstProgressMs'] ?? 0,
          );
        });

        final best = rankingBase.first;
        // ignore: avoid_print
        print(
          '[WEEKLY_ADX_BENCH][best] fetchBatch=${best['fetchBatchSize']} '
          'persistConcurrency=${best['persistConcurrency']} '
          'firstProgressMs=${best['firstProgressMs']} totalMs=${best['totalMs']}',
        );

        expect(benchRows, isNotEmpty);
      },
      skip: runBench
          ? false
          : 'Set RUN_REAL_WEEKLY_ADX_BENCH=1 to run benchmark',
      timeout: const Timeout(Duration(minutes: 45)),
    );
  });
}

List<_SweepConfig> _parseSweepConfigs(String raw) {
  final tokens = raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) {
    throw ArgumentError('WEEKLY_ADX_BENCH_SWEEP cannot be empty');
  }

  final configs = <_SweepConfig>[];
  for (final token in tokens) {
    final pieces = token
        .split('x')
        .map((item) => item.trim())
        .toList(growable: false);
    if (pieces.length != 2) {
      throw ArgumentError('Invalid sweep token: $token');
    }
    final fetchBatchSize = int.tryParse(pieces[0]);
    final persistConcurrency = int.tryParse(pieces[1]);
    if (fetchBatchSize == null || persistConcurrency == null) {
      throw ArgumentError('Invalid sweep token: $token');
    }
    if (fetchBatchSize <= 0 || persistConcurrency <= 0) {
      throw ArgumentError('Sweep values must be > 0: $token');
    }
    configs.add((
      fetchBatchSize: fetchBatchSize,
      persistConcurrency: persistConcurrency,
    ));
  }
  return configs;
}
