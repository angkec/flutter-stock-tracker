import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/power_system_indicator_service.dart';

class _FakeRepository extends DataRepository {
  _FakeRepository(this.barsByCode);

  final Map<String, List<KLine>> barsByCode;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    return {
      for (final code in stockCodes) code: barsByCode[code] ?? const <KLine>[],
    };
  }

  @override
  Future<int> getCurrentVersion() async => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEmaService extends EmaIndicatorService {
  _FakeEmaService({required super.repository}) : super();

  final Map<String, List<EmaPoint>> responseByKey = <String, List<EmaPoint>>{};

  @override
  Future<List<EmaPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
    bool persistToDisk = true,
    void Function(EmaCacheSeries series)? onSeriesComputed,
  }) async {
    return responseByKey['$stockCode|${dataType.name}'] ?? const <EmaPoint>[];
  }
}

class _FakeMacdService extends MacdIndicatorService {
  _FakeMacdService({required super.repository}) : super();

  final Map<String, List<MacdPoint>> responseByKey =
      <String, List<MacdPoint>>{};

  @override
  Future<List<MacdPoint>> getOrComputeFromBars({
    required String stockCode,
    required KLineDataType dataType,
    required List<KLine> bars,
    bool forceRecompute = false,
    bool persistToDisk = true,
    void Function(MacdCacheSeries series)? onSeriesComputed,
  }) async {
    return responseByKey['$stockCode|${dataType.name}'] ?? const <MacdPoint>[];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<KLine> bars() {
    return <KLine>[
      KLine(
        datetime: DateTime(2026, 2, 17),
        open: 10,
        close: 10.5,
        high: 10.8,
        low: 9.9,
        volume: 100,
        amount: 1000,
      ),
      KLine(
        datetime: DateTime(2026, 2, 18),
        open: 10.5,
        close: 11,
        high: 11.1,
        low: 10.2,
        volume: 110,
        amount: 1100,
      ),
      KLine(
        datetime: DateTime(2026, 2, 19),
        open: 11,
        close: 11.2,
        high: 11.4,
        low: 10.8,
        volume: 120,
        amount: 1200,
      ),
    ];
  }

  test('computes red when ema slope up and macd slope up', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'power-system-service-red-',
    );
    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final cacheStore = PowerSystemCacheStore(storage: storage);
    final repository = _FakeRepository({});
    final emaService = _FakeEmaService(repository: repository)
      ..responseByKey['600000|daily'] = <EmaPoint>[
        EmaPoint(datetime: DateTime(2026, 2, 17), emaShort: 10, emaLong: 9),
        EmaPoint(datetime: DateTime(2026, 2, 18), emaShort: 10.4, emaLong: 9.4),
        EmaPoint(datetime: DateTime(2026, 2, 19), emaShort: 10.9, emaLong: 9.9),
      ];
    final macdService = _FakeMacdService(repository: repository)
      ..responseByKey['600000|daily'] = <MacdPoint>[
        MacdPoint(
          datetime: DateTime(2026, 2, 17),
          dif: 0.1,
          dea: 0.0,
          hist: 0.2,
        ),
        MacdPoint(
          datetime: DateTime(2026, 2, 18),
          dif: 0.2,
          dea: 0.1,
          hist: 0.3,
        ),
        MacdPoint(
          datetime: DateTime(2026, 2, 19),
          dif: 0.3,
          dea: 0.2,
          hist: 0.4,
        ),
      ];

    final service = PowerSystemIndicatorService(
      repository: repository,
      emaService: emaService,
      macdService: macdService,
      cacheStore: cacheStore,
    );

    final points = await service.getOrComputeFromBars(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      bars: bars(),
      forceRecompute: true,
    );

    expect(points.last.state, 1);
    await tempDir.delete(recursive: true);
  });

  test('computes green when ema slope down and macd slope down', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'power-system-service-green-',
    );
    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final cacheStore = PowerSystemCacheStore(storage: storage);
    final repository = _FakeRepository({});
    final emaService = _FakeEmaService(repository: repository)
      ..responseByKey['600000|daily'] = <EmaPoint>[
        EmaPoint(datetime: DateTime(2026, 2, 17), emaShort: 10.9, emaLong: 9),
        EmaPoint(datetime: DateTime(2026, 2, 18), emaShort: 10.4, emaLong: 9.4),
        EmaPoint(datetime: DateTime(2026, 2, 19), emaShort: 10, emaLong: 9.9),
      ];
    final macdService = _FakeMacdService(repository: repository)
      ..responseByKey['600000|daily'] = <MacdPoint>[
        MacdPoint(
          datetime: DateTime(2026, 2, 17),
          dif: 0.3,
          dea: 0.0,
          hist: 0.4,
        ),
        MacdPoint(
          datetime: DateTime(2026, 2, 18),
          dif: 0.2,
          dea: 0.1,
          hist: 0.3,
        ),
        MacdPoint(
          datetime: DateTime(2026, 2, 19),
          dif: 0.1,
          dea: 0.2,
          hist: 0.2,
        ),
      ];

    final service = PowerSystemIndicatorService(
      repository: repository,
      emaService: emaService,
      macdService: macdService,
      cacheStore: cacheStore,
    );

    final points = await service.getOrComputeFromBars(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      bars: bars(),
      forceRecompute: true,
    );

    expect(points.last.state, -1);
    await tempDir.delete(recursive: true);
  });

  test('computes blue when slopes diverge', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'power-system-service-blue-',
    );
    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final cacheStore = PowerSystemCacheStore(storage: storage);
    final repository = _FakeRepository({});
    final emaService = _FakeEmaService(repository: repository)
      ..responseByKey['600000|daily'] = <EmaPoint>[
        EmaPoint(datetime: DateTime(2026, 2, 17), emaShort: 10, emaLong: 9),
        EmaPoint(datetime: DateTime(2026, 2, 18), emaShort: 10.3, emaLong: 9.4),
        EmaPoint(datetime: DateTime(2026, 2, 19), emaShort: 10.8, emaLong: 9.9),
      ];
    final macdService = _FakeMacdService(repository: repository)
      ..responseByKey['600000|daily'] = <MacdPoint>[
        MacdPoint(
          datetime: DateTime(2026, 2, 17),
          dif: 0.3,
          dea: 0.0,
          hist: 0.4,
        ),
        MacdPoint(
          datetime: DateTime(2026, 2, 18),
          dif: 0.2,
          dea: 0.1,
          hist: 0.3,
        ),
        MacdPoint(
          datetime: DateTime(2026, 2, 19),
          dif: 0.1,
          dea: 0.2,
          hist: 0.2,
        ),
      ];

    final service = PowerSystemIndicatorService(
      repository: repository,
      emaService: emaService,
      macdService: macdService,
      cacheStore: cacheStore,
    );

    final points = await service.getOrComputeFromBars(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      bars: bars(),
      forceRecompute: true,
    );

    expect(points.last.state, 0);
    await tempDir.delete(recursive: true);
  });

  test(
    'prewarmFromRepository writes cache for stock scope and data type',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'power-system-service-',
      );
      final storage = KLineFileStorage();
      storage.setBaseDirPathForTesting(tempDir.path);
      final cacheStore = PowerSystemCacheStore(storage: storage);
      final repoBars = <String, List<KLine>>{
        '600000': bars(),
        '600001': bars(),
      };
      final repository = _FakeRepository(repoBars);
      final emaService = _FakeEmaService(repository: repository)
        ..responseByKey['600000|weekly'] = <EmaPoint>[
          EmaPoint(datetime: DateTime(2026, 2, 17), emaShort: 1, emaLong: 0),
          EmaPoint(datetime: DateTime(2026, 2, 18), emaShort: 2, emaLong: 0),
          EmaPoint(datetime: DateTime(2026, 2, 19), emaShort: 3, emaLong: 0),
        ]
        ..responseByKey['600001|weekly'] = <EmaPoint>[
          EmaPoint(datetime: DateTime(2026, 2, 17), emaShort: 3, emaLong: 0),
          EmaPoint(datetime: DateTime(2026, 2, 18), emaShort: 2, emaLong: 0),
          EmaPoint(datetime: DateTime(2026, 2, 19), emaShort: 1, emaLong: 0),
        ];
      final macdService = _FakeMacdService(repository: repository)
        ..responseByKey['600000|weekly'] = <MacdPoint>[
          MacdPoint(datetime: DateTime(2026, 2, 17), dif: 0, dea: 0, hist: 0.1),
          MacdPoint(datetime: DateTime(2026, 2, 18), dif: 0, dea: 0, hist: 0.2),
          MacdPoint(datetime: DateTime(2026, 2, 19), dif: 0, dea: 0, hist: 0.3),
        ]
        ..responseByKey['600001|weekly'] = <MacdPoint>[
          MacdPoint(datetime: DateTime(2026, 2, 17), dif: 0, dea: 0, hist: 0.3),
          MacdPoint(datetime: DateTime(2026, 2, 18), dif: 0, dea: 0, hist: 0.2),
          MacdPoint(datetime: DateTime(2026, 2, 19), dif: 0, dea: 0, hist: 0.1),
        ];

      final service = PowerSystemIndicatorService(
        repository: repository,
        emaService: emaService,
        macdService: macdService,
        cacheStore: cacheStore,
      );

      await service.prewarmFromRepository(
        stockCodes: const <String>['600000', '600001'],
        dataType: KLineDataType.weekly,
        dateRange: DateRange(DateTime(2026, 1, 1), DateTime(2026, 2, 20)),
      );

      final first = await cacheStore.loadSeries(
        stockCode: '600000',
        dataType: KLineDataType.weekly,
      );
      final second = await cacheStore.loadSeries(
        stockCode: '600001',
        dataType: KLineDataType.weekly,
      );
      expect(first, isNotNull);
      expect(second, isNotNull);

      await tempDir.delete(recursive: true);
    },
  );
}
