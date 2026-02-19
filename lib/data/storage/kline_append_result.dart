// lib/data/storage/kline_append_result.dart

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
