/// 行业统计数据
class IndustryStats {
  final String name;
  final int upCount;      // 上涨数量
  final int downCount;    // 下跌数量
  final int flatCount;    // 平盘数量
  final int ratioAbove;   // 量比>1 数量
  final int ratioBelow;   // 量比<1 数量

  const IndustryStats({
    required this.name,
    required this.upCount,
    required this.downCount,
    required this.flatCount,
    required this.ratioAbove,
    required this.ratioBelow,
  });

  /// 总股票数
  int get total => upCount + downCount + flatCount;

  /// 量比排序值 (>1数量 / <1数量)，<1数量为0时返回无穷大
  double get ratioSortValue {
    if (ratioBelow == 0) return double.infinity;
    return ratioAbove / ratioBelow;
  }
}
