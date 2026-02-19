import 'dart:async';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class DailyKlineMonthlyWriterImpl {
  DailyKlineMonthlyWriterImpl({
    int maxConcurrentWrites = 6,
    KLineMetadataManager? manager,
  }) : _maxConcurrentWrites = maxConcurrentWrites,
       _manager =
           manager ??
           KLineMetadataManager(dailyFileStorage: KLineFileStorageV2());

  final int _maxConcurrentWrites;
  final KLineMetadataManager _manager;

  Future<void> call(
    Map<String, List<KLine>> barsByStock, {
    void Function(int current, int total)? onProgress,
  }) async {
    final entries = barsByStock.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    final total = entries.length;
    if (total == 0) return;

    var completed = 0;
    var index = 0;
    final mutex = <Future<void>>[];

    Future<void> worker() async {
      while (true) {
        final int i;
        // Claim next entry index
        i = index++;
        if (i >= total) return;

        await _manager.saveKlineData(
          stockCode: entries[i].key,
          newBars: entries[i].value,
          dataType: KLineDataType.daily,
          bumpVersion: false,
        );
        completed++;
        onProgress?.call(completed, total);
      }
    }

    final workerCount =
        _maxConcurrentWrites < total ? _maxConcurrentWrites : total;
    for (var w = 0; w < workerCount; w++) {
      mutex.add(worker());
    }
    await Future.wait(mutex);

    await _manager.incrementDataVersion('Daily sync monthly persist');
  }
}
