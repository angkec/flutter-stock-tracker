import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/sw_daily_bar.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

class SwIndexSyncResult {
  final List<String> fetchedCodes;
  final int totalBars;

  const SwIndexSyncResult({
    required this.fetchedCodes,
    required this.totalBars,
  });
}

class SwIndexCacheStats {
  final int codeCount;
  final int dataVersion;

  const SwIndexCacheStats({required this.codeCount, required this.dataVersion});
}

class SwIndexRepository {
  final KLineMetadataManager _metadataManager;
  final TushareClient _client;

  SwIndexRepository({
    KLineMetadataManager? metadataManager,
    required TushareClient client,
  }) : _metadataManager = metadataManager ?? KLineMetadataManager(),
       _client = client;

  Future<SwIndexSyncResult> syncMissingDaily({
    required List<String> tsCodes,
    required DateRange dateRange,
  }) async {
    var totalBars = 0;
    final fetchedCodes = <String>[];
    final localCodes = tsCodes.map(_toLocalCode).toList(growable: false);
    final coverageByCode = await _metadataManager.getCoverageRanges(
      stockCodes: localCodes,
      dataType: KLineDataType.daily,
    );

    for (var i = 0; i < tsCodes.length; i++) {
      final tsCode = tsCodes[i];
      final localCode = localCodes[i];
      final coverage = coverageByCode[localCode];

      final fetchStart = _resolveFetchStart(dateRange.start, coverage?.endDate);
      if (fetchStart.isAfter(dateRange.end)) {
        continue;
      }

      final bars = await _client.fetchSwDaily(
        tsCode: tsCode,
        startDate: _formatDate(fetchStart),
        endDate: _formatDate(dateRange.end),
      );
      if (bars.isEmpty) {
        continue;
      }

      final klines = bars.map((e) => e.toKLine()).toList(growable: false);
      await _metadataManager.saveKlineData(
        stockCode: localCode,
        newBars: klines,
        dataType: KLineDataType.daily,
      );
      fetchedCodes.add(tsCode);
      totalBars += klines.length;
    }

    return SwIndexSyncResult(fetchedCodes: fetchedCodes, totalBars: totalBars);
  }

  Future<SwIndexSyncResult> refetchDaily({
    required List<String> tsCodes,
    required DateRange dateRange,
  }) async {
    var totalBars = 0;
    final fetchedCodes = <String>[];
    for (final tsCode in tsCodes) {
      final bars = await _client.fetchSwDaily(
        tsCode: tsCode,
        startDate: _formatDate(dateRange.start),
        endDate: _formatDate(dateRange.end),
      );
      if (bars.isEmpty) {
        continue;
      }

      final localCode = _toLocalCode(tsCode);
      final klines = bars.map((e) => e.toKLine()).toList(growable: false);
      await _metadataManager.saveKlineData(
        stockCode: localCode,
        newBars: klines,
        dataType: KLineDataType.daily,
      );
      fetchedCodes.add(tsCode);
      totalBars += klines.length;
    }

    return SwIndexSyncResult(fetchedCodes: fetchedCodes, totalBars: totalBars);
  }

  Future<Map<String, List<KLine>>> getDailyKlines({
    required List<String> tsCodes,
    required DateRange dateRange,
  }) async {
    final result = <String, List<KLine>>{};
    for (final tsCode in tsCodes) {
      final localCode = _toLocalCode(tsCode);
      result[tsCode] = await _metadataManager.loadKlineData(
        stockCode: localCode,
        dataType: KLineDataType.daily,
        dateRange: dateRange,
      );
    }
    return result;
  }

  Future<SwIndexCacheStats> getCacheStats() async {
    final codes = await _metadataManager.getAllStockCodes(
      dataType: KLineDataType.daily,
    );
    final swCodes = codes.where((code) => code.startsWith('sw_')).length;
    final version = await _metadataManager.getCurrentVersion();
    return SwIndexCacheStats(codeCount: swCodes, dataVersion: version);
  }

  static String toLocalCode(String tsCode) => _toLocalCode(tsCode);

  static String _toLocalCode(String tsCode) {
    return 'sw_${tsCode.toLowerCase().replaceAll('.', '_')}';
  }

  static DateTime _resolveFetchStart(
    DateTime requiredStart,
    DateTime? coveredEnd,
  ) {
    if (coveredEnd == null) {
      return DateTime(
        requiredStart.year,
        requiredStart.month,
        requiredStart.day,
      );
    }
    final next = DateTime(
      coveredEnd.year,
      coveredEnd.month,
      coveredEnd.day,
    ).add(const Duration(days: 1));
    if (next.isBefore(requiredStart)) {
      return DateTime(
        requiredStart.year,
        requiredStart.month,
        requiredStart.day,
      );
    }
    return next;
  }

  static String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }
}

List<KLine> mapSwBarsToKlines(List<SwDailyBar> bars) {
  return bars.map((bar) => bar.toKLine()).toList(growable: false);
}
