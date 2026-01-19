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
}
