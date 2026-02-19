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
    final result = await fetchMinuteBarsWithResult(
      stockCodes: stockCodes,
      start: start,
      count: count,
      onProgress: onProgress,
    );
    return result.barsByStock;
  }

  @override
  Future<MinuteFetchResult> fetchMinuteBarsWithResult({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    if (stockCodes.isEmpty) {
      return MinuteFetchResult(barsByStock: const {});
    }

    final barsByStock = <String, List<KLine>>{
      for (final code in stockCodes) code: <KLine>[],
    };
    final errorsByStock = <String, String>{};

    final connected = await _pool.ensureConnected();
    if (!connected) {
      for (final code in stockCodes) {
        errorsByStock[code] = 'Unable to connect to TDX pool';
      }
      return MinuteFetchResult(
        barsByStock: barsByStock,
        errorsByStock: errorsByStock,
      );
    }

    final stocks = stockCodes
        .map(
          (code) =>
              Stock(code: code, name: code, market: _mapCodeToMarket(code)),
        )
        .toList();

    var completed = 0;
    final completedCodes = <String>{};
    try {
      await _pool.batchGetSecurityBarsStreaming(
        stocks: stocks,
        category: klineType1Min,
        start: start,
        count: count,
        onStockBars: (stockIndex, bars) {
          final code = stocks[stockIndex].code;
          barsByStock[code] = bars;
          completedCodes.add(code);
          completed++;
          onProgress?.call(completed, stocks.length);
        },
      );
    } catch (error) {
      final errorMessage = 'Minute pool fetch failed: $error';
      for (final code in stockCodes) {
        if (!completedCodes.contains(code)) {
          errorsByStock[code] = errorMessage;
        }
      }
    }

    return MinuteFetchResult(
      barsByStock: barsByStock,
      errorsByStock: errorsByStock,
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

    final indexCodes = stockCodes.where(_isIndexCode).toList(growable: false);
    final regularCodes =
        stockCodes.where((code) => !_isIndexCode(code)).toList(growable: false);
    final stocks = regularCodes
        .map(
          (code) =>
              Stock(code: code, name: code, market: _mapCodeToMarket(code)),
        )
        .toList();

    final result = <String, List<KLine>>{
      for (final code in stockCodes) code: <KLine>[],
    };

    var completed = 0;
    if (stocks.isNotEmpty) {
      await _pool.batchGetSecurityBarsStreaming(
        stocks: stocks,
        category: category,
        start: start,
        count: count,
        onStockBars: (stockIndex, bars) {
          final code = stocks[stockIndex].code;
          result[code] = bars;
          completed++;
          onProgress?.call(completed, stockCodes.length);
        },
      );
    }

    if (indexCodes.isNotEmpty) {
      for (final code in indexCodes) {
        try {
          final market = _mapIndexCodeToMarket(code);
          final bars = await _pool.getIndexBars(
            market: market,
            code: code,
            category: category,
            start: start,
            count: count,
          );
          result[code] = bars;
        } catch (_) {
          result[code] = const <KLine>[];
        }
        completed++;
        onProgress?.call(completed, stockCodes.length);
      }
    }

    return result;
  }

  bool _isIndexCode(String code) {
    if (code.length != 6) return false;
    return code.startsWith('399') ||
        code.startsWith('899') ||
        code.startsWith('999');
  }

  int _mapIndexCodeToMarket(String code) {
    if (code.startsWith('399')) return 0;
    if (code.startsWith('899')) return 2;
    if (code.startsWith('999')) return 1;
    return _mapCodeToMarket(code);
  }

  int _mapCodeToMarket(String code) {
    if (code.isEmpty) return 0;
    return code.startsWith('6') ? 1 : 0;
  }
}
