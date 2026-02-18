import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/minute_sync_state_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class MinuteWriteStockOutcome {
  final String stockCode;
  final bool success;
  final bool updated;
  final int recordCount;
  final String? error;

  const MinuteWriteStockOutcome({
    required this.stockCode,
    required this.success,
    required this.updated,
    required this.recordCount,
    this.error,
  });
}

class MinuteWriteResult {
  final List<String> updatedStocks;
  final int totalRecords;
  final int persistDurationMs;
  final int versionDurationMs;
  final int totalDurationMs;
  final Map<String, MinuteWriteStockOutcome> outcomesByStock;
  final Map<String, String> errorsByStock;

  const MinuteWriteResult({
    required this.updatedStocks,
    required this.totalRecords,
    this.persistDurationMs = 0,
    this.versionDurationMs = 0,
    this.totalDurationMs = 0,
    this.outcomesByStock = const {},
    this.errorsByStock = const {},
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
          );
          completed++;
          onProgress?.call(completed, nonEmptyEntries.length);
        }
      }

      await Future.wait(
        List.generate(workerCount, (_) => runWorker(), growable: false),
      );

      final succeededStockCodes = outcomes
          .whereType<_StockPersistOutcome>()
          .where((outcome) => outcome.updated)
          .map((outcome) => outcome.stockCode)
          .toList(growable: false);
      if (succeededStockCodes.isNotEmpty) {
        await _syncStateStorage.markFetchSuccessBatch(
          succeededStockCodes,
          lastCompleteTradingDay: fetchedTradingDay,
        );
      }
    }

    persistStopwatch.stop();

    var totalRecords = 0;
    final updatedStocks = <String>[];
    final outcomesByStock = <String, MinuteWriteStockOutcome>{};
    final errorsByStock = <String, String>{};

    for (final outcome in outcomes) {
      if (outcome == null) {
        continue;
      }
      outcomesByStock[outcome.stockCode] = MinuteWriteStockOutcome(
        stockCode: outcome.stockCode,
        success: outcome.success,
        updated: outcome.updated,
        recordCount: outcome.recordCount,
        error: outcome.error,
      );
      if (outcome.error != null && outcome.error!.isNotEmpty) {
        errorsByStock[outcome.stockCode] = outcome.error!;
      }
      if (!outcome.updated) {
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
      outcomesByStock: outcomesByStock,
      errorsByStock: errorsByStock,
    );
  }

  Future<_StockPersistOutcome> _persistStock({
    required String stockCode,
    required List<KLine> bars,
    required KLineDataType dataType,
  }) async {
    try {
      await _metadataManager.saveKlineData(
        stockCode: stockCode,
        newBars: bars,
        dataType: dataType,
        bumpVersion: false,
      );

      return _StockPersistOutcome(
        stockCode: stockCode,
        success: true,
        updated: true,
        recordCount: bars.length,
      );
    } catch (error) {
      debugPrint('MinuteSyncWriter: failed to persist $stockCode - $error');
      await _syncStateStorage.markFetchFailure(stockCode, error.toString());
      return _StockPersistOutcome(
        stockCode: stockCode,
        success: false,
        updated: false,
        recordCount: 0,
        error: error.toString(),
      );
    }
  }
}

class _StockPersistOutcome {
  final String stockCode;
  final bool success;
  final bool updated;
  final int recordCount;
  final String? error;

  const _StockPersistOutcome({
    required this.stockCode,
    required this.success,
    required this.updated,
    required this.recordCount,
    this.error,
  });
}
