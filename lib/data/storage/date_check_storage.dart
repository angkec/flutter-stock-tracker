import 'package:sqflite/sqflite.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';

/// 日期检测状态存储
class DateCheckStorage {
  final MarketDatabase _database;

  DateCheckStorage({MarketDatabase? database})
      : _database = database ?? MarketDatabase();

  /// 保存检测状态
  Future<void> saveCheckStatus({
    required String stockCode,
    required KLineDataType dataType,
    required DateTime date,
    required DayDataStatus status,
    required int barCount,
  }) async {
    final db = await _database.database;
    final dateOnly = DateTime(date.year, date.month, date.day);

    await db.insert(
      'date_check_status',
      {
        'stock_code': stockCode,
        'data_type': dataType.name,
        'date': dateOnly.millisecondsSinceEpoch,
        'status': status.name,
        'bar_count': barCount,
        'checked_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 查询多个日期的检测状态
  Future<Map<DateTime, DayDataStatus?>> getCheckedStatus({
    required String stockCode,
    required KLineDataType dataType,
    required List<DateTime> dates,
  }) async {
    if (dates.isEmpty) return {};

    final db = await _database.database;
    final result = <DateTime, DayDataStatus?>{};

    // Initialize all dates as null
    for (final date in dates) {
      final dateOnly = DateTime(date.year, date.month, date.day);
      result[dateOnly] = null;
    }

    // Query database
    final dateTimestamps = dates
        .map((d) => DateTime(d.year, d.month, d.day).millisecondsSinceEpoch)
        .toList();

    final placeholders = List.filled(dateTimestamps.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT date, status FROM date_check_status
      WHERE stock_code = ? AND data_type = ? AND date IN ($placeholders)
      ''',
      [stockCode, dataType.name, ...dateTimestamps],
    );

    for (final row in rows) {
      final dateMs = row['date'] as int;
      final statusName = row['status'] as String;
      final date = DateTime.fromMillisecondsSinceEpoch(dateMs);
      result[date] = DayDataStatus.values.byName(statusName);
    }

    return result;
  }

  /// 获取未完成的日期（incomplete 或 missing）
  Future<List<DateTime>> getPendingDates({
    required String stockCode,
    required KLineDataType dataType,
    bool excludeToday = false,
    DateTime? today,
  }) async {
    final db = await _database.database;

    String query = '''
      SELECT date FROM date_check_status
      WHERE stock_code = ? AND data_type = ? AND status != 'complete'
    ''';

    final args = <dynamic>[stockCode, dataType.name];

    if (excludeToday) {
      final baseDate = today ?? DateTime.now();
      final todayStart = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
      );
      query += ' AND date < ?';
      args.add(todayStart.millisecondsSinceEpoch);
    }

    query += ' ORDER BY date';

    final rows = await db.rawQuery(query, args);

    return rows.map((row) {
      final dateMs = row['date'] as int;
      return DateTime.fromMillisecondsSinceEpoch(dateMs);
    }).toList();
  }

  /// 获取最新的已检测完成日期
  Future<DateTime?> getLatestCheckedDate({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    final db = await _database.database;

    final rows = await db.rawQuery(
      '''
      SELECT date FROM date_check_status
      WHERE stock_code = ? AND data_type = ? AND status = 'complete'
      ORDER BY date DESC
      LIMIT 1
      ''',
      [stockCode, dataType.name],
    );

    if (rows.isEmpty) return null;

    final dateMs = rows.first['date'] as int;
    return DateTime.fromMillisecondsSinceEpoch(dateMs);
  }

  /// 清除检测缓存
  ///
  /// [stockCode] 可选，指定则只清除该股票的缓存
  /// [dataType] 可选，指定则只清除该数据类型的缓存
  /// 都不指定则清除所有缓存
  Future<int> clearCheckStatus({
    String? stockCode,
    KLineDataType? dataType,
  }) async {
    final db = await _database.database;

    String query = 'DELETE FROM date_check_status';
    final conditions = <String>[];
    final args = <dynamic>[];

    if (stockCode != null) {
      conditions.add('stock_code = ?');
      args.add(stockCode);
    }

    if (dataType != null) {
      conditions.add('data_type = ?');
      args.add(dataType.name);
    }

    if (conditions.isNotEmpty) {
      query += ' WHERE ${conditions.join(' AND ')}';
    }

    return await db.rawDelete(query, args);
  }
}
