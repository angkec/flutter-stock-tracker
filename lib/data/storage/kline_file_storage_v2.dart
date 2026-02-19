import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_append_result.dart';
import 'package:stock_rtwatcher/data/storage/kline_codec.dart';
import 'package:stock_rtwatcher/data/storage/kline_merge_helpers.dart';
import 'package:stock_rtwatcher/data/storage/kline_monthly_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// File storage for K-line data with monthly sharding (binary + zlib).
class KLineFileStorageV2 implements KLineMonthlyStorage {
  static const String _baseDir = 'market_data/klines_v2';

  final BinaryKLineCodec _codec;

  /// Base directory path (used for testing)
  String? _baseDirPath;

  /// Resolved base directory cache
  String? _resolvedBaseDirectory;

  KLineFileStorageV2({BinaryKLineCodec? codec})
      : _codec = codec ?? BinaryKLineCodec();

  /// Set base directory path for testing
  @override
  void setBaseDirPathForTesting(String path) {
    _baseDirPath = path;
    _resolvedBaseDirectory = path;
  }

  /// Initialize the file storage by creating base directory
  @override
  Future<void> initialize() async {
    final baseDirectory = await _getBaseDirectory();
    final dir = Directory(baseDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Get the file path for a monthly K-line file (sync - only for testing)
  String getFilePath(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) {
    final baseDirectory = _getBaseSyncDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.zlib';
    return '$baseDirectory/$fileName';
  }

  /// Get the file path for a monthly K-line file (async - for production)
  @override
  Future<String> getFilePathAsync(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final baseDirectory = await _getBaseDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.zlib';
    return '$baseDirectory/$fileName';
  }

  /// Get base directory synchronously
  String _getBaseSyncDirectory() {
    if (_baseDirPath != null) {
      return _baseDirPath!;
    }
    throw UnsupportedError(
      'Use _getBaseDirectory() for async operations or initialize() first',
    );
  }

  /// Get base directory asynchronously
  Future<String> _getBaseDirectory() async {
    if (_resolvedBaseDirectory != null) {
      return _resolvedBaseDirectory!;
    }

    if (_baseDirPath != null) {
      _resolvedBaseDirectory = _baseDirPath!;
      return _resolvedBaseDirectory!;
    }

    final appDocsDir = await getApplicationDocumentsDirectory();
    _resolvedBaseDirectory = '${appDocsDir.path}/$_baseDir';
    return _resolvedBaseDirectory!;
  }

  /// Get base directory path for external data-layer helpers.
  @override
  Future<String> getBaseDirectoryPath() async {
    return _getBaseDirectory();
  }

  /// Load a monthly K-line file from disk
  @override
  Future<List<KLine>> loadMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final baseDir = await _getBaseDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.zlib';
    final filePath = '$baseDir/$fileName';
    final legacyFileName = '${stockCode}_${dataType.name}_$yearMonth.bin.z';
    final legacyFilePath = '$baseDir/$legacyFileName';

    final file = File(filePath);
    final legacyFile = File(legacyFilePath);
    final sourceFile = await file.exists()
        ? file
        : (await legacyFile.exists() ? legacyFile : null);
    if (sourceFile == null) {
      return [];
    }

    try {
      final data = await sourceFile.readAsBytes();
      final decoded = _codec.decode(data);
      if (sourceFile.path == legacyFilePath) {
        await _migrateLegacyFile(sourceFile, filePath, data);
      }
      return decoded;
    } catch (e) {
      throw Exception('Failed to load monthly K-line file: $e');
    }
  }

  /// Save K-line data for a month atomically
  @override
  Future<void> saveMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> klines,
  ) async {
    if (klines.isEmpty) {
      return;
    }

    final baseDir = await _getBaseDirectory();

    // Ensure directory exists
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.zlib';
    final filePath = '$baseDir/$fileName';

    // Make temp filename unique to avoid race conditions
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tempPath =
        '$baseDir/${stockCode}_${dataType.name}_$yearMonth.$timestamp.tmp';

    final encoded = _codec.encode(klines);

    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsBytes(encoded);
      await tempFile.rename(filePath);
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Append K-line data to a monthly file (handles deduplication)
  ///
  /// Returns append summary so caller can avoid redundant file reload.
  @override
  Future<KLineAppendResult?> appendKlineData(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> newKlines,
  ) async {
    if (newKlines.isEmpty) {
      return null;
    }

    final existingKlines = await loadMonthlyKlineFile(
      stockCode,
      dataType,
      year,
      month,
    );

    final mergeResult =
        KLineMergeHelper.mergeAndDeduplicate(existingKlines, newKlines);

    final filePath = await getFilePathAsync(stockCode, dataType, year, month);

    if (mergeResult.changed) {
      await saveMonthlyKlineFile(
        stockCode,
        dataType,
        year,
        month,
        mergeResult.merged,
      );
    }

    final file = File(filePath);
    final fileSize = await file.length();

    final merged = mergeResult.merged;
    final startDate = merged.isEmpty ? null : merged.first.datetime;
    final endDate = merged.isEmpty ? null : merged.last.datetime;

    return KLineAppendResult(
      changed: mergeResult.changed,
      startDate: startDate,
      endDate: endDate,
      recordCount: merged.length,
      filePath: filePath,
      fileSize: fileSize,
    );
  }

  /// Delete a monthly K-line file
  @override
  Future<void> deleteMonthlyFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final baseDir = await _getBaseDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.zlib';
    final filePath = '$baseDir/$fileName';
    final legacyFileName = '${stockCode}_${dataType.name}_$yearMonth.bin.z';
    final legacyFilePath = '$baseDir/$legacyFileName';

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    final legacyFile = File(legacyFilePath);
    if (await legacyFile.exists()) {
      await legacyFile.delete();
    }
  }

  Future<void> _migrateLegacyFile(
    File legacyFile,
    String newFilePath,
    List<int> encoded,
  ) async {
    final newFile = File(newFilePath);
    if (await newFile.exists()) {
      return;
    }
    try {
      await legacyFile.rename(newFilePath);
    } catch (_) {
      try {
        await newFile.writeAsBytes(encoded);
        if (await legacyFile.exists()) {
          await legacyFile.delete();
        }
      } catch (_) {
        // Migration is best-effort; decoding succeeded so keep data in memory.
      }
    }
  }

  @visibleForTesting
  Future<void> migrateLegacyFileForTesting(
    File legacyFile,
    String newFilePath,
    List<int> encoded,
  ) {
    return _migrateLegacyFile(legacyFile, newFilePath, encoded);
  }
}
