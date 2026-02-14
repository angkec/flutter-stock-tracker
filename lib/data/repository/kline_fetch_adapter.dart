import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/kline.dart';

abstract class KlineFetchAdapter {
  Future<Map<String, List<KLine>>> fetchBars({
    required List<String> stockCodes,
    required int category,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  });
}
