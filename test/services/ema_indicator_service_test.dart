import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/ema_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';

class _FakeRepo extends DataRepository {
  _FakeRepo(this.barsByCode);
  final Map<String, List<KLine>> barsByCode;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required dateRange,
    required dataType,
  }) async {
    return {
      for (final code in stockCodes) code: barsByCode[code] ?? const <KLine>[]
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('prewarm writes cache for daily', () async {
    final tempDir = await Directory.systemTemp.createTemp('ema-service-');
    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final cacheStore = EmaCacheStore(storage: storage);
    final bars = [
      KLine(
        datetime: DateTime(2026, 2, 18),
        open: 10,
        close: 11,
        high: 12,
        low: 9,
        volume: 100,
        amount: 1000,
      ),
      KLine(
        datetime: DateTime(2026, 2, 19),
        open: 11,
        close: 12,
        high: 13,
        low: 10,
        volume: 120,
        amount: 1100,
      ),
    ];

    final repo = _FakeRepo({'600000': bars});
    final service = EmaIndicatorService(repository: repo, cacheStore: cacheStore);
    await service.load();

    await service.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: {'600000': bars},
    );

    final loaded = await cacheStore.loadSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
    );
    expect(loaded, isNotNull);
    expect(loaded!.points.length, 2);

    await tempDir.delete(recursive: true);
  });

  test('config signature changes when periods change', () async {
    final service = EmaIndicatorService(repository: _FakeRepo({}));
    await service.load();
    final daily = service.configFor(KLineDataType.daily);
    final changed = daily.copyWith(shortPeriod: daily.shortPeriod + 1);
    expect(service.buildConfigSignature(daily), isNot(service.buildConfigSignature(changed)));
  });
}
