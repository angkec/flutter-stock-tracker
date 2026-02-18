import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/daily_kline_sync_service.dart';

KLine _bar(DateTime date) {
  return KLine(
    datetime: date,
    open: 10,
    high: 10.4,
    low: 9.8,
    close: 10.2,
    volume: 1000,
    amount: 10000,
  );
}

class _FakeCheckpointStore extends DailyKlineCheckpointStore {
  _FakeCheckpointStore({Map<String, int>? perStock})
    : _perStock = perStock == null ? <String, int>{} : Map.of(perStock);

  Map<String, int> _perStock;
  DailyKlineGlobalCheckpoint? _global;

  @override
  Future<void> saveGlobal({
    required String dateKey,
    required DailyKlineSyncMode mode,
    required int successAtMs,
  }) async {
    _global = DailyKlineGlobalCheckpoint(
      dateKey: dateKey,
      mode: mode,
      successAtMs: successAtMs,
    );
  }

  @override
  Future<DailyKlineGlobalCheckpoint?> loadGlobal() async => _global;

  @override
  Future<void> savePerStockSuccessAtMs(Map<String, int> value) async {
    _perStock = Map.of(value);
  }

  @override
  Future<Map<String, int>> loadPerStockSuccessAtMs() async => Map.of(_perStock);
}

class _FakeCacheStore extends DailyKlineCacheStore {
  _FakeCacheStore()
    : super(
        storage: KLineFileStorage()
          ..setBaseDirPathForTesting(Directory.systemTemp.path),
      );

  Map<String, List<KLine>> lastSaved = const <String, List<KLine>>{};

  @override
  Future<void> saveAll(
    Map<String, List<KLine>> barsByStockCode, {
    void Function(int current, int total)? onProgress,
    int? maxConcurrentWrites,
  }) async {
    lastSaved = Map.of(barsByStockCode);
    onProgress?.call(barsByStockCode.length, barsByStockCode.length);
  }
}

class _RecordingFetcher {
  DailyKlineSyncMode? lastMode;
  List<String> lastRequestedCodes = const <String>[];

  Future<Map<String, List<KLine>>> call({
    required List<Stock> stocks,
    required int count,
    required DailyKlineSyncMode mode,
    void Function(int current, int total)? onProgress,
  }) async {
    lastMode = mode;
    lastRequestedCodes = stocks
        .map((stock) => stock.code)
        .toList(growable: false);
    onProgress?.call(stocks.length, stocks.length);
    return {
      for (final stock in stocks) stock.code: [_bar(DateTime(2026, 2, 17))],
    };
  }
}

void main() {
  test(
    'incremental sync fetches stale stocks and returns partial failures',
    () async {
      final now = DateTime(2026, 2, 17, 10);
      final nowMs = now.millisecondsSinceEpoch;
      final yesterdayMs = now
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;

      final checkpointStore = _FakeCheckpointStore(
        perStock: {'600000': nowMs, '000001': yesterdayMs},
      );
      final cacheStore = _FakeCacheStore();

      final service = DailyKlineSyncService(
        checkpointStore: checkpointStore,
        cacheStore: cacheStore,
        fetcher:
            ({
              required List<Stock> stocks,
              required int count,
              required DailyKlineSyncMode mode,
              void Function(int current, int total)? onProgress,
            }) async {
              return {
                '000001': [_bar(DateTime(2026, 2, 17))],
                // 300001 intentionally omitted to simulate failure
              };
            },
        nowProvider: () => now,
      );

      final result = await service.sync(
        mode: DailyKlineSyncMode.incremental,
        stocks: [
          Stock(code: '600000', name: 'A', market: 1),
          Stock(code: '000001', name: 'B', market: 0),
          Stock(code: '300001', name: 'C', market: 0),
        ],
        targetBars: 260,
      );

      expect(result.successStockCodes, ['000001']);
      expect(result.failureStockCodes, ['300001']);
      expect(result.completenessState, DailySyncCompletenessState.unknownRetry);
      expect(cacheStore.lastSaved.keys, ['000001']);
      expect(
        (await checkpointStore.loadPerStockSuccessAtMs())['000001'],
        nowMs,
      );
      expect(
        (await checkpointStore.loadPerStockSuccessAtMs())['600000'],
        nowMs,
      );
    },
  );

  test('forceFull sync ignores checkpoints and targets all stocks', () async {
    final fetcher = _RecordingFetcher();

    final service = DailyKlineSyncService(
      checkpointStore: _FakeCheckpointStore(perStock: {'600000': 123}),
      cacheStore: _FakeCacheStore(),
      fetcher: fetcher.call,
      nowProvider: () => DateTime(2026, 2, 17, 10),
    );

    final result = await service.sync(
      mode: DailyKlineSyncMode.forceFull,
      stocks: [
        Stock(code: '600000', name: 'A', market: 1),
        Stock(code: '000001', name: 'B', market: 0),
      ],
      targetBars: 260,
    );

    expect(fetcher.lastMode, DailyKlineSyncMode.forceFull);
    expect(fetcher.lastRequestedCodes, ['600000', '000001']);
    expect(result.completenessState, DailySyncCompletenessState.finalOverride);
  });

  test(
    'incremental sync returns intraday_partial completeness for successful run',
    () async {
      final service = DailyKlineSyncService(
        checkpointStore: _FakeCheckpointStore(),
        cacheStore: _FakeCacheStore(),
        fetcher:
            ({
              required List<Stock> stocks,
              required int count,
              required DailyKlineSyncMode mode,
              void Function(int current, int total)? onProgress,
            }) async {
              return {
                for (final stock in stocks)
                  stock.code: [_bar(DateTime(2026, 2, 17))],
              };
            },
        nowProvider: () => DateTime(2026, 2, 17, 10),
      );

      final result = await service.sync(
        mode: DailyKlineSyncMode.incremental,
        stocks: [
          Stock(code: '600000', name: 'A', market: 1),
          Stock(code: '000001', name: 'B', market: 0),
        ],
        targetBars: 260,
      );

      expect(
        result.completenessState,
        DailySyncCompletenessState.intradayPartial,
      );
    },
  );
}
