import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/models/power_system_point.dart';

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late PowerSystemCacheStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'power-system-cache-store-',
    );
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    store = PowerSystemCacheStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('save/load power system cache series for daily and weekly', () async {
    final dailyPoints = <PowerSystemPoint>[
      PowerSystemPoint(datetime: DateTime(2026, 2, 17), state: 1),
      PowerSystemPoint(datetime: DateTime(2026, 2, 18), state: -1),
      PowerSystemPoint(datetime: DateTime(2026, 2, 19), state: 0),
    ];
    final weeklyPoints = <PowerSystemPoint>[
      PowerSystemPoint(datetime: DateTime(2026, 1, 30), state: 1),
      PowerSystemPoint(datetime: DateTime(2026, 2, 6), state: 0),
    ];

    await store.saveSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      sourceSignature: 'daily_sig',
      points: dailyPoints,
    );
    await store.saveSeries(
      stockCode: '600000',
      dataType: KLineDataType.weekly,
      sourceSignature: 'weekly_sig',
      points: weeklyPoints,
    );

    final dailyLoaded = await store.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );
    final weeklyLoaded = await store.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.weekly,
    );

    expect(dailyLoaded, isNotNull);
    expect(dailyLoaded!.sourceSignature, 'daily_sig');
    expect(dailyLoaded.points.length, 3);
    expect(dailyLoaded.points[0].datetime, DateTime(2026, 2, 17));
    expect(dailyLoaded.points[0].state, 1);
    expect(dailyLoaded.points[1].state, -1);
    expect(dailyLoaded.points[2].state, 0);

    expect(weeklyLoaded, isNotNull);
    expect(weeklyLoaded!.sourceSignature, 'weekly_sig');
    expect(weeklyLoaded.points.length, 2);
    expect(weeklyLoaded.points[0].datetime, DateTime(2026, 1, 30));
    expect(weeklyLoaded.points[0].state, 1);
    expect(weeklyLoaded.points[1].datetime, DateTime(2026, 2, 6));
    expect(weeklyLoaded.points[1].state, 0);
  });

  test('clearForStocks clears both daily and weekly cache files', () async {
    await store.saveSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      sourceSignature: 'daily_sig',
      points: [PowerSystemPoint(datetime: DateTime(2026, 2, 19), state: 1)],
    );
    await store.saveSeries(
      stockCode: '600000',
      dataType: KLineDataType.weekly,
      sourceSignature: 'weekly_sig',
      points: [PowerSystemPoint(datetime: DateTime(2026, 2, 14), state: -1)],
    );

    await store.clearForStocks(const ['600000']);

    final dailyLoaded = await store.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );
    final weeklyLoaded = await store.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.weekly,
    );

    expect(dailyLoaded, isNull);
    expect(weeklyLoaded, isNull);
  });
}
