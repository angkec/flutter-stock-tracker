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

/// 行业筛选条件
class IndustryFilter {
  /// 连续上升天数筛选（null表示不筛选）
  final int? consecutiveRisingDays;

  /// 今日量比占比最小值筛选（null表示不筛选）
  final double? minRatioAbovePercent;

  const IndustryFilter({
    this.consecutiveRisingDays,
    this.minRatioAbovePercent,
  });

  /// 是否有激活的筛选条件
  bool get hasActiveFilters =>
      consecutiveRisingDays != null || minRatioAbovePercent != null;

  /// 复制并更新筛选条件
  IndustryFilter copyWith({
    int? consecutiveRisingDays,
    double? minRatioAbovePercent,
    bool clearConsecutiveRisingDays = false,
    bool clearMinRatioAbovePercent = false,
  }) {
    return IndustryFilter(
      consecutiveRisingDays: clearConsecutiveRisingDays
          ? null
          : consecutiveRisingDays ?? this.consecutiveRisingDays,
      minRatioAbovePercent: clearMinRatioAbovePercent
          ? null
          : minRatioAbovePercent ?? this.minRatioAbovePercent,
    );
  }
}

/// 计算连续上升天数（从最近一天往前数）
/// 返回连续上升的天数（每天 ratioAbovePercent 大于前一天）
int countConsecutiveRisingDays(List<double> data) {
  if (data.length < 2) return 0;

  int count = 0;
  // 从最后往前检查
  for (int i = data.length - 1; i > 0; i--) {
    if (data[i] > data[i - 1]) {
      count++;
    } else {
      break;
    }
  }

  return count;
}

/// 检查趋势数据是否满足连续上升天数筛选条件
bool filterMatchesConsecutiveRising(List<double> trendData, int? threshold) {
  if (threshold == null) return true;
  return countConsecutiveRisingDays(trendData) >= threshold;
}

/// 检查今日量比占比是否满足最小值筛选条件
bool filterMatchesMinRatioPercent(double? todayRatioPercent, double? threshold) {
  if (threshold == null) return true;
  if (todayRatioPercent == null) return false;
  return todayRatioPercent >= threshold;
}
