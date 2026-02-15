import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

class _ReconnectableFakePool extends TdxPool {
  _ReconnectableFakePool({
    required this.dailyBarsByCode,
    this.throwOnBatchFetch = false,
  }) : super(poolSize: 1);

  final Map<String, List<KLine>> dailyBarsByCode;
  final bool throwOnBatchFetch;

  int ensureConnectedCalls = 0;
  int batchFetchCalls = 0;
  bool connected = false;

  @override
  Future<bool> ensureConnected() async {
    ensureConnectedCalls++;
    connected = true;
    return true;
  }

  @override
  Future<void> batchGetSecurityBarsStreaming({
    required List<Stock> stocks,
    required int category,
    required int start,
    required int count,
    required void Function(int stockIndex, List<KLine> bars) onStockBars,
  }) async {
    batchFetchCalls++;
    if (!connected) {
      throw StateError('Not connected');
    }
    if (throwOnBatchFetch) {
      throw StateError('Unexpected network fetch');
    }

    for (var index = 0; index < stocks.length; index++) {
      final stock = stocks[index];
      onStockBars(index, dailyBarsByCode[stock.code] ?? const <KLine>[]);
    }
  }
}

DailyKlineCacheStore _buildStorageForPath(String basePath) {
  final storage = KLineFileStorage();
  storage.setBaseDirPathForTesting(basePath);
  return DailyKlineCacheStore(storage: storage);
}

List<KLine> _buildDailyBars(int n) {
  final start = DateTime(2026, 1, 1);
  return List.generate(n, (index) {
    final dt = start.add(Duration(days: index));
    return KLine(
      datetime: dt,
      open: 10,
      close: 10.2,
      high: 10.3,
      low: 9.9,
      volume: 1000.0 + index,
      amount: 10000.0 + index,
    );
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyKline Storage E2E', () {
    test('daily cache metrics stay non-zero on second open', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-kline-storage-e2e-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final tradingDay = DateTime(2026, 2, 15);
      final stock = Stock(code: '600000', name: '浦发银行', market: 1);
      final monitorData = StockMonitorData(
        stock: stock,
        ratio: 1.2,
        changePercent: 0.5,
      );

      SharedPreferences.setMockInitialValues({
        'market_data_cache': jsonEncode([monitorData.toJson()]),
        'market_data_date': tradingDay.toIso8601String(),
        'minute_data_date': tradingDay.toIso8601String(),
        'minute_data_cache_v1': 1,
      });

      final storage1 = _buildStorageForPath(tempDir.path);
      final firstPool = _ReconnectableFakePool(
        dailyBarsByCode: {'600000': _buildDailyBars(260)},
      );
      final firstProvider = MarketDataProvider(
        pool: firstPool,
        stockService: StockService(firstPool),
        industryService: IndustryService(),
        dailyBarsFileStorage: storage1,
      );
      firstProvider.setPullbackService(PullbackService());

      await firstProvider.loadFromCache();
      await firstProvider.forceRefetchDailyBars();

      expect(firstProvider.dailyBarsCacheCount, 1);
      expect(firstProvider.dailyBarsCacheSize, isNot('<1KB'));

      final storage2 = _buildStorageForPath(tempDir.path);
      final secondPool = _ReconnectableFakePool(
        dailyBarsByCode: const <String, List<KLine>>{},
        throwOnBatchFetch: true,
      );
      final secondProvider = MarketDataProvider(
        pool: secondPool,
        stockService: StockService(secondPool),
        industryService: IndustryService(),
        dailyBarsFileStorage: storage2,
      );
      secondProvider.setPullbackService(PullbackService());

      await secondProvider.loadFromCache();

      expect(secondProvider.dailyBarsCacheCount, 1);
      expect(secondProvider.dailyBarsCacheSize, isNot('<1KB'));
      expect(secondPool.batchFetchCalls, 0);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('market_data_cache');
      await prefs.remove('market_data_date');
      await prefs.remove('minute_data_date');
      await prefs.remove('minute_data_cache_v1');

      final storage3 = _buildStorageForPath(tempDir.path);
      final thirdPool = _ReconnectableFakePool(
        dailyBarsByCode: const <String, List<KLine>>{},
        throwOnBatchFetch: true,
      );
      final thirdProvider = MarketDataProvider(
        pool: thirdPool,
        stockService: StockService(thirdPool),
        industryService: IndustryService(),
        dailyBarsFileStorage: storage3,
      );

      await thirdProvider.loadFromCache();

      expect(thirdProvider.allData, isEmpty);
      expect(thirdProvider.dailyBarsCacheCount, 1);
      expect(thirdProvider.dailyBarsCacheSize, isNot('<1KB'));
      expect(thirdPool.batchFetchCalls, 0);
    });
  });
}
