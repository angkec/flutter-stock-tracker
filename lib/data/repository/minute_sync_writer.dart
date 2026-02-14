import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/minute_sync_state_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class MinuteWriteResult {
  final List<String> updatedStocks;
  final int totalRecords;
  final int persistDurationMs;
  final int versionDurationMs;
  final int totalDurationMs;

  const MinuteWriteResult({
    required this.updatedStocks,
    required this.totalRecords,
    this.persistDurationMs = 0,
    this.versionDurationMs = 0,
    this.totalDurationMs = 0,
  });
}

class MinuteSyncWriter {
  final KLineMetadataManager _metadataManager;
  final MinuteSyncStateStorage _syncStateStorage;
  int _maxConcurrentWrites;

  int get maxConcurrentWrites => _maxConcurrentWrites;

  void setMaxConcurrentWrites(int value) {
    _maxConcurrentWrites = max(1, value);
  }

  MinuteSyncWriter({
    required KLineMetadataManager metadataManager,
    required MinuteSyncStateStorage syncStateStorage,
    int maxConcurrentWrites = 1,
  }) : _metadataManager = metadataManager,
       _syncStateStorage = syncStateStorage,
       _maxConcurrentWrites = max(1, maxConcurrentWrites);

  Future<MinuteWriteResult> writeBatch({
    required Map<String, List<KLine>> barsByStock,
    required KLineDataType dataType,
    DateTime? fetchedTradingDay,
    void Function(int current, int total)? onProgress,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    final persistStopwatch = Stopwatch()..start();

    final nonEmptyEntries = barsByStock.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);

    final outcomes = List<_StockPersistOutcome?>.filled(
      nonEmptyEntries.length,
      null,
    );

    if (nonEmptyEntries.isNotEmpty) {
      final workerCount = min(_maxConcurrentWrites, nonEmptyEntries.length);
      var nextIndex = 0;
      var completed = 0;

      Future<void> runWorker() async {
        while (true) {
          final currentIndex = nextIndex;
          if (currentIndex >= nonEmptyEntries.length) {
            return;
          }
          nextIndex++;

          final entry = nonEmptyEntries[currentIndex];
          outcomes[currentIndex] = await _persistStock(
            stockCode: entry.key,
            bars: entry.value,
            dataType: dataType,
            fetchedTradingDay: fetchedTradingDay,
          );
          completed++;
          onProgress?.call(completed, nonEmptyEntries.length);
        }
      }

      await Future.wait(
        List.generate(workerCount, (_) => runWorker(), growable: false),
      );
    }

    persistStopwatch.stop();

    var totalRecords = 0;
    final updatedStocks = <String>[];

    for (final outcome in outcomes) {
      if (outcome == null || !outcome.updated) {
        continue;
      }
      updatedStocks.add(outcome.stockCode);
      totalRecords += outcome.recordCount;
    }

    var versionDurationMs = 0;
    if (updatedStocks.isNotEmpty) {
      final versionStopwatch = Stopwatch()..start();
      await _metadataManager.incrementDataVersion(
        'Updated minute K-line batch (${updatedStocks.length} stocks)',
      );
      versionStopwatch.stop();
      versionDurationMs = versionStopwatch.elapsedMilliseconds;
    }

    totalStopwatch.stop();

    return MinuteWriteResult(
      updatedStocks: updatedStocks,
      totalRecords: totalRecords,
      persistDurationMs: persistStopwatch.elapsedMilliseconds,
      versionDurationMs: versionDurationMs,
      totalDurationMs: totalStopwatch.elapsedMilliseconds,
    );
  }

  Future<_StockPersistOutcome> _persistStock({
    required String stockCode,
    required List<KLine> bars,
    required KLineDataType dataType,
    required DateTime? fetchedTradingDay,
  }) async {
    try {
      await _metadataManager.saveKlineData(
        stockCode: stockCode,
        newBars: bars,
        dataType: dataType,
        bumpVersion: false,
      );

      await _syncStateStorage.markFetchSuccess(
        stockCode,
        lastCompleteTradingDay: fetchedTradingDay,
      );

      return _StockPersistOutcome(
        stockCode: stockCode,
        updated: true,
        recordCount: bars.length,
      );
    } catch (error) {
      debugPrint('MinuteSyncWriter: failed to persist $stockCode - $error');
      await _syncStateStorage.markFetchFailure(stockCode, error.toString());
      return _StockPersistOutcome(
        stockCode: stockCode,
        updated: false,
        recordCount: 0,
      );
    }
  }
}

class _StockPersistOutcome {
  final String stockCode;
  final bool updated;
  final int recordCount;

  const _StockPersistOutcome({
    required this.stockCode,
    required this.updated,
    required this.recordCount,
  });
}
