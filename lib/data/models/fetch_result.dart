// lib/data/models/fetch_result.dart

class FetchResult {
  final int totalStocks;
  final int successCount;
  final int failureCount;
  final Map<String, String> errors; // stockCode -> errorMessage
  final int totalRecords;
  final Duration duration;

  FetchResult({
    required this.totalStocks,
    required this.successCount,
    required this.failureCount,
    required Map<String, String> errors,
    required this.totalRecords,
    required this.duration,
  }) : errors = Map.unmodifiable(errors) {
    if (totalStocks < 0) {
      throw ArgumentError('totalStocks must be non-negative. Got: $totalStocks');
    }
    if (successCount < 0) {
      throw ArgumentError('successCount must be non-negative. Got: $successCount');
    }
    if (failureCount < 0) {
      throw ArgumentError('failureCount must be non-negative. Got: $failureCount');
    }
    if (totalRecords < 0) {
      throw ArgumentError('totalRecords must be non-negative. Got: $totalRecords');
    }
  }

  bool get isSuccess => failureCount == 0;
  double get successRate => totalStocks > 0 ? successCount / totalStocks : 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FetchResult &&
          runtimeType == other.runtimeType &&
          totalStocks == other.totalStocks &&
          successCount == other.successCount &&
          failureCount == other.failureCount &&
          _mapEquals(errors, other.errors) &&
          totalRecords == other.totalRecords &&
          duration == other.duration;

  @override
  int get hashCode =>
      totalStocks.hashCode ^
      successCount.hashCode ^
      failureCount.hashCode ^
      _mapHashCode(errors) ^
      totalRecords.hashCode ^
      duration.hashCode;

  bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  int _mapHashCode(Map<String, String> map) {
    int hash = 0;
    for (final entry in map.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }

  @override
  String toString() {
    return 'FetchResult(total: $totalStocks, success: $successCount, '
        'failed: $failureCount, records: $totalRecords, duration: $duration)';
  }
}
