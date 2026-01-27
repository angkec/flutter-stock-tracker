// lib/data/storage/kline_file_storage.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';

/// File storage for K-line data with monthly sharding
class KLineFileStorage {
  static const String _baseDir = 'market_data/klines';

  /// Base directory path (used for testing)
  String? _baseDirPath;

  /// Set base directory path for testing
  void setBaseDirPathForTesting(String path) {
    _baseDirPath = path;
  }

  /// Initialize the file storage by creating base directory
  Future<void> initialize() async {
    final baseDirectory = await _getBaseDirectory();
    final dir = Directory(baseDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Get the file path for a monthly K-line file
  String getFilePath(String stockCode, KLineDataType dataType, int year, int month) {
    final baseDirectory = _getBaseSyncDirectory();
    final yearMonth = '${year}${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
    return '$baseDirectory/$fileName';
  }

  /// Get the temporary file path for atomic writes
  String _getTempFilePath(String stockCode, KLineDataType dataType, int year, int month) {
    final baseDirectory = _getBaseSyncDirectory();
    final yearMonth = '${year}${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.tmp';
    return '$baseDirectory/$fileName';
  }

  /// Get base directory synchronously
  String _getBaseSyncDirectory() {
    if (_baseDirPath != null) {
      return _baseDirPath!;
    }
    throw UnsupportedError(
      'Use _getBaseDirectory() for async operations or initialize() first'
    );
  }

  /// Get base directory asynchronously
  Future<String> _getBaseDirectory() async {
    if (_baseDirPath != null) {
      return _baseDirPath!;
    }
    final appDocsDir = await getApplicationDocumentsDirectory();
    return '${appDocsDir.path}/$_baseDir';
  }

  /// Load a monthly K-line file from disk
  Future<List<KLine>> loadMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final baseDir = await _getBaseDirectory();
    final yearMonth = '${year}${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
    final filePath = '$baseDir/$fileName';

    final file = File(filePath);
    if (!await file.exists()) {
      return [];
    }

    try {
      final compressedData = await file.readAsBytes();
      final klines = await compute(_decompressAndDeserialize, compressedData);
      return klines;
    } catch (e) {
      throw Exception('Failed to load monthly K-line file: $e');
    }
  }

  /// Save K-line data for a month atomically
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
    final yearMonth = '${year}${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
    final filePath = '$baseDir/$fileName';
    final tempPath = '$baseDir/${stockCode}_${dataType.name}_$yearMonth.tmp';

    // Prepare data for compression
    final preparedData = _PrepareCompressionData(
      klines: klines,
      checksum: '', // Will be calculated after compression
    );

    // Compress data using isolate
    final compressedData = await compute(_serializeAndCompress, preparedData);

    // Calculate checksum
    final checksum = sha256.convert(compressedData).toString();

    // Write to temp file with checksum
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(compressedData);

    // Append checksum to the file
    await tempFile.writeAsString('\n$checksum', mode: FileMode.append);

    // Verify checksum by reading back
    final writtenData = await tempFile.readAsBytes();
    final lastNewlineIndex = writtenData.lastIndexOf(10); // ASCII for \n
    if (lastNewlineIndex != -1) {
      final fileChecksum = String.fromCharCodes(writtenData.sublist(lastNewlineIndex + 1)).trim();
      final dataChecksum = sha256.convert(writtenData.sublist(0, lastNewlineIndex)).toString();

      if (fileChecksum != dataChecksum) {
        await tempFile.delete();
        throw Exception('Checksum validation failed during save');
      }
    }

    // Atomic rename
    final finalFile = File(filePath);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(filePath);
  }

  /// Append K-line data to a monthly file (handles deduplication)
  Future<void> appendKlineData(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> newKlines,
  ) async {
    if (newKlines.isEmpty) {
      return;
    }

    // Load existing data
    final existingKlines = await loadMonthlyKlineFile(stockCode, dataType, year, month);

    // Merge and deduplicate
    final merged = _mergeAndDeduplicate(existingKlines, newKlines);

    // Save back
    await saveMonthlyKlineFile(stockCode, dataType, year, month, merged);
  }

  /// Delete a monthly K-line file
  Future<void> deleteMonthlyFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final baseDir = await _getBaseDirectory();
    final yearMonth = '${year}${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
    final filePath = '$baseDir/$fileName';

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Group K-lines by year-month
  Map<String, List<KLine>> _groupByMonth(List<KLine> klines) {
    final grouped = <String, List<KLine>>{};

    for (final kline in klines) {
      final yearMonth = '${kline.datetime.year}${kline.datetime.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(yearMonth, () => []).add(kline);
    }

    return grouped;
  }

  /// Merge and deduplicate K-lines by datetime
  List<KLine> _mergeAndDeduplicate(List<KLine> existing, List<KLine> newKlines) {
    final map = <DateTime, KLine>{};

    // Add existing
    for (final kline in existing) {
      map[kline.datetime] = kline;
    }

    // Add or overwrite with new
    for (final kline in newKlines) {
      map[kline.datetime] = kline;
    }

    // Sort by datetime
    final merged = map.values.toList();
    merged.sort((a, b) => a.datetime.compareTo(b.datetime));

    return merged;
  }

  /// Static method to serialize and compress K-line data
  static Uint8List _serializeAndCompress(_PrepareCompressionData data) {
    // Serialize to JSON
    final jsonList = data.klines.map((k) => k.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    final bytes = utf8.encode(jsonString);

    // Compress using gzip
    final encoder = GZipEncoder();
    final compressed = encoder.encode(bytes);

    return Uint8List.fromList(compressed!);
  }

  /// Static method to decompress and deserialize K-line data
  static List<KLine> _decompressAndDeserialize(Uint8List compressedData) {
    // Remove checksum from the end if present
    var dataToDecompress = compressedData;
    final lastNewlineIndex = compressedData.lastIndexOf(10); // ASCII for \n
    if (lastNewlineIndex != -1) {
      dataToDecompress = compressedData.sublist(0, lastNewlineIndex);
    }

    // Decompress
    final decoder = GZipDecoder();
    final decompressed = decoder.decodeBytes(dataToDecompress);

    // Deserialize from JSON
    final jsonString = utf8.decode(decompressed);
    final jsonList = jsonDecode(jsonString) as List<dynamic>;

    return jsonList
        .map((json) => KLine.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Calculate SHA256 checksum
  static String _calculateChecksum(Uint8List data) {
    return sha256.convert(data).toString();
  }
}

/// Helper class for passing data to compute function
class _PrepareCompressionData {
  final List<KLine> klines;
  final String checksum;

  _PrepareCompressionData({
    required this.klines,
    required this.checksum,
  });
}

