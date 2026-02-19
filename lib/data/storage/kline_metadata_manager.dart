// lib/data/storage/kline_metadata_manager.dart

import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/storage/kline_append_result.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_monthly_storage.dart';

/// Metadata for a K-line file
class KLineFileMetadata {
  final String stockCode;
  final KLineDataType dataType;
  final String yearMonth;
  final String filePath;
  final DateTime? startDate;
  final DateTime? endDate;
  final int recordCount;
  final String? checksum;
  final int fileSize;

  KLineFileMetadata({
    required this.stockCode,
    required this.dataType,
    required this.yearMonth,
    required this.filePath,
    this.startDate,
    this.endDate,
    this.recordCount = 0,
    this.checksum,
    this.fileSize = 0,
  });

  /// Create from database row map
  factory KLineFileMetadata.fromMap(Map<String, dynamic> map) {
    return KLineFileMetadata(
      stockCode: map['stock_code'] as String,
      dataType: KLineDataType.fromName(map['data_type'] as String),
      yearMonth: map['year_month'] as String,
      filePath: map['file_path'] as String,
      startDate: map['start_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['start_date'] as int)
          : null,
      endDate: map['end_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_date'] as int)
          : null,
      recordCount: (map['record_count'] as int?) ?? 0,
      checksum: map['checksum'] as String?,
      fileSize: (map['file_size'] as int?) ?? 0,
    );
  }

  /// Convert to map for database insert/update
  Map<String, dynamic> toMap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      'stock_code': stockCode,
      'data_type': dataType.name,
      'year_month': yearMonth,
      'file_path': filePath,
      'start_date': startDate?.millisecondsSinceEpoch,
      'end_date': endDate?.millisecondsSinceEpoch,
      'record_count': recordCount,
      'checksum': checksum,
      'file_size': fileSize,
      'created_at': now,
      'updated_at': now,
    };
  }

  @override
  String toString() =>
      'KLineFileMetadata(stockCode=$stockCode, dataType=$dataType, yearMonth=$yearMonth, recordCount=$recordCount)';
}

/// Manages K-line data storage with coordinated file and database updates
class KLineMetadataManager {
  static const int _inClauseChunkSize = 800;
  static const int _maxTradingDateRangeCacheEntries = 128;

  final MarketDatabase _db;
  final KLineMonthlyStorage _fileStorage;
  final KLineMonthlyStorage? _dailyFileStorage;
  final LinkedHashMap<String, List<DateTime>> _tradingDateRangeCache =
      LinkedHashMap<String, List<DateTime>>();
  final Map<String, Future<List<DateTime>>> _tradingDateRangeInFlight = {};
  int? _tradingDateCacheVersion;
  bool _dailyStoragePrepared = false;

  KLineMetadataManager({
    MarketDatabase? database,
    KLineMonthlyStorage? fileStorage,
    KLineMonthlyStorage? dailyFileStorage,
  }) : _db = database ?? MarketDatabase(),
       _fileStorage = fileStorage ?? KLineFileStorage(),
       _dailyFileStorage = dailyFileStorage;

  KLineMonthlyStorage _resolveStorage(KLineDataType dataType) {
    if (dataType == KLineDataType.daily && _dailyFileStorage != null) {
      return _dailyFileStorage!;
    }
    return _fileStorage;
  }

  Future<void> _prepareDailyStorageIfNeeded() async {
    if (_dailyStoragePrepared || _dailyFileStorage == null) {
      return;
    }

    final baseDir = await _dailyFileStorage!.getBaseDirectoryPath();
    if (!baseDir.contains('klines_v2')) {
      _dailyFileStorage!.setBaseDirPathForTesting(
        '$baseDir/market_data/klines_v2',
      );
    }
    _dailyStoragePrepared = true;
  }

