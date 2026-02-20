import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/ema_config.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/industry_ema_breadth_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

List<KLine> _bars(List<(DateTime, double)> entries) {
  return entries
      .map(
        (entry) => KLine(
          datetime: entry.$1,
          open: entry.$2,
          close: entry.$2,
          high: entry.$2,
          low: entry.$2,
          volume: 1,
          amount: 1,
        ),
      )
      .toList(growable: false);
}

class _TrackingEmaCacheStore extends EmaCacheStore {
  _TrackingEmaCacheStore({required this.delay, required this.responses});

  final Duration delay;
  final Map<String, EmaCacheSeries> responses;
  final Set<String> requestedStockCodes = <String>{};
  int _inFlight = 0;
  int maxObservedConcurrency = 0;

  @override
  Future<EmaCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    requestedStockCodes.add(stockCode);
    _inFlight++;
    if (_inFlight > maxObservedConcurrency) {
      maxObservedConcurrency = _inFlight;
    }
    try {
      await Future<void>.delayed(delay);
      return responses[stockCode];
    } finally {
      _inFlight--;
    }
  }
}

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late DailyKlineCacheStore dailyStore;
  late EmaCacheStore emaStore;
  late IndustryEmaBreadthCacheStore breadthStore;
  late IndustryService industryService;
  late IndustryEmaBreadthService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('industry-ema-breadth-');
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);

    dailyStore = DailyKlineCacheStore(storage: storage);
    emaStore = EmaCacheStore(storage: storage);
    breadthStore = IndustryEmaBreadthCacheStore(storage: storage);

    industryService = IndustryService();
    industryService.setTestData({
      'AAA': 'Tech',
      'BBB': 'Tech',
      'CCC': 'Finance',
    });

    service = IndustryEmaBreadthService(
      industryService: industryService,
      dailyCacheStore: dailyStore,
      emaCacheStore: emaStore,
      cacheStore: breadthStore,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('getCachedSeries reads persisted industry series', () async {
    final series = IndustryEmaBreadthSeries(
      industry: 'Tech',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 1, 5),
          percent: 50,
          aboveCount: 1,
          validCount: 2,
          missingCount: 0,
        ),
      ],
    );
    await breadthStore.saveSeries(series);

    final loaded = await service.getCachedSeries('Tech');

    expect(loaded, equals(series));
  });

  test('recomputeAllIndustries uses cached close and EMA only', () async {
    await dailyStore.saveAll({
      'AAA': _bars([(DateTime(2026, 1, 5), 11), (DateTime(2026, 1, 6), 9)]),
      'BBB': _bars([(DateTime(2026, 1, 5), 12)]),
      'CCC': _bars([(DateTime(2026, 1, 5), 20), (DateTime(2026, 1, 6), 21)]),
    });

    await emaStore.saveSeries(
      stockCode: 'AAA',
      dataType: KLineDataType.weekly,
      config: EmaConfig.weeklyDefaults,
      sourceSignature: 'sig-a',
      points: [
        EmaPoint(datetime: DateTime(2026, 1, 2), emaShort: 10, emaLong: 8),
      ],
    );
    await emaStore.saveSeries(
      stockCode: 'BBB',
      dataType: KLineDataType.weekly,
      config: EmaConfig.weeklyDefaults,
      sourceSignature: 'sig-b',
      points: [
        EmaPoint(datetime: DateTime(2026, 1, 2), emaShort: 11, emaLong: 9),
      ],
    );

    final result = await service.recomputeAllIndustries(
      startDate: DateTime(2026, 1, 5),
      endDate: DateTime(2026, 1, 11),
    );

    expect(result.keys.toSet(), equals({'Tech', 'Finance'}));
    expect(result['Tech']!.points, <IndustryEmaBreadthPoint>[
      IndustryEmaBreadthPoint(
        date: DateTime(2026, 1, 5),
        percent: 100,
        aboveCount: 2,
        validCount: 2,
        missingCount: 0,
      ),
      IndustryEmaBreadthPoint(
        date: DateTime(2026, 1, 6),
        percent: 0,
        aboveCount: 0,
        validCount: 1,
        missingCount: 1,
      ),
    ]);

    expect(result['Finance']!.points, <IndustryEmaBreadthPoint>[
      IndustryEmaBreadthPoint(
        date: DateTime(2026, 1, 5),
        percent: null,
        aboveCount: 0,
        validCount: 0,
        missingCount: 1,
      ),
      IndustryEmaBreadthPoint(
        date: DateTime(2026, 1, 6),
        percent: null,
        aboveCount: 0,
        validCount: 0,
        missingCount: 1,
      ),
    ]);

    final cachedTech = await service.getCachedSeries('Tech');
    final cachedFinance = await service.getCachedSeries('Finance');
    expect(cachedTech, equals(result['Tech']));
    expect(cachedFinance, equals(result['Finance']));
  });

  test('recomputeAllIndustries emits fine-grained progress updates', () async {
    await dailyStore.saveAll({
      'AAA': _bars([(DateTime(2026, 1, 5), 11), (DateTime(2026, 1, 6), 9)]),
      'BBB': _bars([(DateTime(2026, 1, 5), 12)]),
      'CCC': _bars([(DateTime(2026, 1, 5), 20), (DateTime(2026, 1, 6), 21)]),
    });

    await emaStore.saveSeries(
      stockCode: 'AAA',
      dataType: KLineDataType.weekly,
      config: EmaConfig.weeklyDefaults,
      sourceSignature: 'sig-a',
      points: [
        EmaPoint(datetime: DateTime(2026, 1, 2), emaShort: 10, emaLong: 8),
      ],
    );
    await emaStore.saveSeries(
      stockCode: 'BBB',
      dataType: KLineDataType.weekly,
      config: EmaConfig.weeklyDefaults,
      sourceSignature: 'sig-b',
      points: [
        EmaPoint(datetime: DateTime(2026, 1, 2), emaShort: 11, emaLong: 9),
      ],
    );

    final events = <({int current, int total, String stage})>[];
    final result = await service.recomputeAllIndustries(
      startDate: DateTime(2026, 1, 5),
      endDate: DateTime(2026, 1, 11),
      onProgress: (current, total, stage) {
        events.add((current: current, total: total, stage: stage));
      },
    );
    final datesPerIndustry = result.values
        .map((series) => series.points.length)
        .fold<int>(
          0,
          (maxLength, length) => length > maxLength ? length : maxLength,
        );
    final expectedTotalUnits = result.length * datesPerIndustry;

    expect(events, isNotEmpty);
    expect(events.first.current, 0);
    expect(events.first.stage, '准备重算行业EMA广度...');
    expect(events.last.total, expectedTotalUnits);
    expect(events.last.current, events.last.total);
    expect(events.where((event) => event.stage.startsWith('已完成 ')), isEmpty);
    expect(events.any((event) => event.stage.startsWith('计算中')), isTrue);
    expect(events.length, greaterThan(4));
  });

  test(
    'recomputeAllIndustries loads weekly EMA cache with bounded concurrency',
    () async {
      final stockCodes = List<String>.generate(
        16,
        (index) => 'S${(index + 1).toString().padLeft(3, '0')}',
        growable: false,
      );
      industryService.setTestData({
        for (final stockCode in stockCodes) stockCode: 'Tech',
      });

      await dailyStore.saveAll({
        for (final stockCode in stockCodes)
          stockCode: _bars([(DateTime(2026, 1, 5), 10)]),
      });

      final trackingStore = _TrackingEmaCacheStore(
        delay: const Duration(milliseconds: 20),
        responses: {
          for (final stockCode in stockCodes)
            stockCode: EmaCacheSeries(
              stockCode: stockCode,
              dataType: KLineDataType.weekly,
              config: EmaConfig.weeklyDefaults,
              sourceSignature: 'sig-$stockCode',
              points: [
                EmaPoint(
                  datetime: DateTime(2026, 1, 2),
                  emaShort: 9,
                  emaLong: 8,
                ),
              ],
            ),
        },
      );
      final localService = IndustryEmaBreadthService(
        industryService: industryService,
        dailyCacheStore: dailyStore,
        emaCacheStore: trackingStore,
        cacheStore: breadthStore,
      );

      final result = await localService.recomputeAllIndustries(
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2026, 1, 5),
      );

      expect(result['Tech']!.points.single.percent, 100);
      expect(trackingStore.requestedStockCodes.length, stockCodes.length);
      expect(trackingStore.maxObservedConcurrency, greaterThan(1));
      expect(trackingStore.maxObservedConcurrency, lessThanOrEqualTo(8));
    },
  );
}
