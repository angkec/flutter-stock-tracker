// lib/data/models/kline_data_type.dart

enum KLineDataType {
  oneMinute('1min'),
  daily('daily');

  final String name;
  const KLineDataType(this.name);

  static KLineDataType fromName(String name) {
    return values.firstWhere((e) => e.name == name);
  }
}
