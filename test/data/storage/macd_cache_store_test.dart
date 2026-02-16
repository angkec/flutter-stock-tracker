import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';

List<MacdPoint> _buildPoints(DateTime start, int count) {
  return List.generate(count, (index) {
    final date = DateTime(start.year, start.month, start.day + index);
    return MacdPoint(
      datetime: date,
      dif: 0.1 + index * 0.01,
      dea: 0.05 + index * 0.01,
      hist: 0.1,
    );
  });
}

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late MacdCacheStore cacheStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('macd-cache-store-');
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    cacheStore = MacdCacheStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saveSeries + loadSeries should persist and restore payload', () async {
    final config = const MacdConfig(
      fastPeriod: 12,
      slowPeriod: 26,
      signalPeriod: 9,
      windowMonths: 3,
    );

    await cacheStore.saveSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: config,
      sourceSignature: 'daily_sig_001',
      points: _buildPoints(DateTime(2026, 1, 1), 20),
    );

    final loaded = await cacheStore.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );

    expect(loaded, isNotNull);
    expect(loaded!.stockCode, '600000');
    expect(loaded.dataType, KLineDataType.daily);
    expect(loaded.sourceSignature, 'daily_sig_001');
    expect(loaded.config, config);
    expect(loaded.points.length, 20);
  });

  test('saveAll should support concurrent batch write', () async {
    final config = MacdConfig.defaults;
    final updates = [
      MacdCacheSeries(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        config: config,
        sourceSignature: 'sig_a',
        points: _buildPoints(DateTime(2026, 1, 1), 12),
      ),
      MacdCacheSeries(
        stockCode: '600001',
        dataType: KLineDataType.weekly,
        config: config,
        sourceSignature: 'sig_b',
        points: _buildPoints(DateTime(2026, 1, 1), 10),
      ),
    ];

    await cacheStore.saveAll(updates, maxConcurrentWrites: 2);

    final loadedA = await cacheStore.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );
    final loadedB = await cacheStore.loadSeries(
      stockCode: '600001',
      dataType: KLineDataType.weekly,
    );

    expect(loadedA, isNotNull);
    expect(loadedB, isNotNull);
    expect(loadedA!.points.length, 12);
    expect(loadedB!.points.length, 10);
  });

  test('clearForStocks should clear both daily and weekly files', () async {
    final config = MacdConfig.defaults;

    await cacheStore.saveAll([
      MacdCacheSeries(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        config: config,
        sourceSignature: 'daily_sig',
        points: _buildPoints(DateTime(2026, 1, 1), 8),
      ),
      MacdCacheSeries(
        stockCode: '600000',
        dataType: KLineDataType.weekly,
        config: config,
        sourceSignature: 'weekly_sig',
        points: _buildPoints(DateTime(2026, 1, 1), 8),
      ),
    ]);

    await cacheStore.clearForStocks(const ['600000']);

    final daily = await cacheStore.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );
    final weekly = await cacheStore.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.weekly,
    );

    expect(daily, isNull);
    expect(weekly, isNull);
  });

  test(
    'listStockCodes should return existing codes for selected data type',
    () async {
      final config = MacdConfig.defaults;

      await cacheStore.saveAll([
        MacdCacheSeries(
          stockCode: '600000',
          dataType: KLineDataType.weekly,
          config: config,
          sourceSignature: 'w1',
          points: _buildPoints(DateTime(2026, 1, 1), 8),
        ),
        MacdCacheSeries(
          stockCode: '600001',
          dataType: KLineDataType.weekly,
          config: config,
          sourceSignature: 'w2',
          points: _buildPoints(DateTime(2026, 1, 1), 8),
        ),
        MacdCacheSeries(
          stockCode: '600002',
          dataType: KLineDataType.daily,
          config: config,
          sourceSignature: 'd1',
          points: _buildPoints(DateTime(2026, 1, 1), 8),
        ),
      ]);

      final weeklyCodes = await cacheStore.listStockCodes(
        dataType: KLineDataType.weekly,
      );
      final dailyCodes = await cacheStore.listStockCodes(
        dataType: KLineDataType.daily,
      );

      expect(weeklyCodes, containsAll(<String>['600000', '600001']));
      expect(weeklyCodes, isNot(contains('600002')));
      expect(dailyCodes, contains('600002'));
      expect(dailyCodes, isNot(contains('600000')));
    },
  );
}
