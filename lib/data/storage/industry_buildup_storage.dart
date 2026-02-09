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

  Future<DateTime?> getPreviousDate(DateTime currentDate) async {
    final db = await _database.database;
    final currentKey = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    ).millisecondsSinceEpoch;
    final rows = await db.query(
      'industry_buildup_daily',
      columns: ['date'],
      where: 'date < ?',
      whereArgs: [currentKey],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(rows.first['date'] as int);
  }

  Future<DateTime?> getNextDate(DateTime currentDate) async {
    final db = await _database.database;
    final currentKey = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    ).millisecondsSinceEpoch;
    final rows = await db.query(
      'industry_buildup_daily',
      columns: ['date'],
      where: 'date > ?',
      whereArgs: [currentKey],
      orderBy: 'date ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(rows.first['date'] as int);
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
    return _getIndustryMetricTrend(industry, column: 'z_rel', days: days);
  }

  Future<List<double>> getIndustryRawScoreTrend(
    String industry, {
    int days = 20,
  }) async {
    return _getIndustryMetricTrend(industry, column: 'raw_score', days: days);
  }

  Future<List<double>> getIndustryScoreEmaTrend(
    String industry, {
    int days = 20,
  }) async {
    return _getIndustryMetricTrend(industry, column: 'score_ema', days: days);
  }

  Future<List<double>> getIndustryRankTrend(
    String industry, {
    int days = 20,
  }) async {
    return _getIndustryMetricTrend(industry, column: 'rank', days: days);
  }

  Future<List<double>> _getIndustryMetricTrend(
    String industry, {
    required String column,
    required int days,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'industry_buildup_daily',
      columns: [column],
      where: 'industry = ?',
      whereArgs: [industry],
      orderBy: 'date DESC',
      limit: days,
    );

    final trend = rows
        .map((row) => (row[column] as num?)?.toDouble() ?? 0.0)
        .toList();
    return trend.reversed.toList();
  }

  Future<List<IndustryBuildupDailyRecord>> getIndustryHistory(
    String industry, {
    int? limit,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'industry_buildup_daily',
      where: 'industry = ?',
      whereArgs: [industry],
      orderBy: 'date DESC, rank ASC',
      limit: limit,
    );

    return rows.map(IndustryBuildupDailyRecord.fromDbMap).toList();
  }

  Future<void> clearAll() async {
    final db = await _database.database;
    await db.delete('industry_buildup_daily');
  }
}
