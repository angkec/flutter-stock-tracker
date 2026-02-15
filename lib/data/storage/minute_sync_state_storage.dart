import 'package:sqflite/sqflite.dart';
import 'package:stock_rtwatcher/data/models/minute_sync_state.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';

class MinuteSyncStateStorage {
  final MarketDatabase _database;
  static const int _inClauseChunkSize = 800;

  MinuteSyncStateStorage({MarketDatabase? database})
    : _database = database ?? MarketDatabase();

  Future<void> upsert(MinuteSyncState state) async {
    final db = await _database.database;
    await db.insert(
      'minute_sync_state',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<MinuteSyncState?> getByStockCode(String stockCode) async {
    final db = await _database.database;
    final rows = await db.query(
      'minute_sync_state',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return MinuteSyncState.fromMap(rows.first);
  }

  Future<Map<String, MinuteSyncState>> getBatchByStockCodes(
    List<String> stockCodes,
  ) async {
    if (stockCodes.isEmpty) return {};

    final db = await _database.database;
    final result = <String, MinuteSyncState>{};

    for (
      var start = 0;
      start < stockCodes.length;
      start += _inClauseChunkSize
    ) {
      final end = (start + _inClauseChunkSize).clamp(0, stockCodes.length);
      final chunk = stockCodes.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT * FROM minute_sync_state WHERE stock_code IN ($placeholders)',
        chunk,
      );

      for (final row in rows) {
        final state = MinuteSyncState.fromMap(row);
        result[state.stockCode] = state;
      }
    }

    return result;
  }

  Future<void> markFetchFailure(String stockCode, String errorMessage) async {
    final now = DateTime.now();
    final existing = await getByStockCode(stockCode);

    final state =
        (existing ?? MinuteSyncState(stockCode: stockCode, updatedAt: now))
            .copyWith(
              consecutiveFailures: (existing?.consecutiveFailures ?? 0) + 1,
              lastError: errorMessage,
              lastAttemptAt: now,
              updatedAt: now,
            );

    await upsert(state);
  }

  Future<void> markFetchSuccess(
    String stockCode, {
    DateTime? lastCompleteTradingDay,
  }) async {
    final now = DateTime.now();
    final normalizedCompleteDay = lastCompleteTradingDay == null
        ? null
        : DateTime(
            lastCompleteTradingDay.year,
            lastCompleteTradingDay.month,
            lastCompleteTradingDay.day,
          );
    final existing = await getByStockCode(stockCode);

    final state =
        (existing ?? MinuteSyncState(stockCode: stockCode, updatedAt: now))
            .copyWith(
              lastCompleteTradingDay:
                  normalizedCompleteDay ?? existing?.lastCompleteTradingDay,
              lastSuccessFetchAt: now,
              lastAttemptAt: now,
              consecutiveFailures: 0,
              clearLastError: true,
              updatedAt: now,
            );

    await upsert(state);
  }

  Future<void> markFetchSuccessBatch(
    List<String> stockCodes, {
    DateTime? lastCompleteTradingDay,
  }) async {
    if (stockCodes.isEmpty) return;

    final db = await _database.database;
    final now = DateTime.now();
    final normalizedCompleteDay = lastCompleteTradingDay == null
        ? null
        : DateTime(
            lastCompleteTradingDay.year,
            lastCompleteTradingDay.month,
            lastCompleteTradingDay.day,
          );

    final existingMap = await getBatchByStockCodes(stockCodes);

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final stockCode in stockCodes) {
        final existing = existingMap[stockCode];
        final state =
            (existing ?? MinuteSyncState(stockCode: stockCode, updatedAt: now))
                .copyWith(
                  lastCompleteTradingDay:
                      normalizedCompleteDay ?? existing?.lastCompleteTradingDay,
                  lastSuccessFetchAt: now,
                  lastAttemptAt: now,
                  consecutiveFailures: 0,
                  clearLastError: true,
                  updatedAt: now,
                );

        batch.insert(
          'minute_sync_state',
          state.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }
}
