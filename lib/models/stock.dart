/// 股票基本信息
class Stock {
  final String code;
  final String name;
  final int market; // 0=深圳, 1=上海
  final int volUnit;
  final int decimalPoint;
  final double preClose;

  Stock({
    required this.code,
    required this.name,
    required this.market,
    this.volUnit = 100,
    this.decimalPoint = 2,
    this.preClose = 0.0,
  });

  /// 判断是否为有效A股代码
  bool get isValidAStock {
    if (code.length != 6) return false;
    final validPrefixes = [
      '000', '001', '002', '003', // 深圳主板
      '300', '301', // 创业板
      '600', '601', '603', '605', // 上海主板
      '688', // 科创板
    ];
    return validPrefixes.any((p) => code.startsWith(p));
  }

  /// 判断是否为ST股票
  bool get isST => name.contains('ST');

  /// 获取涨跌停幅度
  double get limitPercent {
    if (isST) return 0.05;
    if (code.startsWith('300') || code.startsWith('301') || code.startsWith('688')) {
      return 0.20;
    }
    return 0.10;
  }
}
