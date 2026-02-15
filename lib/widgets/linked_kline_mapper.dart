import 'package:stock_rtwatcher/models/kline.dart';

class PriceRange {
  final double minPrice;
  final double maxPrice;

  const PriceRange(this.minPrice, this.maxPrice);
}

class LinkedKlineMapper {
  static int? findWeeklyIndexForDailyDate({
    required List<KLine> weeklyBars,
    required DateTime dailyDate,
  }) {
    if (weeklyBars.isEmpty) {
      return null;
    }

    final dailyWeekKey = _weekKey(dailyDate);
    for (var i = 0; i < weeklyBars.length; i++) {
      if (_weekKey(weeklyBars[i].datetime) == dailyWeekKey) {
        return i;
      }
    }
    return null;
  }

  static int? findDailyIndexForWeeklyDate({
    required List<KLine> dailyBars,
    required DateTime weeklyDate,
  }) {
    if (dailyBars.isEmpty) {
      return null;
    }

    final weeklyKey = _weekKey(weeklyDate);
    int? latestIndex;
    DateTime? latestDate;

    for (var i = 0; i < dailyBars.length; i++) {
      final day = dailyBars[i].datetime;
      if (_weekKey(day) != weeklyKey) {
        continue;
      }
      if (latestDate == null || day.isAfter(latestDate)) {
        latestDate = day;
        latestIndex = i;
      }
    }

    return latestIndex;
  }

  static PriceRange ensurePriceVisible({
    required double minPrice,
    required double maxPrice,
    required double anchorPrice,
    double paddingRatio = 0.08,
    double minSpan = 0.01,
  }) {
    if (anchorPrice >= minPrice && anchorPrice <= maxPrice) {
      return PriceRange(minPrice, maxPrice);
    }

    final expandedMin = anchorPrice < minPrice ? anchorPrice : minPrice;
    final expandedMax = anchorPrice > maxPrice ? anchorPrice : maxPrice;
    final span = (expandedMax - expandedMin).clamp(minSpan, double.infinity);
    final padding = span * paddingRatio;

    return PriceRange(expandedMin - padding, expandedMax + padding);
  }

  static int ensureIndexVisible({
    required int startIndex,
    required int visibleCount,
    required int targetIndex,
    required int totalCount,
  }) {
    if (totalCount <= 0) {
      return 0;
    }

    final safeVisible = visibleCount.clamp(1, totalCount);
    var nextStart = startIndex.clamp(0, totalCount - safeVisible);

    if (targetIndex < nextStart) {
      nextStart = targetIndex;
    } else if (targetIndex >= nextStart + safeVisible) {
      nextStart = targetIndex - safeVisible + 1;
    }

    return nextStart.clamp(0, totalCount - safeVisible);
  }

  static Set<int> findWeeklyBoundaryIndices({
    required List<KLine> bars,
    required int startIndex,
    required int endIndex,
  }) {
    if (bars.isEmpty || startIndex >= endIndex) {
      return const {};
    }

    final boundaries = <int>{};
    final safeStart = startIndex.clamp(0, bars.length);
    final safeEnd = endIndex.clamp(safeStart, bars.length);

    for (var globalIndex = safeStart; globalIndex < safeEnd; globalIndex++) {
      if (globalIndex == 0) {
        boundaries.add(0);
        continue;
      }

      final currentKey = _weekKey(bars[globalIndex].datetime);
      final previousKey = _weekKey(bars[globalIndex - 1].datetime);
      if (currentKey != previousKey) {
        boundaries.add(globalIndex - safeStart);
      }
    }

    return boundaries;
  }

  static int? findIndexByDate({
    required List<KLine> bars,
    required DateTime date,
  }) {
    for (var i = 0; i < bars.length; i++) {
      final d = bars[i].datetime;
      if (d.year == date.year && d.month == date.month && d.day == date.day) {
        return i;
      }
    }
    return null;
  }

  static String _weekKey(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final monday = normalized.subtract(Duration(days: normalized.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  }
}
