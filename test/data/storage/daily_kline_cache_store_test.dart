import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

List<KLine> _buildDailyBars(DateTime start, int count) {
  return List.generate(count, (index) {
    final dt = DateTime(start.year, start.month, start.day + index);
    return KLine(
      datetime: dt,
      open: 10,
      close: 10.1 + index,
      high: 10.2 + index,
      low: 9.9,
      volume: 1000.0 + index,
      amount: 10000.0 + index,
    );
  });
}

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late DailyKlineCacheStore cacheStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('daily-kline-cache-store-');
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    cacheStore = DailyKlineCacheStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'saveAll + loadForStocks should persist and restore latest bars',
    () async {
      final bars = _buildDailyBars(DateTime(2026, 1, 20), 40);

      await cacheStore.saveAll({'600000': bars});

      final loaded = await cacheStore.loadForStocks(
        const ['600000'],
        anchorDate: DateTime(2026, 2, 28),
        targetBars: 30,
      );

      expect(loaded.containsKey('600000'), isTrue);
      expect(loaded['600000']!.length, 30);
      expect(loaded['600000']!.first.datetime, DateTime(2026, 1, 30));
      expect(loaded['600000']!.last.datetime, DateTime(2026, 2, 28));
    },
  );

  test('clearForStocks should remove persisted monthly files', () async {
    final bars = _buildDailyBars(DateTime(2026, 1, 1), 10);
    await cacheStore.saveAll({'600000': bars});

    await cacheStore.clearForStocks(
      const ['600000'],
      anchorDate: DateTime(2026, 2, 1),
      lookbackMonths: 3,
    );

    final loaded = await cacheStore.loadForStocks(
      const ['600000'],
      anchorDate: DateTime(2026, 2, 1),
      targetBars: 30,
    );
    expect(loaded, isEmpty);
  });

  test('saveAll should support configurable write concurrency', () async {
    final concurrentStore = DailyKlineCacheStore(
      storage: storage,
      defaultMaxConcurrentWrites: 4,
    );
    final bars = _buildDailyBars(DateTime(2026, 1, 1), 32);
    await concurrentStore.saveAll({
      '600000': bars,
      '600001': bars,
      '600002': bars,
      '600003': bars,
    });

    final loaded = await concurrentStore.loadForStocks(
      const ['600000', '600001', '600002', '600003'],
      anchorDate: DateTime(2026, 2, 1),
      targetBars: 32,
    );

    expect(loaded.length, 4);
    expect(loaded.values.every((value) => value.length == 32), isTrue);
  });

  test(
    'getSnapshotStats should return persisted file count and bytes',
    () async {
      final bars = _buildDailyBars(DateTime(2026, 1, 1), 32);
      await cacheStore.saveAll({'600000': bars, '600001': bars});

      final stats = await cacheStore.getSnapshotStats();

      expect(stats.stockCount, 2);
      expect(stats.totalBytes, greaterThan(0));
    },
  );
}
