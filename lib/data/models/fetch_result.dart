// lib/data/models/fetch_result.dart

class FetchResult {
  final int totalStocks;
  final int successCount;
  final int failureCount;
  final Map<String, String> errors; // stockCode -> errorMessage
  final int totalRecords;
  final Duration duration;

  const FetchResult({
    required this.totalStocks,
    required this.successCount,
    required this.failureCount,
    required this.errors,
    required this.totalRecords,
    required this.duration,
  });

  bool get isSuccess => failureCount == 0;
  double get successRate => totalStocks > 0 ? successCount / totalStocks : 0.0;

  @override
  String toString() {
    return 'FetchResult(total: $totalStocks, success: $successCount, '
        'failed: $failureCount, records: $totalRecords, duration: $duration)';
  }
}
