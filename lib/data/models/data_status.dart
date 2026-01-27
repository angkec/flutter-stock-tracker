// lib/data/models/data_status.dart

import 'date_range.dart';

/// 数据状态
sealed class DataStatus {
  const DataStatus();
}

/// 就绪
class DataReady extends DataStatus {
  final int dataVersion;
  const DataReady(this.dataVersion);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataReady &&
          runtimeType == other.runtimeType &&
          dataVersion == other.dataVersion;

  @override
  int get hashCode => dataVersion.hashCode;
}

/// 数据过时
class DataStale extends DataStatus {
  final List<String> missingStockCodes;
  final DateRange missingRange;

  DataStale({
    required List<String> missingStockCodes,
    required this.missingRange,
  }) : missingStockCodes = List.unmodifiable(missingStockCodes);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataStale &&
          runtimeType == other.runtimeType &&
          _listEquals(missingStockCodes, other.missingStockCodes) &&
          missingRange == other.missingRange;

  @override
  int get hashCode =>
      _listHashCode(missingStockCodes) ^ missingRange.hashCode;

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int _listHashCode(List<String> list) {
    int hash = 0;
    for (final item in list) {
      hash ^= item.hashCode;
    }
    return hash;
  }
}

/// 拉取中
class DataFetching extends DataStatus {
  final int current;
  final int total;
  final String currentStock;

  const DataFetching({
    required this.current,
    required this.total,
    required this.currentStock,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataFetching &&
          runtimeType == other.runtimeType &&
          current == other.current &&
          total == other.total &&
          currentStock == other.currentStock;

  @override
  int get hashCode =>
      current.hashCode ^ total.hashCode ^ currentStock.hashCode;
}

/// 错误
class DataError extends DataStatus {
  final String message;
  final Exception? exception;

  const DataError(this.message, [this.exception]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataError &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          exception == other.exception;

  @override
  int get hashCode => message.hashCode ^ exception.hashCode;
}
