// lib/data/storage/kline_metadata_manager.dart

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

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
  final MarketDatabase _db;
  final KLineFileStorage _fileStorage;

  KLineMetadataManager({
    MarketDatabase? database,
    KLineFileStorage? fileStorage,
  })  : _db = database ?? MarketDatabase(),
        _fileStorage = fileStorage ?? KLineFileStorage();

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
  }) async {
    if (newBars.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Group new bars by year-month
    final barsByMonth = <String, List<KLine>>{};
    for (final bar in newBars) {
      final yearMonth =
          '${bar.datetime.year}${bar.datetime.month.toString().padLeft(2, '0')}';
      barsByMonth.putIfAbsent(yearMonth, () => []).add(bar);
    }

    // Save to files (this will handle deduplication)
    final monthsUpdated = <String>{};
    for (final entry in barsByMonth.entries) {
      final yearMonth = entry.key;
      final klines = entry.value;

      final year = int.parse(yearMonth.substring(0, 4));
      final month = int.parse(yearMonth.substring(4, 6));

      try {
        await _fileStorage.appendKlineData(
          stockCode,
          dataType,
          year,
          month,
          klines,
        );

        monthsUpdated.add(yearMonth);
      } catch (e) {
        print('Failed to append K-line data for $stockCode $yearMonth: $e');
        // Continue with other months
      }
    }

    // Prepare metadata before transaction (avoid I/O inside transaction)
    final metadataMap = <String, ({DateTime startDate, DateTime endDate, int recordCount, int fileSize})>{};
    for (final yearMonth in monthsUpdated) {
      final year = int.parse(yearMonth.substring(0, 4));
      final month = int.parse(yearMonth.substring(4, 6));

      final monthBars =
          await _fileStorage.loadMonthlyKlineFile(stockCode, dataType, year, month);

      if (monthBars.isEmpty) continue;

      monthBars.sort((a, b) => a.datetime.compareTo(b.datetime));
      final startDate = monthBars.first.datetime;
      final endDate = monthBars.last.datetime;

      try {
        final filePath = _fileStorage.getFilePath(stockCode, dataType, year, month);
        final file = File(filePath);
        final fileSize = await file.length();

        metadataMap[yearMonth] = (
          startDate: startDate,
          endDate: endDate,
          recordCount: monthBars.length,
          fileSize: fileSize,
        );
      } catch (e) {
        print('Failed to get file size for $stockCode $yearMonth: $e');
        // Skip this month's metadata update
        continue;
      }
    }

    // Update metadata in transaction
    final database = await _db.database;
    await database.transaction((txn) async {
      for (final entry in metadataMap.entries) {
        final yearMonth = entry.key;
        final metadata = entry.value;

        final filePath = _fileStorage.getFilePath(
          stockCode,
          dataType,
          int.parse(yearMonth.substring(0, 4)),
          int.parse(yearMonth.substring(4, 6)),
        );

        // Insert or update metadata
        await txn.insert(
          'kline_files',
          {
            'stock_code': stockCode,
            'data_type': dataType.name,
            'year_month': yearMonth,
            'file_path': filePath,
            'start_date': metadata.startDate.millisecondsSinceEpoch,
            'end_date': metadata.endDate.millisecondsSinceEpoch,
            'record_count': metadata.recordCount,
            'checksum': null,
            'created_at': now,
            'updated_at': now,
            'file_size': metadata.fileSize,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

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
    });
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

      final monthKlines =
          await _fileStorage.loadMonthlyKlineFile(stockCode, dataType, year, month);

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
          'description': 'Deleted old K-line data for $stockCode before $beforeDate',
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
        print('Warning: Failed to delete file $filePath: $e');
      }
    }
  }
}
