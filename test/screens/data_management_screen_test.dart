import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:stock_rtwatcher/screens/data_management_screen.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _FakeDataRepository implements DataRepository {
  final StreamController<DataStatus> _statusController =
      StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _updatedController =
      StreamController<DataUpdatedEvent>.broadcast();

  List<DateTime> tradingDates = <DateTime>[];
  Map<String, List<KLine>> klinesByStock = <String, List<KLine>>{};

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _updatedController.stream;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    return {
      for (final code in stockCodes)
        code: (klinesByStock[code] ?? <KLine>[]).where((bar) {
          return dateRange.contains(bar.datetime);
        }).toList(),
    };
  }

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    return {for (final code in stockCodes) code: const Fresh()};
  }

  @override
  Future<Map<String, Quote>> getQuotes({required List<String> stockCodes}) {
    throw UnimplementedError();
  }

  @override
  Future<int> getCurrentVersion() async => 1;

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
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
    return tradingDates;
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _updatedController.close();
  }
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

  @override
  Future<void> refresh({bool silent = false}) async {}
}

List<KLine> _buildBarsForDate(DateTime day, int count) {
  final start = DateTime(day.year, day.month, day.day, 9, 30);
  return List.generate(count, (index) {
    final dt = start.add(Duration(minutes: index));
    return KLine(
      datetime: dt,
      open: 10,
      close: 10.1,
      high: 10.2,
      low: 9.9,
      volume: 1000,
      amount: 10000,
    );
  });
}

List<StockMonitorData> _buildStocks(int count) {
  return List.generate(count, (index) {
    final code = (600000 + index).toString();
    return StockMonitorData(
      stock: Stock(code: code, name: '股票$code', market: 1),
      ratio: 1.0,
      changePercent: 0.0,
    );
  });
}

void main() {
  Future<void> pumpDataManagement(
    WidgetTester tester, {
    required DataRepository repository,
    required MarketDataProvider marketDataProvider,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DataRepository>.value(value: repository),
          ChangeNotifierProvider<MarketDataProvider>.value(
            value: marketDataProvider,
          ),
        ],
        child: const MaterialApp(home: DataManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('交易日覆盖率不足时显示最后交易日完整而非样本不足', (tester) async {
    final repository = _FakeDataRepository();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    final today = DateTime.now();
    final lastTradingDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    repository.tradingDates = <DateTime>[]; // 强制走覆盖率不足分支
    repository.klinesByStock = {
      '600000': _buildBarsForDate(lastTradingDay, 220),
    };

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
    );

    expect(find.textContaining('最后交易日'), findsOneWidget);
    expect(find.textContaining('数据完整'), findsOneWidget);
    expect(find.textContaining('交易日样本不足'), findsNothing);
    expect(find.text('拉取缺失'), findsNothing);

    provider.dispose();
    await repository.dispose();
  });

  testWidgets('交易日覆盖率不足且最后交易日不完整时仍提示拉取缺失', (tester) async {
    final repository = _FakeDataRepository();
    final provider = _FakeMarketDataProvider(
      data: [
        StockMonitorData(
          stock: Stock(code: '600000', name: '浦发银行', market: 1),
          ratio: 1.2,
          changePercent: 0.5,
        ),
      ],
    );

    final today = DateTime.now();
    final lastTradingDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));
    repository.tradingDates = <DateTime>[];
    repository.klinesByStock = {
      '600000': _buildBarsForDate(lastTradingDay, 120),
    };

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
    );

    expect(find.textContaining('最后交易日'), findsOneWidget);
    expect(find.textContaining('不完整'), findsOneWidget);
    expect(find.text('拉取缺失'), findsOneWidget);

    provider.dispose();
    await repository.dispose();
  });

  testWidgets('交易日覆盖率不足时抽样需覆盖全量避免误报完整', (tester) async {
    final repository = _FakeDataRepository();
    final provider = _FakeMarketDataProvider(data: _buildStocks(40));

    final today = DateTime.now();
    final lastTradingDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 1));

    repository.tradingDates = <DateTime>[];
    repository.klinesByStock = {
      for (var i = 0; i < 20; i++)
        (600000 + i).toString(): _buildBarsForDate(lastTradingDay, 220),
    };

    await pumpDataManagement(
      tester,
      repository: repository,
      marketDataProvider: provider,
    );

    expect(find.textContaining('交易日基线不足'), findsOneWidget);
    expect(find.textContaining('数据完整'), findsNothing);
    expect(find.textContaining('缺失20只'), findsOneWidget);
    expect(find.text('拉取缺失'), findsOneWidget);

    provider.dispose();
    await repository.dispose();
  });
}
