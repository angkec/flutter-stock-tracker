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
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/power_system_settings_screen.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/power_system_indicator_service.dart';
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
  _FakeMarketDataProvider({required List<StockMonitorData> data})
    : _data = data,
      super(
        pool: TdxPool(poolSize: 1),
        stockService: StockService(TdxPool(poolSize: 1)),
        industryService: IndustryService(),
      );

  final List<StockMonitorData> _data;

  @override
  List<StockMonitorData> get allData => _data;
}

class _FakePowerSystemIndicatorService extends PowerSystemIndicatorService {
  _FakePowerSystemIndicatorService({
    required super.repository,
    required super.emaService,
    required super.macdService,
  });

  int prewarmCount = 0;

  @override
  Future<void> prewarmFromRepository({
    required List<String> stockCodes,
    required KLineDataType dataType,
    required DateRange dateRange,
    bool forceRecompute = false,
    bool ignoreSnapshot = false,
    int? fetchBatchSize,
    int? maxConcurrentPersistWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    prewarmCount++;
    onProgress?.call(stockCodes.length, stockCodes.length);
  }
}

void main() {
  testWidgets('power system recompute button calls prewarmFromRepository', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final repository = _StubDataRepository();
    final ema = EmaIndicatorService(repository: repository);
    final macd = MacdIndicatorService(repository: repository);
    final powerSystem = _FakePowerSystemIndicatorService(
      repository: repository,
      emaService: ema,
      macdService: macd,
    );
    final provider = _FakeMarketDataProvider(
      data: <StockMonitorData>[
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1,
          changePercent: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MarketDataProvider>.value(value: provider),
          ChangeNotifierProvider<PowerSystemIndicatorService>.value(
            value: powerSystem,
          ),
        ],
        child: const MaterialApp(
          home: PowerSystemSettingsScreen(dataType: KLineDataType.daily),
        ),
      ),
    );
    await tester.pump();

    final recomputeButton = find.byKey(
      const ValueKey('power_system_recompute_daily'),
    );
    expect(recomputeButton, findsOneWidget);
    await tester.tap(recomputeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(powerSystem.prewarmCount, 1);

    provider.dispose();
    powerSystem.dispose();
    ema.dispose();
    macd.dispose();
  });
}
