/// 单日数据状态
enum DayDataStatus {
  /// 数据完整（分钟K线 >= 220）
  complete,

  /// 历史日期数据不完整（< 220，需要补全）
  incomplete,

  /// 完全没有数据
  missing,

  /// 当天，交易进行中（不视为缺失，不缓存）
  inProgress,
}

/// 日期缺失检测结果
class MissingDatesResult {
  /// 缺失的日期列表（完全没有数据）
  final List<DateTime> missingDates;

  /// 不完整的日期列表（数据 < 220，需要重新拉取）
  final List<DateTime> incompleteDates;

  /// 完整的日期列表
  final List<DateTime> completeDates;

  const MissingDatesResult({
    required this.missingDates,
    required this.incompleteDates,
    required this.completeDates,
  });

  /// 是否全部完整
  bool get isComplete => missingDates.isEmpty && incompleteDates.isEmpty;

  /// 需要拉取的日期（合并 missing + incomplete，已排序）
  List<DateTime> get datesToFetch =>
      [...missingDates, ...incompleteDates]..sort();

  /// 需要拉取的日期数量
  int get fetchCount => missingDates.length + incompleteDates.length;
}
