import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_monthly_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
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

class _RecordingMonthlyWriter {
  Map<String, List<KLine>> lastPayload = const <String, List<KLine>>{};
  int callCount = 0;

  Future<void> call(
    Map<String, List<KLine>> barsByStock, {
    void Function(int current, int total)? onProgress,
  }) async {
    callCount++;
    lastPayload = Map.of(barsByStock);
  }
}

class _SaveCall {
  final String stockCode;
  final List<KLine> bars;
  final KLineDataType dataType;
  final bool bumpVersion;

  const _SaveCall({
    required this.stockCode,
    required this.bars,
    required this.dataType,
    required this.bumpVersion,
  });
}

class _RecordingMetadataManager extends KLineMetadataManager {
  _RecordingMetadataManager() : super();

  final List<_SaveCall> saveCalls = [];
  final List<String> versionCalls = [];

  @override
  Future<void> saveKlineData({
    required String stockCode,
    required List<KLine> newBars,
    required KLineDataType dataType,
    bool bumpVersion = true,
  }) async {
    saveCalls.add(
      _SaveCall(
        stockCode: stockCode,
        bars: newBars,
        dataType: dataType,
        bumpVersion: bumpVersion,
      ),
    );
  }

  @override
  Future<int> incrementDataVersion(String description) async {
    versionCalls.add(description);
    return versionCalls.length;
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

  test('incremental sync forwards successful payload to monthly writer', () async {
    final monthlyWriter = _RecordingMonthlyWriter();
    final cacheStore = _FakeCacheStore();
    final service = DailyKlineSyncService(
      checkpointStore: _FakeCheckpointStore(),
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
      monthlyWriter: monthlyWriter.call,
      nowProvider: () => DateTime(2026, 2, 17, 10),
    );

    final result = await service.sync(
      mode: DailyKlineSyncMode.incremental,
      stocks: [
        Stock(code: '000001', name: 'A', market: 0),
        Stock(code: '300001', name: 'B', market: 0),
      ],
      targetBars: 260,
    );

    expect(result.successStockCodes, ['000001']);
    expect(result.failureStockCodes, ['300001']);
    expect(monthlyWriter.callCount, 1);
    expect(monthlyWriter.lastPayload.keys, ['000001']);
    expect(monthlyWriter.lastPayload, cacheStore.lastSaved);
  });

  test(
    'incremental sync rethrows monthly writer failure and keeps cache',
    () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
      };
      addTearDown(() {
        debugPrint = originalDebugPrint;
      });

      final cacheStore = _FakeCacheStore();
      final service = DailyKlineSyncService(
        checkpointStore: _FakeCheckpointStore(),
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
              };
            },
        monthlyWriter: (
          Map<String, List<KLine>> barsByStock, {
          void Function(int current, int total)? onProgress,
        }) async {
          throw StateError('monthly failure');
        },
        nowProvider: () => DateTime(2026, 2, 17, 10),
      );

      await expectLater(
        service.sync(
          mode: DailyKlineSyncMode.incremental,
          stocks: [Stock(code: '000001', name: 'A', market: 0)],
          targetBars: 260,
        ),
        throwsA(isA<StateError>()),
      );

      expect(cacheStore.lastSaved.keys, ['000001']);
      expect(
        logs.any((message) => message.contains('monthly persist failed')),
        isTrue,
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

  test('monthly writer persists each stock and bumps version once', () async {
    final manager = _RecordingMetadataManager();
    final writer = DailyKlineMonthlyWriterImpl(manager: manager);

    await writer({
      '000001': [_bar(DateTime(2026, 2, 17))],
      '000002': [_bar(DateTime(2026, 2, 17))],
    });

    expect(manager.saveCalls.length, 2);
    expect(
      manager.saveCalls.map((call) => call.stockCode),
      unorderedEquals(['000001', '000002']),
    );
    expect(
      manager.saveCalls.every((call) => call.dataType == KLineDataType.daily),
      isTrue,
    );
    expect(
      manager.saveCalls.every((call) => call.bumpVersion == false),
      isTrue,
    );
    expect(manager.versionCalls, ['Daily sync monthly persist']);
  });
}
