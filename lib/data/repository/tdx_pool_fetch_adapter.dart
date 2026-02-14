import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/repository/kline_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/repository/minute_fetch_adapter.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class TdxPoolFetchAdapter implements MinuteFetchAdapter, KlineFetchAdapter {
  final TdxPool _pool;

  TdxPoolFetchAdapter({required TdxPool pool}) : _pool = pool;

  @override
  Future<Map<String, List<KLine>>> fetchMinuteBars({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    return fetchBars(
      stockCodes: stockCodes,
      category: klineType1Min,
      start: start,
      count: count,
      onProgress: onProgress,
    );
  }

  @override
  Future<Map<String, List<KLine>>> fetchBars({
    required List<String> stockCodes,
    required int category,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    if (stockCodes.isEmpty) return {};

    final connected = await _pool.ensureConnected();
    if (!connected) {
      return {for (final code in stockCodes) code: <KLine>[]};
    }

    final stocks = stockCodes
        .map(
          (code) =>
              Stock(code: code, name: code, market: _mapCodeToMarket(code)),
        )
        .toList();

    final result = <String, List<KLine>>{
      for (final code in stockCodes) code: <KLine>[],
    };

    var completed = 0;
    await _pool.batchGetSecurityBarsStreaming(
      stocks: stocks,
      category: category,
      start: start,
      count: count,
      onStockBars: (stockIndex, bars) {
        final code = stocks[stockIndex].code;
        result[code] = bars;
        completed++;
        onProgress?.call(completed, stocks.length);
      },
    );

    return result;
  }

  int _mapCodeToMarket(String code) {
    if (code.isEmpty) return 0;
    return code.startsWith('6') ? 1 : 0;
  }
}
