import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/ema_settings_screen.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _StubDataRepository implements DataRepository {
  final _statusCtrl = StreamController<DataStatus>.broadcast();
  final _updatedCtrl = StreamController<DataUpdatedEvent>.broadcast();

  @override
  Stream<DataStatus> get statusStream => _statusCtrl.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _updatedCtrl.stream;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async => {};

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async => {};

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async => {};

  @override
  Future<int> getCurrentVersion() async => 0;

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async => _emptyFetchResult();

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async => _emptyFetchResult();

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) async {}

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) async => const MissingDatesResult(
    missingDates: [],
    incompleteDates: [],
    completeDates: [],
  );

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) async => {};

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async => [];

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) async => 0;

  @override
  Future<void> dispose() async {
    await _statusCtrl.close();
    await _updatedCtrl.close();
  }

  FetchResult _emptyFetchResult() => FetchResult(
    totalStocks: 0,
    successCount: 0,
    failureCount: 0,
    errors: const {},
    totalRecords: 0,
    duration: Duration.zero,
  );
}

class _FakeMarketDataProvider extends MarketDataProvider {
  final List<StockMonitorData> _testData;

  _FakeMarketDataProvider({required List<StockMonitorData> data})
    : _testData = data,
      super(
        pool: TdxPool(poolSize: 1),
        stockService: StockService(TdxPool(poolSize: 1)),
        industryService: IndustryService(),
      );

  @override
  List<StockMonitorData> get allData => _testData;
}

class _FakeEmaCacheStore extends EmaCacheStore {
  final int _count;
  final DateTime? _latest;

  _FakeEmaCacheStore({required int count, DateTime? latestUpdatedAt})
    : _count = count,
      _latest = latestUpdatedAt;

  @override
  Future<int> countSeries(KLineDataType dataType) async => _count;

  @override
  Future<DateTime?> latestUpdatedAt(KLineDataType dataType) async => _latest;
}

Future<void> _pumpEmaSettings(
  WidgetTester tester, {
  required KLineDataType dataType,
  required EmaCacheStore cacheStore,
  List<StockMonitorData> stocks = const [],
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final repository = _StubDataRepository();
  final emaService = EmaIndicatorService(repository: repository);
  await emaService.load();
  final provider = _FakeMarketDataProvider(data: stocks);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MarketDataProvider>.value(value: provider),
        ChangeNotifierProvider<EmaIndicatorService>.value(value: emaService),
      ],
      child: MaterialApp(
        home: EmaSettingsScreen(
          dataType: dataType,
          emaCacheStoreForTest: cacheStore,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('EmaSettingsScreen cache stats', () {
    testWidgets('shows 缓存 section with count when cache has entries', (
      tester,
    ) async {
      final cacheStore = _FakeEmaCacheStore(
        count: 42,
        latestUpdatedAt: DateTime(2026, 2, 10, 14, 30),
      );

      await _pumpEmaSettings(
        tester,
        dataType: KLineDataType.daily,
        cacheStore: cacheStore,
        stocks: [
          StockMonitorData(
            stock: Stock(code: '600000', name: '浦发银行', market: 1),
            ratio: 1.0,
            changePercent: 0.0,
          ),
        ],
      );

      expect(find.textContaining('缓存'), findsWidgets);
      expect(find.textContaining('42'), findsOneWidget);
    });

    testWidgets('shows -- for latest update when no cache entries', (
      tester,
    ) async {
      final cacheStore = _FakeEmaCacheStore(count: 0, latestUpdatedAt: null);

      await _pumpEmaSettings(
        tester,
        dataType: KLineDataType.daily,
        cacheStore: cacheStore,
      );

      expect(find.textContaining('缓存'), findsWidgets);
      expect(find.textContaining('--'), findsWidgets);
    });
  });
}
