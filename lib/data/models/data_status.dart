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
}

/// 数据过时
class DataStale extends DataStatus {
  final List<String> missingStockCodes;
  final DateRange missingRange;

  const DataStale({
    required this.missingStockCodes,
    required this.missingRange,
  });
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
}

/// 错误
class DataError extends DataStatus {
  final String message;
  final Exception? exception;

  const DataError(this.message, [this.exception]);
}
