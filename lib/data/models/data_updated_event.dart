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
}