  /// Save K-line data with metadata update in a transaction
  ///
  /// This method:
  /// 1. Saves K-line data to monthly files
  /// 2. In a database transaction, updates metadata for each affected month
  /// 3. Increments the data version
  Future<void> saveKlineData({
    required String stockCode,
    required List<KLine> newBars,
    required KLineDataType dataType,
    bool bumpVersion = true,
  }) async {
    if (newBars.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (dataType == KLineDataType.daily) {
      await _prepareDailyStorageIfNeeded();
    }
    final storage = _resolveStorage(dataType);

    // Group new bars by year-month
    final barsByMonth = <String, List<KLine>>{};
    for (final bar in newBars) {
      final yearMonth =
          '${bar.datetime.year}${bar.datetime.month.toString().padLeft(2, '0')}';
      barsByMonth.putIfAbsent(yearMonth, () => []).add(bar);
    }

    // Save to files (this will handle deduplication)
    final appendResultsByMonth = <String, KLineAppendResult>{};
    for (final entry in barsByMonth.entries) {
      final yearMonth = entry.key;
      final klines = entry.value;

      final year = int.parse(yearMonth.substring(0, 4));
      final month = int.parse(yearMonth.substring(4, 6));

      try {
        final appendResult = await storage.appendKlineData(
          stockCode,
          dataType,
          year,
          month,
          klines,
        );

        if (appendResult != null) {
          appendResultsByMonth[yearMonth] = appendResult;
        }
      } catch (error) {
        debugPrint(
          'Failed to append K-line data for $stockCode $yearMonth: $error',
        );
        // Continue with other months
      }
    }

    // Prepare metadata from append results (avoid repeated file reload)
    final metadataMap =
        <
          String,
          ({
            DateTime startDate,
            DateTime endDate,
            int recordCount,
            int fileSize,
            String filePath,
          })
        >{};

    for (final entry in appendResultsByMonth.entries) {
      final yearMonth = entry.key;
      final appendResult = entry.value;

      if (!appendResult.changed ||
          appendResult.startDate == null ||
          appendResult.endDate == null) {
        continue;
      }

      metadataMap[yearMonth] = (
        startDate: appendResult.startDate!,
        endDate: appendResult.endDate!,
        recordCount: appendResult.recordCount,
        fileSize: appendResult.fileSize,
        filePath: appendResult.filePath,
      );
    }

    if (metadataMap.isEmpty) {
      return;
    }

    // Update metadata in transaction
    final database = await _db.database;
    await database.transaction((txn) async {
      for (final entry in metadataMap.entries) {
        final yearMonth = entry.key;
        final metadata = entry.value;

        // Insert or update metadata
        await txn.insert('kline_files', {
          'stock_code': stockCode,
          'data_type': dataType.name,
          'year_month': yearMonth,
          'file_path': metadata.filePath,
          'start_date': metadata.startDate.millisecondsSinceEpoch,
          'end_date': metadata.endDate.millisecondsSinceEpoch,
          'record_count': metadata.recordCount,
          'checksum': null,
          'created_at': now,
          'updated_at': now,
          'file_size': metadata.fileSize,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      if (bumpVersion) {
        // Increment data version within the transaction
        final currentVersionRows = await txn.query(
          'data_versions',
          columns: ['version'],
          orderBy: 'id DESC',
          limit: 1,
        );

        final currentVersion = currentVersionRows.isEmpty
            ? 1
            : (currentVersionRows.first['version'] as int);
        final newVersion = currentVersion + 1;

        await txn.insert('data_versions', {
          'version': newVersion,
          'description': 'Updated K-line data for $stockCode',
          'created_at': now,
        });
      }
    });

    _invalidateTradingDateRangeCache();
  }

  Future<int> incrementDataVersion(String description) async {
    final version = await _db.incrementVersion(description);
    _invalidateTradingDateRangeCache();
    return version;
  }

  /// Get all metadata for a stock and data type
  Future<List<KLineFileMetadata>> getMetadata({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    final database = await _db.database;
    final rows = await database.query(
      'kline_files',
      where: 'stock_code = ? AND data_type = ?',
      whereArgs: [stockCode, dataType.name],
      orderBy: 'year_month ASC',
    );

    return rows.map((row) => KLineFileMetadata.fromMap(row)).toList();
  }

  /// 批量获取股票在指定数据类型下的起止覆盖范围
  ///
  /// 返回: {stockCode: (startDate, endDate)}
  Future<Map<String, ({DateTime? startDate, DateTime? endDate})>>
  getCoverageRanges({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    final result = <String, ({DateTime? startDate, DateTime? endDate})>{};
    if (stockCodes.isEmpty) {
      return result;
    }

    final database = await _db.database;

    for (
      var start = 0;
      start < stockCodes.length;
      start += _inClauseChunkSize
    ) {
      final end = (start + _inClauseChunkSize).clamp(0, stockCodes.length);
      final chunk = stockCodes.sublist(start, end);
      if (chunk.isEmpty) {
        continue;
      }

      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await database.rawQuery(
        '''
        SELECT
          stock_code,
          MIN(start_date) AS min_start_date,
          MAX(end_date) AS max_end_date
        FROM kline_files
        WHERE data_type = ? AND stock_code IN ($placeholders)
        GROUP BY stock_code
        ''',
        [dataType.name, ...chunk],
      );

      for (final row in rows) {
        final stockCode = row['stock_code'] as String;
        final startMs = row['min_start_date'] as int?;
        final endMs = row['max_end_date'] as int?;

        result[stockCode] = (
          startDate: startMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(startMs),
          endDate: endMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(endMs),
        );
      }
    }

    return result;
  }

  /// Get the most recent data date for a stock and data type
  Future<DateTime?> getLatestDataDate({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    final database = await _db.database;
    final rows = await database.query(
      'kline_files',
      where: 'stock_code = ? AND data_type = ?',
      whereArgs: [stockCode, dataType.name],
      orderBy: 'end_date DESC',
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final endDate = rows.first['end_date'] as int?;
    return endDate != null
        ? DateTime.fromMillisecondsSinceEpoch(endDate)
        : null;
  }

  /// Load K-line data by date range
  ///
  /// Queries metadata to find relevant months, then loads data from files.
  /// Returns all K-lines within the date range, sorted by datetime.
  Future<List<KLine>> loadKlineData({
    required String stockCode,
    required KLineDataType dataType,
    required DateRange dateRange,
  }) async {
    if (dataType == KLineDataType.daily) {
      await _prepareDailyStorageIfNeeded();
    }
    final metadata = await getMetadata(
      stockCode: stockCode,
      dataType: dataType,
    );

    final result = <KLine>[];

    for (final meta in metadata) {
      // Check if this month overlaps with the date range
      if (meta.startDate == null || meta.endDate == null) continue;

      final monthStart = meta.startDate!;
      final monthEnd = meta.endDate!;

      // Skip if month is outside the date range
      if (monthEnd.isBefore(dateRange.start) ||
          monthStart.isAfter(dateRange.end)) {
        continue;
      }

      // Load the month file
      final year = int.parse(meta.yearMonth.substring(0, 4));
      final month = int.parse(meta.yearMonth.substring(4, 6));

      final monthKlines = await _resolveStorage(dataType).loadMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
      );

      // Filter by date range
      for (final kline in monthKlines) {
        if (dateRange.contains(kline.datetime)) {
          result.add(kline);
        }
      }
    }

    // Sort by datetime
    result.sort((a, b) => a.datetime.compareTo(b.datetime));

    return result;
  }

  /// Delete old K-line data
  ///
  /// Deletes all metadata and files for a stock before the specified date.
  Future<void> deleteOldData({
    required String stockCode,
    required KLineDataType dataType,
    required DateTime beforeDate,
  }) async {
    final database = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Get metadata for old files
    final metadata = await getMetadata(
      stockCode: stockCode,
      dataType: dataType,
    );

    final filesToDelete = <String>[];
    final metadataToDelete = <String>[];

    for (final meta in metadata) {
      if (meta.endDate == null) continue;

      if (meta.endDate!.isBefore(beforeDate)) {
        filesToDelete.add(meta.filePath);
        metadataToDelete.add(meta.yearMonth);
      }
    }

    // Delete metadata in transaction
    await database.transaction((txn) async {
      // Delete metadata from database
      for (final yearMonth in metadataToDelete) {
        await txn.delete(
          'kline_files',
          where: 'stock_code = ? AND data_type = ? AND year_month = ?',
          whereArgs: [stockCode, dataType.name, yearMonth],
        );
      }

      // Increment data version if anything was deleted
      if (metadataToDelete.isNotEmpty) {
        final currentVersionRows = await txn.query(
          'data_versions',
          columns: ['version'],
          orderBy: 'id DESC',
          limit: 1,
        );

        final currentVersion = currentVersionRows.isEmpty
            ? 1
            : (currentVersionRows.first['version'] as int);
        final newVersion = currentVersion + 1;

        await txn.insert('data_versions', {
          'version': newVersion,
          'description':
              'Deleted old K-line data for $stockCode before $beforeDate',
          'created_at': now,
        });
      }
    });

    // Delete files from disk after transaction commits
    for (final filePath in filesToDelete) {
      final file = File(filePath);
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Log but don't fail - orphaned files acceptable
        debugPrint('Warning: Failed to delete file $filePath: $e');
      }
    }

    if (metadataToDelete.isNotEmpty) {
      _invalidateTradingDateRangeCache();
    }
  }

  /// Get the current data version
  Future<int> getCurrentVersion() async {
    return await _db.getCurrentVersion();
  }

  /// Get all unique stock codes for a given data type
  Future<List<String>> getAllStockCodes({
    required KLineDataType dataType,
  }) async {
    final database = await _db.database;
    final rows = await database.query(
      'kline_files',
      columns: ['DISTINCT stock_code'],
      where: 'data_type = ?',
      whereArgs: [dataType.name],
    );

    return rows.map((row) => row['stock_code'] as String).toList();
  }

  /// 获取交易日列表（从日K数据推断）
  ///
  /// 某天只要有任意股票有日K数据，就认为是交易日
  Future<List<DateTime>> getTradingDates(DateRange range) async {
    final normalizedRange = _normalizeToDayRange(range);
    final currentVersion = await getCurrentVersion();
    _syncTradingDateCacheVersion(currentVersion);

    final cacheKey = _buildTradingDateCacheKey(
      startDay: DateTime(
        normalizedRange.start.year,
        normalizedRange.start.month,
        normalizedRange.start.day,
      ),
      endDay: DateTime(
        normalizedRange.end.year,
        normalizedRange.end.month,
        normalizedRange.end.day,
      ),
      dataVersion: currentVersion,
    );

    final cached = _tradingDateRangeCache[cacheKey];
    if (cached != null) {
      return List<DateTime>.from(cached);
    }

    final inFlight = _tradingDateRangeInFlight[cacheKey];
    if (inFlight != null) {
      return List<DateTime>.from(await inFlight);
    }

    final loadFuture = _computeTradingDates(normalizedRange);
    _tradingDateRangeInFlight[cacheKey] = loadFuture;

    try {
      final computed = await loadFuture;
      final materialized = List<DateTime>.unmodifiable(computed);
      if (_tradingDateCacheVersion == currentVersion) {
        _cacheTradingDateRange(cacheKey, materialized);
      }
      return List<DateTime>.from(materialized);
    } finally {
      _tradingDateRangeInFlight.remove(cacheKey);
    }
  }

  Future<List<DateTime>> _computeTradingDates(DateRange range) async {
    final stockCodes = await getAllStockCodes(dataType: KLineDataType.daily);
    if (stockCodes.isEmpty) return [];

    final tradingDates = <DateTime>{};

    for (final stockCode in stockCodes) {
      final klines = await loadKlineData(
        stockCode: stockCode,
        dataType: KLineDataType.daily,
        dateRange: range,
      );
      for (final kline in klines) {
        tradingDates.add(
          DateTime(
            kline.datetime.year,
            kline.datetime.month,
            kline.datetime.day,
          ),
        );
      }
    }

    final sorted = tradingDates.toList()..sort();
    return sorted;
  }

  DateRange _normalizeToDayRange(DateRange range) {
    final startDay = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final endDay = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
      999,
    );
    return DateRange(startDay, endDay);
  }

  String _buildTradingDateCacheKey({
    required DateTime startDay,
    required DateTime endDay,
    required int dataVersion,
  }) {
    return '${startDay.millisecondsSinceEpoch}_'
        '${endDay.millisecondsSinceEpoch}_$dataVersion';
  }

  void _syncTradingDateCacheVersion(int currentVersion) {
    if (_tradingDateCacheVersion == currentVersion) {
      return;
    }
    _invalidateTradingDateRangeCache(nextVersion: currentVersion);
  }

  void _cacheTradingDateRange(String key, List<DateTime> dates) {
    if (_tradingDateRangeCache.containsKey(key)) {
      _tradingDateRangeCache[key] = dates;
      return;
    }

    while (_tradingDateRangeCache.length >= _maxTradingDateRangeCacheEntries) {
      _tradingDateRangeCache.remove(_tradingDateRangeCache.keys.first);
    }
    _tradingDateRangeCache[key] = dates;
  }

  void _invalidateTradingDateRangeCache({int? nextVersion}) {
    _tradingDateRangeCache.clear();
    _tradingDateRangeInFlight.clear();
    _tradingDateCacheVersion = nextVersion;
  }

  /// 统计指定日期的K线数量
  ///
  /// [stockCode] 股票代码
  /// [dataType] 数据类型
  /// [date] 日期（只使用年月日部分）
  Future<int> countBarsForDate({
    required String stockCode,
    required KLineDataType dataType,
    required DateTime date,
  }) async {
    if (dataType == KLineDataType.daily) {
      await _prepareDailyStorageIfNeeded();
    }
    final dateOnly = DateTime(date.year, date.month, date.day);
    final nextDay = dateOnly.add(const Duration(days: 1));

    // Load the month's data
    final klines = await _resolveStorage(dataType).loadMonthlyKlineFile(
      stockCode,
      dataType,
      date.year,
      date.month,
    );

    // Count bars for the specific date
    return klines.where((k) {
      return !k.datetime.isBefore(dateOnly) && k.datetime.isBefore(nextDay);
    }).length;
  }

  /// 批量统计日期范围内每天的K线数量
  ///
  /// 仅返回有数据的日期，缺失日期不在结果中（调用方可按需补 0）
  Future<Map<DateTime, int>> countBarsByDateInRange({
    required String stockCode,
    required KLineDataType dataType,
    required DateRange dateRange,
  }) async {
    final normalizedRange = DateRange(
      DateTime(
        dateRange.start.year,
        dateRange.start.month,
        dateRange.start.day,
      ),
      DateTime(
        dateRange.end.year,
        dateRange.end.month,
        dateRange.end.day,
        23,
        59,
        59,
        999,
        999,
      ),
    );

    final klines = await loadKlineData(
      stockCode: stockCode,
      dataType: dataType,
      dateRange: normalizedRange,
    );

    final result = <DateTime, int>{};
    for (final kline in klines) {
      final dateOnly = DateTime(
        kline.datetime.year,
        kline.datetime.month,
        kline.datetime.day,
      );
      result.update(dateOnly, (count) => count + 1, ifAbsent: () => 1);
    }

    return result;
  }
}
