/// 每日量比数据
class DailyRatio {
  final DateTime date;
  final double? ratio; // null 表示无法计算（涨停/跌停等）

  DailyRatio({
    required this.date,
    this.ratio,
  });
}
