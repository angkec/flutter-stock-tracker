import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';

class FakeRepository implements DataRepository {
  FakeRepository(this.barsByCode);

  final Map<String, List<KLine>> barsByCode;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    return {for (final code in stockCodes) code: barsByCode[code] ?? []};
  }

  @override
  Future<int> getCurrentVersion() async => 1;

  @override
  Stream<DataStatus> get statusStream => const Stream.empty();

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => const Stream.empty();

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    return {};
  }

  @override
  Future<Map<String, Quote>> getQuotes({required List<String> stockCodes}) async {
    return {};
  }

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: const <String, String>{},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: const <String, String>{},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) async {}

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) async {
    return const MissingDatesResult(
      missingDates: <DateTime>[],
      incompleteDates: <DateTime>[],
      completeDates: <DateTime>[],
    );
  }

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) async {
    return {};
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
    return <DateTime>[];
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) async => 0;

  @override
  Future<void> dispose() async {}
}

void main() {
  test('macd recompute writes cache when forceRecompute true', () async {
    final bars = <KLine>[
      KLine(
        datetime: DateTime(2024, 1, 1),
        open: 1,
        close: 2,
        high: 2,
        low: 1,
        volume: 1,
        amount: 1,
      ),
      KLine(
        datetime: DateTime(2024, 1, 2),
        open: 2,
        close: 3,
        high: 3,
        low: 2,
        volume: 1,
        amount: 1,
      ),
    ];

    final tempDir = await Directory.systemTemp.createTemp('macd_probe_');
    addTearDown(() async {
      await tempDir.delete(recursive: true);
    });
    final storage = KLineFileStorage()
      ..setBaseDirPathForTesting(tempDir.path);
    final cacheStore = MacdCacheStore(storage: storage);
    final fakeRepo = FakeRepository({'000001': bars});
    final service = MacdIndicatorService(
      repository: fakeRepo,
      cacheStore: cacheStore,
    );

    await service.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: {'000001': bars},
      forceRecompute: true,
    );

    final series = await cacheStore.loadSeries(
      stockCode: '000001',
      dataType: KLineDataType.daily,
    );
    expect(series, isNotNull);
  });
}
