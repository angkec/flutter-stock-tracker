// lib/data/models/data_updated_event.dart

import 'kline_data_type.dart';
import 'date_range.dart';

/// 数据更新事件
class DataUpdatedEvent {
  final List<String> stockCodes;
  final DateRange dateRange;
  final KLineDataType dataType;
  final int dataVersion;

  const DataUpdatedEvent({
    required this.stockCodes,
    required this.dateRange,
    required this.dataType,
    required this.dataVersion,
  });

  @override
  String toString() {
    return 'DataUpdatedEvent(stocks: ${stockCodes.length}, '
        'range: $dateRange, type: ${dataType.name}, version: $dataVersion)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataUpdatedEvent &&
          runtimeType == other.runtimeType &&
          _listEquals(stockCodes, other.stockCodes) &&
          dateRange == other.dateRange &&
          dataType == other.dataType &&
          dataVersion == other.dataVersion;

  @override
  int get hashCode =>
      _listHashCode(stockCodes) ^
      dateRange.hashCode ^
      dataType.hashCode ^
      dataVersion.hashCode;

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
