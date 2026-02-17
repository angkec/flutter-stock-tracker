import 'dart:async';
import 'dart:io';

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
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/adx_config.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';

class _FakeDataRepository implements DataRepository {
  Map<String, List<KLine>> klinesByStock = <String, List<KLine>>{};
  int getKlinesCallCount = 0;
  final List<List<String>> getKlinesRequestBatches = <List<String>>[];
  int currentVersion = 1;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    getKlinesCallCount++;
    getKlinesRequestBatches.add(List<String>.from(stockCodes, growable: false));
    return {
      for (final code in stockCodes)
        code: (klinesByStock[code] ?? const <KLine>[])
            .where((bar) => dateRange.contains(bar.datetime))
            .toList(growable: false),
    };
  }

  @override
  Stream<DataStatus> get statusStream => const Stream.empty();

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => const Stream.empty();

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
  Future<int> getCurrentVersion() async => currentVersion;

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

List<KLine> _buildBars(DateTime start, int count) {
  return List.generate(count, (index) {
    final date = DateTime(start.year, start.month, start.day + index);
    final base = 10 + index * 0.05;
    return KLine(
      datetime: date,
      open: base - 0.1,
      close: base + ((index % 5) - 2) * 0.08,
      high: base + 0.3 + (index % 3) * 0.02,
      low: base - 0.3 - (index % 2) * 0.02,
      volume: 1000 + index.toDouble(),
      amount: 10000 + index.toDouble(),
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeDataRepository repository;
  late AdxCacheStore cacheStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    tempDir = await Directory.systemTemp.createTemp('adx-indicator-service-');
    repository = _FakeDataRepository();

    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    cacheStore = AdxCacheStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('getOrComputeFromBars should compute ADX points', () async {
    final service = AdxIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await service.load();

    final bars = _buildBars(DateTime(2025, 8, 1), 120);
    final points = await service.getOrComputeFromBars(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      bars: bars,
    );

    expect(points, isNotEmpty);
    expect(points.first.datetime.isBefore(points.last.datetime), isTrue);
    expect(points.last.adx, greaterThanOrEqualTo(0));
  });

  test(
    'getOrComputeFromBars should reuse existing disk cache when unchanged',
    () async {
      final service = AdxIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();
      final bars = _buildBars(DateTime(2025, 10, 1), 100);

      await service.getOrComputeFromBars(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        bars: bars,
      );

      final cacheFile = File(
        '${tempDir.path}/adx_cache/600000_daily_adx_cache.json',
      );
      expect(await cacheFile.exists(), isTrue);
      final firstModified = await cacheFile.lastModified();

      final serviceAfterRestart = AdxIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await serviceAfterRestart.load();

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await serviceAfterRestart.getOrComputeFromBars(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        bars: bars,
      );

      final secondModified = await cacheFile.lastModified();
      expect(secondModified, firstModified);
    },
  );

  test('updateConfigFor should persist daily and weekly configs independently', () async {
    final service = AdxIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await service.load();

    const dailyConfig = AdxConfig(period: 10, threshold: 28);
    const weeklyConfig = AdxConfig(period: 20, threshold: 30);

    await service.updateConfigFor(
      dataType: KLineDataType.daily,
      newConfig: dailyConfig,
    );
    await service.updateConfigFor(
      dataType: KLineDataType.weekly,
      newConfig: weeklyConfig,
    );

    final reloaded = AdxIndicatorService(
      repository: repository,
      cacheStore: cacheStore,
    );
    await reloaded.load();

    expect(reloaded.configFor(KLineDataType.daily), dailyConfig);
    expect(reloaded.configFor(KLineDataType.weekly), weeklyConfig);
  });

  test(
    'prewarmFromRepository should fetch in chunks and aggregate progress',
    () async {
      final service = AdxIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();

      final stockCodes = <String>[
        '600000',
        '600001',
        '600002',
        '600003',
        '600004',
        '600005',
        '600006',
      ];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 90),
      };

      final progressRecords = <({int current, int total})>[];
      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
        fetchBatchSize: 3,
        onProgress: (current, total) {
          progressRecords.add((current: current, total: total));
        },
      );

      expect(repository.getKlinesCallCount, 3);
      expect(
        repository.getKlinesRequestBatches
            .map((batch) => batch.length)
            .toList(),
        <int>[3, 3, 1],
      );
      expect(progressRecords, isNotEmpty);
      expect(progressRecords.last.total, stockCodes.length * 2);
      expect(progressRecords.last.current, progressRecords.last.total);
    },
  );

  test(
    'prewarmFromRepository should skip unchanged version with same config and stock scope',
    () async {
      final service = AdxIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();
      repository.currentVersion = 42;

      final stockCodes = <String>['600000', '600001', '600002'];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 90),
      };

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 1);

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 1);
    },
  );

  test(
    'prewarmFromRepository should rerun when config changes with same data version',
    () async {
      final service = AdxIndicatorService(
        repository: repository,
        cacheStore: cacheStore,
      );
      await service.load();
      repository.currentVersion = 99;

      const stockCodes = <String>['600000', '600001'];
      repository.klinesByStock = {
        for (final code in stockCodes)
          code: _buildBars(DateTime(2025, 10, 1), 90),
      };

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 1);

      await service.updateConfigFor(
        dataType: KLineDataType.weekly,
        newConfig: const AdxConfig(period: 18, threshold: 32),
      );

      await service.prewarmFromRepository(
        stockCodes: stockCodes,
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2025, 10, 1), DateTime(2026, 2, 1)),
      );
      expect(repository.getKlinesCallCount, 2);
    },
  );
}
