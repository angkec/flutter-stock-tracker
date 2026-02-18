import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';

enum DailyKlineReadFailureReason {
  missingFile,
  corruptedPayload,
  invalidOrder,
  insufficientBars,
}

class DailyKlineReadException implements Exception {
  const DailyKlineReadException({
    required this.stockCode,
    required this.reason,
    required this.message,
  });

  final String stockCode;
  final DailyKlineReadFailureReason reason;
  final String message;

  @override
  String toString() {
    return 'DailyKlineReadException(stock=$stockCode, reason=$reason, message=$message)';
  }
}

class DailyKlineReadService {
  DailyKlineReadService({required DailyKlineCacheStore cacheStore})
    : _cacheStore = cacheStore;

  final DailyKlineCacheStore _cacheStore;

  Future<Map<String, List<KLine>>> readOrThrow({
    required List<String> stockCodes,
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    final loaded = await _cacheStore.loadForStocksWithStatus(
      stockCodes,
      anchorDate: anchorDate,
      targetBars: targetBars,
    );

    final result = <String, List<KLine>>{};
    for (final stockCode in stockCodes) {
      final loadResult = loaded[stockCode];
      if (loadResult?.status == DailyKlineCacheLoadStatus.corrupted) {
        throw DailyKlineReadException(
          stockCode: stockCode,
          reason: DailyKlineReadFailureReason.corruptedPayload,
          message: 'Daily cache file is corrupted',
        );
      }

      if (loadResult == null ||
          loadResult.status == DailyKlineCacheLoadStatus.missing ||
          loadResult.bars.isEmpty) {
        throw DailyKlineReadException(
          stockCode: stockCode,
          reason: DailyKlineReadFailureReason.missingFile,
          message: 'Daily cache file missing or empty',
        );
      }

      final bars = loadResult.bars;
      for (var index = 1; index < bars.length; index++) {
        if (bars[index - 1].datetime.isAfter(bars[index].datetime)) {
          throw DailyKlineReadException(
            stockCode: stockCode,
            reason: DailyKlineReadFailureReason.invalidOrder,
            message: 'Daily bars are not sorted by datetime',
          );
        }
      }

      if (bars.length < targetBars) {
        throw DailyKlineReadException(
          stockCode: stockCode,
          reason: DailyKlineReadFailureReason.insufficientBars,
          message:
              'Daily bars shorter than target: got ${bars.length}, expected $targetBars',
        );
      }

      result[stockCode] = bars;
    }

    return result;
  }
}
