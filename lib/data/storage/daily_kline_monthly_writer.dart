import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class DailyKlineMonthlyWriterImpl {
  DailyKlineMonthlyWriterImpl({KLineMetadataManager? manager})
    : _manager =
          manager ??
          KLineMetadataManager(dailyFileStorage: KLineFileStorageV2());

  final KLineMetadataManager _manager;

  Future<void> call(
    Map<String, List<KLine>> barsByStock, {
    void Function(int current, int total)? onProgress,
  }) async {
    final entries = barsByStock.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    final total = entries.length;
    var completed = 0;

    for (final entry in entries) {
      await _manager.saveKlineData(
        stockCode: entry.key,
        newBars: entry.value,
        dataType: KLineDataType.daily,
        bumpVersion: false,
      );
      completed++;
      onProgress?.call(completed, total);
    }

    if (total > 0) {
      await _manager.incrementDataVersion('Daily sync monthly persist');
    }
  }
}
