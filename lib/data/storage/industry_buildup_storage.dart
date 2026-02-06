import 'package:sqflite/sqflite.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';

class IndustryBuildUpStorage {
  final MarketDatabase _database;

  IndustryBuildUpStorage({MarketDatabase? database})
    : _database = database ?? MarketDatabase();

  Future<void> upsertDailyResults(
    List<IndustryBuildupDailyRecord> records,
  ) async {
    if (records.isEmpty) return;

    final db = await _database.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final record in records) {
        batch.insert(
          'industry_buildup_daily',
          record.toDbMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<DateTime?> getLatestDate() async {
    final db = await _database.database;
    final rows = await db.query(
      'industry_buildup_daily',
      columns: ['date'],
      orderBy: 'date DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(rows.first['date'] as int);
  }

  Future<List<IndustryBuildupDailyRecord>> getLatestBoard({
    int limit = 50,
  }) async {
    final latestDate = await getLatestDate();
    if (latestDate == null) {
      return [];
    }

    return getBoardForDate(latestDate, limit: limit);
  }

  Future<List<IndustryBuildupDailyRecord>> getBoardForDate(
    DateTime date, {
    int limit = 50,
  }) async {
    final db = await _database.database;
    final dateOnly = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final rows = await db.query(
      'industry_buildup_daily',
      where: 'date = ?',
      whereArgs: [dateOnly],
      orderBy: 'rank ASC',
      limit: limit,
    );

    return rows.map(IndustryBuildupDailyRecord.fromDbMap).toList();
  }

  Future<List<double>> getIndustryTrend(
    String industry, {
    int days = 20,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'industry_buildup_daily',
      columns: ['z_rel'],
      where: 'industry = ?',
      whereArgs: [industry],
      orderBy: 'date DESC',
      limit: days,
    );

    final trend = rows.map((row) => (row['z_rel'] as num).toDouble()).toList();
    return trend.reversed.toList();
  }

  Future<void> clearAll() async {
    final db = await _database.database;
    await db.delete('industry_buildup_daily');
  }
}
