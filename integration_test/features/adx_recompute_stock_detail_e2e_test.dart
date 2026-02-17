import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/adx_settings_screen.dart';
import 'package:stock_rtwatcher/screens/stock_detail_screen.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _FakeDataRepository implements DataRepository {
  int currentVersion = 1;
  Map<KLineDataType, Map<String, List<KLine>>> barsByType =
      <KLineDataType, Map<String, List<KLine>>>{};

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final source = barsByType[dataType] ?? const <String, List<KLine>>{};
    return <String, List<KLine>>{
      for (final code in stockCodes)
        code: (source[code] ?? const <KLine>[])
            .where((bar) => dateRange.contains(bar.datetime))
            .toList(growable: false),
    };
  }

  @override
  Future<int> getCurrentVersion() async => currentVersion;

  @override
  Stream<DataStatus> get statusStream => const Stream.empty();

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => const Stream.empty();

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Quote>> getQuotes({required List<String> stockCodes}) {
    throw UnimplementedError();
  }

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) {
    throw UnimplementedError();
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}
}

class _FakeMarketDataProvider extends MarketDataProvider {
  _FakeMarketDataProvider(this._allData)
    : super(
        pool: TdxPool(poolSize: 1),
        stockService: StockService(TdxPool(poolSize: 1)),
        industryService: IndustryService(),
        dailyBarsFileStorage: DailyKlineCacheStore(
          storage: KLineFileStorage(),
        ),
      );

  final List<StockMonitorData> _allData;

  @override
  List<StockMonitorData> get allData => _allData;

  @override
  bool get isLoading => false;
}

List<KLine> _buildDailyBars({required int count, required DateTime start}) {
  return List<KLine>.generate(count, (index) {
    final date = start.add(Duration(days: index));
    final base = 10 + index * 0.05;
    return KLine(
      datetime: date,
      open: base - 0.1,
      close: base + ((index % 5) - 2) * 0.08,
      high: base + 0.3 + (index % 3) * 0.02,
      low: base - 0.3 - (index % 2) * 0.02,
      volume: 1000 + index.toDouble(),
      amount: 10000 + index.toDouble(),
    );
  });
}

List<KLine> _buildWeeklyBars({required int count, required DateTime start}) {
  return List<KLine>.generate(count, (index) {
    final date = start.add(Duration(days: index * 7));
    final base = 10 + index * 0.08;
    return KLine(
      datetime: date,
      open: base - 0.2,
      close: base + ((index % 5) - 2) * 0.15,
      high: base + 0.45 + (index % 3) * 0.03,
      low: base - 0.45 - (index % 2) * 0.03,
      volume: 5000 + index.toDouble(),
      amount: 50000 + index.toDouble(),
    );
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'recomputing daily/weekly ADX should make stock detail render ADX cache',
    (tester) async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});

      final tempDir = await Directory.systemTemp.createTemp(
        'adx-recompute-stock-detail-e2e-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final fileStorage = KLineFileStorage();
      fileStorage.setBaseDirPathForTesting(tempDir.path);
      final adxCacheStore = AdxCacheStore(storage: fileStorage);
      final repository = _FakeDataRepository();
      const stockCode = '600000';
      final dailyBars = _buildDailyBars(
        count: 260,
        start: DateTime.now().subtract(const Duration(days: 320)),
      );
      final weeklyBars = _buildWeeklyBars(
        count: 120,
        start: DateTime.now().subtract(const Duration(days: 900)),
      );

      final adxService = AdxIndicatorService(
        repository: repository,
        cacheStore: adxCacheStore,
      );
      await adxService.load();

      // 先制造“snapshot命中但缓存缺失”状态：同版本同scope预热一次，但bars为空，不写入缓存文件。
      repository.barsByType = <KLineDataType, Map<String, List<KLine>>>{
        KLineDataType.daily: <String, List<KLine>>{
          stockCode: const <KLine>[],
        },
        KLineDataType.weekly: <String, List<KLine>>{
          stockCode: const <KLine>[],
        },
      };
      await adxService.prewarmFromRepository(
        stockCodes: const <String>[stockCode],
        dataType: KLineDataType.daily,
        dateRange: DateRange(
          DateTime.now().subtract(const Duration(days: 400)),
          DateTime.now(),
        ),
      );
      await adxService.prewarmFromRepository(
        stockCodes: const <String>[stockCode],
        dataType: KLineDataType.weekly,
        dateRange: DateRange(
          DateTime.now().subtract(const Duration(days: 760)),
          DateTime.now(),
        ),
      );

      repository.barsByType = <KLineDataType, Map<String, List<KLine>>>{
        KLineDataType.daily: <String, List<KLine>>{stockCode: dailyBars},
        KLineDataType.weekly: <String, List<KLine>>{stockCode: weeklyBars},
      };

      final marketProvider = _FakeMarketDataProvider(<StockMonitorData>[
        StockMonitorData(
          stock: Stock(code: stockCode, name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.8,
        ),
      ]);

      Future<void> runRecompute(KLineDataType dataType) async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<MarketDataProvider>.value(
                value: marketProvider,
              ),
              ChangeNotifierProvider<AdxIndicatorService>.value(
                value: adxService,
              ),
            ],
            child: MaterialApp(home: AdxSettingsScreen(dataType: dataType)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ValueKey('adx_recompute_${dataType.name}')));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.textContaining('ADX重算完成'), findsOneWidget);
      }

      await runRecompute(KLineDataType.daily);
      await runRecompute(KLineDataType.weekly);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MarketDataProvider>.value(
              value: marketProvider,
            ),
          ],
          child: MaterialApp(
            home: StockDetailScreen(
              stock: Stock(code: stockCode, name: '浦发银行', market: 1),
              skipAutoConnectForTest: true,
              showWatchlistToggle: false,
              showIndustryHeatSection: false,
              initialChartMode: ChartMode.daily,
              initialDailyBars: dailyBars,
              initialWeeklyBars: weeklyBars,
              adxCacheStoreForTest: adxCacheStore,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('暂无ADX缓存，请先在数据管理同步'), findsNothing);
      expect(
        find.byKey(const ValueKey('stock_detail_adx_paint_daily')),
        findsOneWidget,
      );

      await tester.tap(find.text('周线'));
      await tester.pumpAndSettle();
      expect(find.text('暂无ADX缓存，请先在数据管理同步'), findsNothing);
      expect(
        find.byKey(const ValueKey('stock_detail_adx_paint_weekly')),
        findsOneWidget,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
