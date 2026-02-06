import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/database_schema.dart';
import 'package:stock_rtwatcher/data/storage/industry_buildup_storage.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

class MockBuildUpRepository implements DataRepository {
  final _statusController = StreamController<DataStatus>.broadcast();
  final _updatedController = StreamController<DataUpdatedEvent>.broadcast();

  final Map<String, List<KLine>> _bars = {};
  List<DateTime> tradingDates = [];
  int _version = 1;

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _updatedController.stream;

  void setStockBars(String code, List<KLine> bars) {
    _bars[code] = bars;
  }

  void emitDataUpdated(List<String> stockCodes) {
    _version++;
    _updatedController.add(
      DataUpdatedEvent(
        stockCodes: stockCodes,
        dateRange: DateRange(
          DateTime.now().subtract(const Duration(days: 30)),
          DateTime.now(),
        ),
        dataType: KLineDataType.oneMinute,
        dataVersion: _version,
      ),
    );
  }

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final result = <String, List<KLine>>{};
    for (final code in stockCodes) {
      final bars = _bars[code] ?? [];
      result[code] = bars.where((k) => dateRange.contains(k.datetime)).toList();
    }
    return result;
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
    return tradingDates.where((d) => dateRange.contains(d)).toList()..sort();
  }

  @override
  Future<int> getCurrentVersion() async => _version;

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    return {for (final code in stockCodes) code: const Fresh()};
  }

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async {
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
      errors: {},
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
      errors: {},
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
      missingDates: [],
      incompleteDates: [],
      completeDates: [],
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
  Future<int> clearFreshnessCache({KLineDataType? dataType}) async => 0;

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _updatedController.close();
  }
}

List<KLine> _buildBarsForDay(DateTime date, {required double trend}) {
  final bars = <KLine>[];
  var lastClose = 10.0;
  for (var i = 0; i < 240; i++) {
    final open = lastClose;
    final close = open * (1 + trend);
    bars.add(
      KLine(
        datetime: DateTime(
          date.year,
          date.month,
          date.day,
          9,
          30,
        ).add(Duration(minutes: i)),
        open: open,
        close: close,
        high: open > close ? open : close,
        low: open < close ? open : close,
        volume: 1000,
        amount: 100000,
      ),
    );
    lastClose = close;
  }
  return bars;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    final db = MarketDatabase();
    try {
      await db.close();
    } catch (_) {}

    MarketDatabase.resetInstance();

    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/${DatabaseSchema.databaseName}';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  group('IndustryBuildUpService', () {
    late MockBuildUpRepository repository;
    late IndustryService industryService;
    late IndustryBuildUpStorage storage;
    late IndustryBuildUpService service;

    setUp(() async {
      repository = MockBuildUpRepository();
      industryService = IndustryService();
      industryService.setTestData({
        '000001': '半导体',
        '000002': '半导体',
        '000003': '军工',
      });

      storage = IndustryBuildUpStorage();
      service = IndustryBuildUpService(
        repository: repository,
        industryService: industryService,
        storage: storage,
      );

      final day1 = DateTime(2026, 2, 4);
      final day2 = DateTime(2026, 2, 5);
      final day3 = DateTime(2026, 2, 6);
      repository.tradingDates = [day1, day2, day3];

      repository.setStockBars('000001', [
        ..._buildBarsForDay(day1, trend: 0.0010),
        ..._buildBarsForDay(day2, trend: 0.0010),
        ..._buildBarsForDay(day3, trend: 0.0012),
      ]);
      repository.setStockBars('000002', [
        ..._buildBarsForDay(day1, trend: 0.0008),
        ..._buildBarsForDay(day2, trend: 0.0010),
        ..._buildBarsForDay(day3, trend: 0.0011),
      ]);
      repository.setStockBars('000003', [
        ..._buildBarsForDay(day1, trend: -0.0005),
        ..._buildBarsForDay(day2, trend: -0.0004),
        ..._buildBarsForDay(day3, trend: -0.0002),
      ]);
    });

    test(
      'recalculate generates latest board and writes sqlite records',
      () async {
        await service.recalculate(force: true);

        final board = service.latestBoard;
        expect(board, isNotEmpty);
        expect(board.first.record.rank, 1);
        expect(service.latestResultDate, isNotNull);

        final persisted = await storage.getLatestBoard(limit: 10);
        expect(persisted, isNotEmpty);
        expect(persisted.first.rank, 1);
      },
    );

    test('recalculate publishes stage progress snapshots', () async {
      final snapshots = <String>[];
      service.addListener(() {
        snapshots.add(
          '${service.stageLabel} ${service.progressCurrent}/${service.progressTotal}',
        );
      });

      await service.recalculate(force: true);

      expect(snapshots.any((s) => s.startsWith('预处理')), isTrue);
      expect(snapshots.any((s) => s.startsWith('行业聚合')), isTrue);
      expect(snapshots.any((s) => s.startsWith('写入结果')), isTrue);
      expect(service.isCalculating, isFalse);
    });

    test(
      'dataUpdated event marks service stale without auto recompute',
      () async {
        await service.recalculate(force: true);
        final previousComputedAt = service.lastComputedAt;

        repository.emitDataUpdated(['000001']);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(service.isStale, isTrue);
        expect(service.lastComputedAt, previousComputedAt);
        expect(service.latestBoard, isNotEmpty);
      },
    );
  });
}
