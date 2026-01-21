import 'package:stock_rtwatcher/models/industry_trend.dart';

/// 行业排序模式
enum IndustrySortMode {
  ratioPercent, // 当前量比>1占比（默认）
  trendSlope, // 趋势斜率（近7天上升/下降幅度）
  todayChange, // 今日变化
}

/// 计算趋势斜率（使用最近7个数据点的线性回归）
/// 返回每天的变化量（正值表示上升趋势，负值表示下降趋势）
double calculateTrendSlope(List<double> data) {
  if (data.isEmpty || data.length < 2) return 0.0;

  // 使用最近7个数据点
  final recentData = data.length > 7 ? data.sublist(data.length - 7) : data;
  final n = recentData.length;

  // 使用线性回归计算斜率
  // y = mx + b, 其中 x 是索引 (0, 1, 2, ..., n-1)
  double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
  for (int i = 0; i < n; i++) {
    sumX += i;
    sumY += recentData[i];
    sumXY += i * recentData[i];
    sumX2 += i * i;
  }

  // 斜率公式: m = (n*sumXY - sumX*sumY) / (n*sumX2 - sumX*sumX)
  final denominator = n * sumX2 - sumX * sumX;
  if (denominator == 0) return 0.0;

  return (n * sumXY - sumX * sumY) / denominator;
}

/// 计算今日变化（与昨日对比）
/// 返回今日 ratioAbovePercent 与昨日的差值
double calculateTodayChange(
  DailyRatioPoint? today,
  List<DailyRatioPoint> historical,
) {
  if (today == null) return 0.0;

  if (historical.isEmpty) {
    // 无历史数据，返回今日值本身
    return today.ratioAbovePercent;
  }

  // 找到最近一天的数据（按日期排序后取最后一个）
  final sorted = List<DailyRatioPoint>.from(historical)
    ..sort((a, b) => a.date.compareTo(b.date));
  final yesterday = sorted.last;

  return today.ratioAbovePercent - yesterday.ratioAbovePercent;
}

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

  /// 量比>1股票占比 (0-100)
  double get ratioAbovePercent {
    if (total == 0) return 0.0;
    return ratioAbove / total * 100;
  }
}
