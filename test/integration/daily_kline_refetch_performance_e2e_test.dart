import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _StageTiming {
  DateTime? first;
  DateTime? last;
  int eventCount = 0;

  void mark() {
    final now = DateTime.now();
    first ??= now;
    last = now;
    eventCount++;
  }

  int get elapsedMs {
    if (first == null || last == null) {
      return 0;
    }
    return last!.difference(first!).inMilliseconds;
  }
}

class _GeneratedBarsPool extends TdxPool {
  _GeneratedBarsPool({
    required this.generatedBars,
    this.throwOnBatchFetch = false,
  }) : super(poolSize: 1);

  final List<KLine> generatedBars;
  final bool throwOnBatchFetch;

  int ensureConnectedCalls = 0;
  int batchFetchCalls = 0;
  bool connected = false;

  @override
  Future<bool> ensureConnected() async {
    ensureConnectedCalls++;
    connected = true;
    return true;
  }

  @override
  Future<void> batchGetSecurityBarsStreaming({
    required List<Stock> stocks,
    required int category,
    required int start,
    required int count,
    required void Function(int stockIndex, List<KLine> bars) onStockBars,
  }) async {
    batchFetchCalls++;

    if (!connected) {
      throw StateError('Not connected');
    }
    if (throwOnBatchFetch) {
      throw StateError('Unexpected network fetch');
    }

    for (var index = 0; index < stocks.length; index++) {
      onStockBars(index, generatedBars);
    }
  }
}

class _NoopDataRepository implements DataRepository {
  @override
  Stream<DataStatus> get statusStream => const Stream.empty();

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => const Stream.empty();

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    return {for (final code in stockCodes) code: const <KLine>[]};
  }

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Quote>> getQuotes({required List<String> stockCodes}) {
    throw UnimplementedError();
  }

  @override
  Future<int> getCurrentVersion() async => 1;

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) {
    throw UnimplementedError();
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}
}

List<KLine> _buildDailyBars(int count) {
  final start = DateTime(2025, 1, 1);
  return List.generate(count, (index) {
    final dt = start.add(Duration(days: index));
    final base = 10 + index * 0.02;
    return KLine(
      datetime: dt,
      open: base,
      close: base + ((index % 5) - 2) * 0.03,
      high: base + 0.2,
      low: base - 0.2,
      volume: 1000.0 + index,
      amount: 10000.0 + index,
    );
  });
}

List<StockMonitorData> _buildMonitorData(int stockCount) {
  return List.generate(stockCount, (index) {
    final code = '${600000 + index}';
    return StockMonitorData(
      stock: Stock(code: code, name: '股票$index', market: 1),
      ratio: 1.2,
      changePercent: 0.8,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final runPerfE2E = Platform.environment['RUN_DAILY_KLINE_PERF_E2E'] == '1';

  group('DailyKline Refetch Performance E2E', () {
    test(
      'forceRefetchDailyBars should complete within thresholds',
      () async {
        final stockCount =
            int.tryParse(Platform.environment['DAILY_PERF_STOCKS'] ?? '') ??
            800;
        final barsPerStock =
            int.tryParse(Platform.environment['DAILY_PERF_BARS'] ?? '') ?? 260;
        final maxFetchMs =
            int.tryParse(
              Platform.environment['DAILY_PERF_MAX_FETCH_MS'] ?? '',
            ) ??
            25000;
        final maxComputeMs =
            int.tryParse(
              Platform.environment['DAILY_PERF_MAX_COMPUTE_MS'] ?? '',
            ) ??
            25000;
        final maxTotalMs =
            int.tryParse(
              Platform.environment['DAILY_PERF_MAX_TOTAL_MS'] ?? '',
            ) ??
            45000;

        final tempDir = await Directory.systemTemp.createTemp(
          'daily-kline-perf-e2e-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final monitorData = _buildMonitorData(stockCount);
        final tradingDay = DateTime(2026, 2, 15);

        SharedPreferences.setMockInitialValues({
          'market_data_cache': jsonEncode(
            monitorData.map((item) => item.toJson()).toList(growable: false),
          ),
          'market_data_date': tradingDay.toIso8601String(),
          'minute_data_date': tradingDay.toIso8601String(),
          'minute_data_cache_v1': stockCount,
        });

        final bars = _buildDailyBars(barsPerStock);
        final pool = _GeneratedBarsPool(generatedBars: bars);
        final provider = MarketDataProvider(
          pool: pool,
          stockService: StockService(pool),
          industryService: IndustryService(),
          dailyBarsFileStorage: DailyKlineCacheStore(
            storage: KLineFileStorage()..setBaseDirPathForTesting(tempDir.path),
          ),
        );
        provider.setPullbackService(PullbackService());
        provider.setBreakoutService(BreakoutService());

        final macdStorage = KLineFileStorage()
          ..setBaseDirPathForTesting(tempDir.path);
        final macdService = MacdIndicatorService(
          repository: _NoopDataRepository(),
          cacheStore: MacdCacheStore(storage: macdStorage),
        );
        await macdService.load();
        provider.setMacdService(macdService);

        await provider.loadFromCache();

        final fetchTiming = _StageTiming();
        final writeTiming = _StageTiming();
        final computeTiming = _StageTiming();
        final metadataTiming = _StageTiming();

        final totalStopwatch = Stopwatch()..start();
        await provider.forceRefetchDailyBars(
          onProgress: (stage, _, __) {
            if (stage.startsWith('1/4 ')) {
              fetchTiming.mark();
            } else if (stage.startsWith('2/4 ')) {
              writeTiming.mark();
            } else if (stage.startsWith('3/4 ')) {
              computeTiming.mark();
            } else if (stage.startsWith('4/4 ')) {
              metadataTiming.mark();
            }
          },
        );
        totalStopwatch.stop();

        final fetchMs = fetchTiming.elapsedMs;
        final computeMs = computeTiming.elapsedMs;
        final totalMs = totalStopwatch.elapsedMilliseconds;

        debugPrint(
          '[daily_kline_perf_e2e] stocks=$stockCount bars=$barsPerStock '
          'fetchMs=$fetchMs writeMs=${writeTiming.elapsedMs} '
          'computeMs=$computeMs metadataMs=${metadataTiming.elapsedMs} '
          'totalMs=$totalMs '
          'fetchEvents=${fetchTiming.eventCount} '
          'computeEvents=${computeTiming.eventCount}',
        );

        expect(pool.batchFetchCalls, 1);
        expect(provider.dailyBarsCacheCount, stockCount);
        expect(provider.dailyBarsCacheSize, isNot('<1KB'));
        expect(fetchTiming.eventCount, greaterThan(0));
        expect(computeTiming.eventCount, greaterThan(0));

        expect(
          fetchMs,
          lessThanOrEqualTo(maxFetchMs),
          reason:
              '日K拉取阶段过慢: ${fetchMs}ms > ${maxFetchMs}ms (stocks=$stockCount, bars=$barsPerStock)',
        );
        expect(
          computeMs,
          lessThanOrEqualTo(maxComputeMs),
          reason:
              '指标计算阶段过慢: ${computeMs}ms > ${maxComputeMs}ms (stocks=$stockCount, bars=$barsPerStock)',
        );
        expect(
          totalMs,
          lessThanOrEqualTo(maxTotalMs),
          reason:
              '总流程过慢: ${totalMs}ms > ${maxTotalMs}ms (stocks=$stockCount, bars=$barsPerStock)',
        );
      },
      skip: runPerfE2E
          ? false
          : 'Set RUN_DAILY_KLINE_PERF_E2E=1 to run daily refetch performance E2E',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
