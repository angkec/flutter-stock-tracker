import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';

enum DailyKlineReadFailureReason {
  missingFile,
  corruptedPayload,
  invalidOrder,
  insufficientBars,
}

class DailyKlineReadReport {
  const DailyKlineReadReport({
    required this.totalStocks,
    required this.missingStockCodes,
    required this.corruptedStockCodes,
    required this.insufficientStockCodes,
  });

  final int totalStocks;
  final List<String> missingStockCodes;
  final List<String> corruptedStockCodes;
  final List<String> insufficientStockCodes;

  int get missingCount => missingStockCodes.length;
  int get corruptedCount => corruptedStockCodes.length;
  int get insufficientCount => insufficientStockCodes.length;

  int get shortageCount => missingCount + corruptedCount + insufficientCount;

  double get shortageRatio =>
      totalStocks <= 0 ? 0 : shortageCount / totalStocks;

  bool isShortageOver(double threshold) => shortageRatio > threshold;
}

class DailyKlineReadResult {
  const DailyKlineReadResult({
    required this.barsByStockCode,
    required this.report,
  });

  final Map<String, List<KLine>> barsByStockCode;
  final DailyKlineReadReport report;
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

  Future<DailyKlineReadResult> readWithReport({
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
    final missingStockCodes = <String>[];
    final corruptedStockCodes = <String>[];
    final insufficientStockCodes = <String>[];

    for (final stockCode in stockCodes) {
      final loadResult = loaded[stockCode];
      if (loadResult?.status == DailyKlineCacheLoadStatus.corrupted) {
        corruptedStockCodes.add(stockCode);
        continue;
      }

      if (loadResult == null ||
          loadResult.status == DailyKlineCacheLoadStatus.missing ||
          loadResult.bars.isEmpty) {
        missingStockCodes.add(stockCode);
        continue;
      }

      final bars = loadResult.bars;
      var isSorted = true;
      for (var index = 1; index < bars.length; index++) {
        if (bars[index - 1].datetime.isAfter(bars[index].datetime)) {
          isSorted = false;
          break;
        }
      }
      if (!isSorted) {
        corruptedStockCodes.add(stockCode);
        continue;
      }

      if (bars.length < targetBars) {
        insufficientStockCodes.add(stockCode);
      }

      result[stockCode] = bars;
    }

    return DailyKlineReadResult(
      barsByStockCode: result,
      report: DailyKlineReadReport(
        totalStocks: stockCodes.length,
        missingStockCodes: missingStockCodes,
        corruptedStockCodes: corruptedStockCodes,
        insufficientStockCodes: insufficientStockCodes,
      ),
    );
  }
}
