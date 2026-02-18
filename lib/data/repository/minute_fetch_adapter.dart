import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class MinuteFetchResult {
  final Map<String, List<KLine>> barsByStock;
  final Map<String, String> errorsByStock;
  final Set<String> emptyStockCodes;

  MinuteFetchResult({
    required Map<String, List<KLine>> barsByStock,
    Map<String, String> errorsByStock = const {},
    Set<String>? emptyStockCodes,
  }) : barsByStock = Map.unmodifiable({
         for (final entry in barsByStock.entries)
           entry.key: List<KLine>.unmodifiable(entry.value),
       }),
       errorsByStock = Map.unmodifiable({...errorsByStock}),
       emptyStockCodes = Set.unmodifiable(
         emptyStockCodes ??
             barsByStock.entries
                 .where((entry) => entry.value.isEmpty)
                 .map((entry) => entry.key),
       );
}

abstract class MinuteFetchAdapter {
  Future<Map<String, List<KLine>>> fetchMinuteBars({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  });

  Future<MinuteFetchResult> fetchMinuteBarsWithResult({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    final barsByStock = await fetchMinuteBars(
      stockCodes: stockCodes,
      start: start,
      count: count,
      onProgress: onProgress,
    );

    return MinuteFetchResult(barsByStock: barsByStock);
  }
}
