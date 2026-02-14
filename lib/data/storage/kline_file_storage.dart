// lib/data/storage/kline_file_storage.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';

class KLineAppendResult {
  final bool changed;
  final DateTime? startDate;
  final DateTime? endDate;
  final int recordCount;
  final String filePath;
  final int fileSize;

  const KLineAppendResult({
    required this.changed,
    required this.startDate,
    required this.endDate,
    required this.recordCount,
    required this.filePath,
    required this.fileSize,
  });
}

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

  /// Get the file path for a monthly K-line file (sync - only for testing)
  String getFilePath(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) {
    final baseDirectory = _getBaseSyncDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
    return '$baseDirectory/$fileName';
  }

  /// Get the file path for a monthly K-line file (async - for production)
  Future<String> getFilePathAsync(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final baseDirectory = await _getBaseDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
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
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
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

    // Ensure directory exists
    final dir = Directory(baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
    final filePath = '$baseDir/$fileName';

    // Make temp filename unique to avoid race conditions
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final tempPath =
        '$baseDir/${stockCode}_${dataType.name}_$yearMonth.$timestamp.tmp';

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
    try {
      await tempFile.writeAsBytes(compressedData);

      // Append checksum to the file
      await tempFile.writeAsString('\n$checksum', mode: FileMode.append);

      // Atomic rename
      await tempFile.rename(filePath);
    } catch (e) {
      // Clean up on any error
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  /// Append K-line data to a monthly file (handles deduplication)
  ///
  /// Returns append summary so caller can avoid redundant file reload.
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

    // Load existing data
    final existingKlines = await loadMonthlyKlineFile(
      stockCode,
      dataType,
      year,
      month,
    );

    final mergeResult = _mergeAndDeduplicate(existingKlines, newKlines);

    final filePath = await getFilePathAsync(stockCode, dataType, year, month);

    if (mergeResult.changed) {
      // Save back only when content actually changes.
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
  Future<void> deleteMonthlyFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final baseDir = await _getBaseDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.gz';
    final filePath = '$baseDir/$fileName';

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Merge and deduplicate K-lines by datetime.
  ///
  /// Existing bars are expected to be ascending by datetime (storage invariant).
  /// Incoming bars are deduplicated then sorted once, and merged in linear time.
  _KLineMergeResult _mergeAndDeduplicate(
    List<KLine> existing,
    List<KLine> newKlines,
  ) {
    final normalizedExisting = _ensureSorted(existing);
    final normalizedIncoming = _deduplicateAndSortIncoming(newKlines);

    if (normalizedIncoming.isEmpty) {
      return _KLineMergeResult(changed: false, merged: normalizedExisting);
    }

    if (normalizedExisting.isEmpty) {
      return _KLineMergeResult(changed: true, merged: normalizedIncoming);
    }

    final merged = <KLine>[];
    var changed = false;
    var existingIndex = 0;
    var incomingIndex = 0;

    while (existingIndex < normalizedExisting.length &&
        incomingIndex < normalizedIncoming.length) {
      final existingBar = normalizedExisting[existingIndex];
      final incomingBar = normalizedIncoming[incomingIndex];
      final compare = existingBar.datetime.compareTo(incomingBar.datetime);

      if (compare < 0) {
        merged.add(existingBar);
        existingIndex++;
        continue;
      }

      if (compare > 0) {
        merged.add(incomingBar);
        incomingIndex++;
        changed = true;
        continue;
      }

      if (!_isSameKLine(existingBar, incomingBar)) {
        changed = true;
      }
      merged.add(incomingBar);
      existingIndex++;
      incomingIndex++;
    }

    while (existingIndex < normalizedExisting.length) {
      merged.add(normalizedExisting[existingIndex]);
      existingIndex++;
    }

    while (incomingIndex < normalizedIncoming.length) {
      merged.add(normalizedIncoming[incomingIndex]);
      incomingIndex++;
      changed = true;
    }

    return _KLineMergeResult(changed: changed, merged: merged);
  }

  List<KLine> _deduplicateAndSortIncoming(List<KLine> newKlines) {
    final byDatetime = <DateTime, KLine>{
      for (final kline in newKlines) kline.datetime: kline,
    };

    final deduplicated = byDatetime.values.toList(growable: false)
      ..sort((left, right) => left.datetime.compareTo(right.datetime));

    return deduplicated;
  }

  List<KLine> _ensureSorted(List<KLine> klines) {
    if (klines.length < 2) {
      return klines;
    }

    for (var index = 1; index < klines.length; index++) {
      if (klines[index - 1].datetime.isAfter(klines[index].datetime)) {
        final sorted = List<KLine>.from(klines);
        sorted.sort((left, right) => left.datetime.compareTo(right.datetime));
        return sorted;
      }
    }

    return klines;
  }

  bool _isSameKLine(KLine left, KLine right) {
    return left.datetime == right.datetime &&
        left.open == right.open &&
        left.close == right.close &&
        left.high == right.high &&
        left.low == right.low &&
        left.volume == right.volume &&
        left.amount == right.amount;
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
    // Extract and validate checksum
    final lastNewlineIndex = compressedData.lastIndexOf(10); // ASCII for \n
    if (lastNewlineIndex == -1) {
      throw Exception('No checksum found in file');
    }

    final dataToDecompress = compressedData.sublist(0, lastNewlineIndex);
    final fileChecksum = String.fromCharCodes(
      compressedData.sublist(lastNewlineIndex + 1),
    ).trim();
    final calculatedChecksum = sha256.convert(dataToDecompress).toString();

    if (fileChecksum != calculatedChecksum) {
      throw Exception('Checksum validation failed - file may be corrupted');
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
}

class _KLineMergeResult {
  final bool changed;
  final List<KLine> merged;

  const _KLineMergeResult({required this.changed, required this.merged});
}

/// Helper class for passing data to compute function
class _PrepareCompressionData {
  final List<KLine> klines;
  final String checksum;

  _PrepareCompressionData({required this.klines, required this.checksum});
}
