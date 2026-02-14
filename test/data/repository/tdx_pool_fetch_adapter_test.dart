import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class FakeTdxPool extends TdxPool {
  FakeTdxPool(this._barsByCode) : super(poolSize: 2);

  final Map<String, List<KLine>> _barsByCode;
  final List<Stock> requestedStocks = [];

  @override
  Future<bool> ensureConnected() async => true;

  @override
  Future<bool> autoConnect() async => true;

  @override
  Future<void> batchGetSecurityBarsStreaming({
    required List<Stock> stocks,
    required int category,
    required int start,
    required int count,
    required void Function(int stockIndex, List<KLine> bars) onStockBars,
  }) async {
    requestedStocks.addAll(stocks);
    for (var index = 0; index < stocks.length; index++) {
      final code = stocks[index].code;
      onStockBars(index, _barsByCode[code] ?? const []);
    }
  }
}

void main() {
  KLine sampleBar(DateTime time) {
    return KLine(
      datetime: time,
      open: 10,
      close: 10.2,
      high: 10.3,
      low: 9.9,
      volume: 1000,
      amount: 10000,
    );
  }

  group('TdxPoolFetchAdapter', () {
    test('returns per-stock bars and reports progress', () async {
      final pool = FakeTdxPool({
        '000001': [sampleBar(DateTime(2026, 2, 14, 9, 30))],
        '600000': [sampleBar(DateTime(2026, 2, 14, 9, 31))],
      });
      final adapter = TdxPoolFetchAdapter(pool: pool);

      final progress = <(int, int)>[];
      final result = await adapter.fetchMinuteBars(
        stockCodes: const ['000001', '600000'],
        start: 0,
        count: 800,
        onProgress: (current, total) => progress.add((current, total)),
      );

      expect(result.keys, containsAll(['000001', '600000']));
      expect(result['000001']!.length, 1);
      expect(result['600000']!.length, 1);
      expect(progress, [(1, 2), (2, 2)]);
      expect(pool.requestedStocks[0].market, 0);
      expect(pool.requestedStocks[1].market, 1);
    });

    test('fills missing stock responses with empty bars', () async {
      final pool = FakeTdxPool({
        '000001': [sampleBar(DateTime(2026, 2, 14, 9, 30))],
      });
      final adapter = TdxPoolFetchAdapter(pool: pool);

      final result = await adapter.fetchMinuteBars(
        stockCodes: const ['000001', '300001'],
        start: 0,
        count: 800,
      );

      expect(result['000001']!.length, 1);
      expect(result['300001'], isEmpty);
    });
  });
}
