import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/ema_config.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late EmaCacheStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ema-cache-store-');
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    store = EmaCacheStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save and load series', () async {
    await store.saveSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: const EmaConfig(shortPeriod: 11, longPeriod: 22),
      sourceSignature: 'sig',
      points: [
        EmaPoint(datetime: DateTime(2026, 2, 19), emaShort: 10, emaLong: 11),
      ],
    );

    final loaded = await store.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );

    expect(loaded, isNotNull);
    expect(loaded!.points.length, 1);
    expect(loaded.config.shortPeriod, 11);
  });

  test('corrupt cache returns null', () async {
    await store.initialize();
    final path = await store.cacheFilePath('600000', KLineDataType.daily);
    await File(path).writeAsString('not json');

    final loaded = await store.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );

    expect(loaded, isNull);
  });
}
