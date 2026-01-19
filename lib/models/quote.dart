/// 实时行情数据
class Quote {
  final int market;
  final String code;
  final double price;
  final double lastClose;
  final double open;
  final double high;
  final double low;
  final int volume;
  final double amount;

  Quote({
    required this.market,
    required this.code,
    required this.price,
    required this.lastClose,
    required this.open,
    required this.high,
    required this.low,
    required this.volume,
    required this.amount,
  });

  /// 涨跌幅 (%)
  double get changePercent {
    if (lastClose == 0) return 0;
    return (price - lastClose) / lastClose * 100;
  }

  /// 涨跌额
  double get changeAmount => price - lastClose;
}
