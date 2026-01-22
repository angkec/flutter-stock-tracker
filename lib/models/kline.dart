/// K线数据
class KLine {
  final DateTime datetime;
  final double open;
  final double close;
  final double high;
  final double low;
  final double volume;
  final double amount;

  KLine({
    required this.datetime,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    required this.volume,
    required this.amount,
  });

  /// 判断是否为上涨K线 (close > open)
  bool get isUp => close > open;

  /// 判断是否为下跌K线 (close < open)
  bool get isDown => close < open;

  /// 转换为 JSON
  Map<String, dynamic> toJson() => {
    'datetime': datetime.toIso8601String(),
    'open': open,
    'close': close,
    'high': high,
    'low': low,
    'volume': volume,
    'amount': amount,
  };

  /// 从 JSON 创建
  factory KLine.fromJson(Map<String, dynamic> json) => KLine(
    datetime: DateTime.parse(json['datetime'] as String),
    open: (json['open'] as num).toDouble(),
    close: (json['close'] as num).toDouble(),
    high: (json['high'] as num).toDouble(),
    low: (json['low'] as num).toDouble(),
    volume: (json['volume'] as num).toDouble(),
    amount: (json['amount'] as num).toDouble(),
  );
}
