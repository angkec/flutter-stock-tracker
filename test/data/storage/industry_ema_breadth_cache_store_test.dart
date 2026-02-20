import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late IndustryEmaBreadthCacheStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'industry-ema-breadth-cache-store-',
    );
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    store = IndustryEmaBreadthCacheStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save and load series by industry', () async {
    final series = IndustryEmaBreadthSeries(
      industry: 'bank',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 20),
          percent: 73.5,
          aboveCount: 10,
          validCount: 14,
          missingCount: 2,
        ),
      ],
    );

    await store.saveSeries(series);
    final loaded = await store.loadSeries('bank');

    expect(loaded, isNotNull);
    expect(loaded, equals(series));
  });

  test('saveAll persists multiple industries', () async {
    final bank = IndustryEmaBreadthSeries(
      industry: 'bank',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 20),
          percent: 80,
          aboveCount: 8,
          validCount: 10,
          missingCount: 0,
        ),
      ],
    );
    final broker = IndustryEmaBreadthSeries(
      industry: 'broker',
      points: [
        IndustryEmaBreadthPoint(
          date: DateTime(2026, 2, 20),
          percent: 45,
          aboveCount: 9,
          validCount: 20,
          missingCount: 3,
        ),
      ],
    );

    await store.saveAll([bank, broker]);

    expect(await store.loadSeries('bank'), equals(bank));
    expect(await store.loadSeries('broker'), equals(broker));
  });

  test('corrupt cache returns null', () async {
    await store.initialize();
    final path = await store.cacheFilePath('bank');
    await File(path).writeAsString('not json');

    final loaded = await store.loadSeries('bank');
    expect(loaded, isNull);
  });
}
