import 'package:sqflite/sqflite.dart';
import 'package:stock_rtwatcher/data/models/daily_sync_state.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';

class DailySyncStateStorage {
  DailySyncStateStorage({MarketDatabase? database})
    : _database = database ?? MarketDatabase();

  final MarketDatabase _database;
  static const int _inClauseChunkSize = 800;

  Future<void> upsert(DailySyncState state) async {
    final db = await _database.database;
    await db.insert(
      'daily_sync_state',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DailySyncState?> getByStockCode(String stockCode) async {
    final db = await _database.database;
    final rows = await db.query(
      'daily_sync_state',
      where: 'stock_code = ?',
      whereArgs: [stockCode],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DailySyncState.fromMap(rows.first);
  }

  Future<Map<String, DailySyncState>> getBatchByStockCodes(
    List<String> stockCodes,
  ) async {
    if (stockCodes.isEmpty) {
      return <String, DailySyncState>{};
    }

    final db = await _database.database;
    final result = <String, DailySyncState>{};

    for (
      var start = 0;
      start < stockCodes.length;
      start += _inClauseChunkSize
    ) {
      final end = (start + _inClauseChunkSize).clamp(0, stockCodes.length);
      final chunk = stockCodes.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT * FROM daily_sync_state WHERE stock_code IN ($placeholders)',
        chunk,
      );

      for (final row in rows) {
        final state = DailySyncState.fromMap(row);
        result[state.stockCode] = state;
      }
    }

    return result;
  }

  Future<void> markIntradaySnapshot({
    required String stockCode,
    required DateTime tradeDate,
    String? fingerprint,
  }) async {
    final now = DateTime.now();
    final normalizedTradeDate = DateTime(
      tradeDate.year,
      tradeDate.month,
      tradeDate.day,
    );
    final existing = await getByStockCode(stockCode);
    final keptIntradayDate = _maxDate(
      existing?.lastIntradayDate,
      normalizedTradeDate,
    );

    final nextState =
        (existing ?? DailySyncState(stockCode: stockCode, updatedAt: now))
            .copyWith(
              lastIntradayDate: keptIntradayDate,
              lastFingerprint: fingerprint,
              updatedAt: now,
            );

    await upsert(nextState);
  }

  Future<void> markFinalizedSnapshot({
    required String stockCode,
    required DateTime tradeDate,
    String? fingerprint,
  }) async {
    final now = DateTime.now();
    final normalizedTradeDate = DateTime(
      tradeDate.year,
      tradeDate.month,
      tradeDate.day,
    );
    final existing = await getByStockCode(stockCode);

    final keptFinalizedDate = _maxDate(
      existing?.lastFinalizedDate,
      normalizedTradeDate,
    );
    final shouldOverrideFingerprint =
        existing?.lastFinalizedDate == null ||
        !existing!.lastFinalizedDate!.isAfter(normalizedTradeDate);

    final nextState =
        (existing ?? DailySyncState(stockCode: stockCode, updatedAt: now))
            .copyWith(
              lastFinalizedDate: keptFinalizedDate,
              lastIntradayDate: _maxDate(
                existing?.lastIntradayDate,
                normalizedTradeDate,
              ),
              lastFingerprint: shouldOverrideFingerprint
                  ? fingerprint
                  : existing.lastFingerprint,
              updatedAt: now,
            );

    await upsert(nextState);
  }

  DateTime? _maxDate(DateTime? left, DateTime? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left.isAfter(right) ? left : right;
  }
}
