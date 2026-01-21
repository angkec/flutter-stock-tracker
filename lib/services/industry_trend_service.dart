import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

/// 行业趋势服务
/// 计算每个行业的每日分钟涨跌量比趋势
class IndustryTrendService extends ChangeNotifier {
  static const String _storageKey = 'industry_trend_cache';
  static const int _maxCacheDays = 30;
  static const int _autoRefreshThreshold = 3; // 缺失天数 <= 3 天自动后台拉取

  Map<String, IndustryTrendData> _trendData = {};
  bool _isLoading = false;
  int _missingDays = 0;

  /// 按行业名索引的趋势数据
  Map<String, IndustryTrendData> get trendData => Map.unmodifiable(_trendData);

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 缺失天数
  int get missingDays => _missingDays;

  /// 获取某行业趋势
  IndustryTrendData? getTrend(String industry) => _trendData[industry];

  /// 从缓存加载数据
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _trendData = _deserializeCache(json);
        _cleanupOldData();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load industry trend cache: $e');
    }
  }

  /// 检查并增量更新
  /// 返回缺失天数
  /// 如果缺失天数 <= 3 天，自动后台拉取
  Future<int> checkAndRefresh(TdxPool pool, List<StockMonitorData> stocks) async {
    if (stocks.isEmpty) return 0;

    // 计算缺失天数
    final today = DateTime.now();
    final cachedDates = _getCachedDates();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);

    // 找出缺失的日期（不包括今天，今天实时计算）
    final missingDates = <DateTime>[];
    for (final date in tradingDays) {
      if (!_isSameDay(date, today) && !cachedDates.contains(_dateKey(date))) {
        missingDates.add(date);
      }
    }

    _missingDays = missingDates.length;
    notifyListeners();

    // 如果缺失天数 <= 阈值，自动后台拉取
    if (_missingDays > 0 && _missingDays <= _autoRefreshThreshold) {
      await fetchHistoricalData(pool, stocks, null);
    }

    return _missingDays;
  }

  /// 全量拉取历史数据
  /// [onProgress] 进度回调 (current, total)
  Future<void> fetchHistoricalData(
    TdxPool pool,
    List<StockMonitorData> stocks,
    void Function(int, int)? onProgress,
  ) async {
    if (stocks.isEmpty) return;
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      // 按行业分组股票
      final industryStocks = <String, List<StockMonitorData>>{};
      for (final stock in stocks) {
        final industry = stock.industry;
        if (industry != null && industry.isNotEmpty) {
          industryStocks.putIfAbsent(industry, () => []).add(stock);
        }
      }

      // 获取所有股票的分钟K线数据
      // category=8 是分钟K线，count=7200 约30天
      final stockList = stocks.map((s) => s.stock).toList();
      final allBars = await pool.batchGetSecurityBars(
        stocks: stockList,
        category: klineType1Min,
        start: 0,
        count: 7200,
        onProgress: onProgress,
      );

      // 计算每只股票每天的量比
      final stockDailyRatios = <int, Map<String, double>>{}; // stockIndex -> {dateKey -> ratio}
      final today = DateTime.now();

      for (var i = 0; i < allBars.length; i++) {
        final bars = allBars[i];
        if (bars.isEmpty) continue;

        // 按日期分组K线
        final dailyBars = _groupBarsByDate(bars);

        for (final entry in dailyBars.entries) {
          final dateKey = entry.key;
          final dayBars = entry.value;

          // 跳过今天（今天实时计算，不缓存）
          if (_isDateKeyToday(dateKey, today)) continue;

          // 计算该股票该天的量比
          final ratio = _calculateDailyRatio(dayBars);
          if (ratio != null) {
            stockDailyRatios.putIfAbsent(i, () => {})[dateKey] = ratio;
          }
        }
      }

      // 汇总每个行业每天的趋势数据
      final newTrendData = <String, IndustryTrendData>{};

      for (final entry in industryStocks.entries) {
        final industry = entry.key;
        final industryStockList = entry.value;

        // 收集该行业所有股票的所有日期
        final allDates = <String>{};
        for (final stock in industryStockList) {
          final stockIndex = stocks.indexOf(stock);
          if (stockIndex >= 0 && stockDailyRatios.containsKey(stockIndex)) {
            allDates.addAll(stockDailyRatios[stockIndex]!.keys);
          }
        }

        // 计算每个日期的行业趋势
        final points = <DailyRatioPoint>[];
        for (final dateKey in allDates) {
          var ratioAboveCount = 0;
          var totalStocks = 0;

          for (final stock in industryStockList) {
            final stockIndex = stocks.indexOf(stock);
            if (stockIndex < 0) continue;

            final ratios = stockDailyRatios[stockIndex];
            if (ratios == null || !ratios.containsKey(dateKey)) continue;

            totalStocks++;
            if (ratios[dateKey]! > 1.0) {
              ratioAboveCount++;
            }
          }

          if (totalStocks > 0) {
            final ratioAbovePercent = (ratioAboveCount / totalStocks) * 100;
            points.add(DailyRatioPoint(
              date: _parseDate(dateKey),
              ratioAbovePercent: ratioAbovePercent,
              totalStocks: totalStocks,
              ratioAboveCount: ratioAboveCount,
            ));
          }
        }

        if (points.isNotEmpty) {
          // 合并现有缓存数据
          final existingData = _trendData[industry];
          final mergedPoints = _mergePoints(existingData?.points ?? [], points);

          newTrendData[industry] = IndustryTrendData(
            industry: industry,
            points: mergedPoints,
          ).sortedByDate();
        }
      }

      // 更新数据
      _trendData = newTrendData;
      _cleanupOldData();
      _missingDays = 0;

      // 保存缓存
      await _save();

    } catch (e) {
      debugPrint('Failed to fetch historical data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 计算单只股票某天的分钟涨跌量比
  /// 上涨分钟总量 / 下跌分钟总量
  double? _calculateDailyRatio(List<KLine> dayBars) {
    if (dayBars.length < StockService.minBarsCount) {
      return null;
    }

    double upVolume = 0;
    double downVolume = 0;

    for (final bar in dayBars) {
      if (bar.isUp) {
        upVolume += bar.volume;
      } else if (bar.isDown) {
        downVolume += bar.volume;
      }
    }

    // 没有下跌分钟（可能是涨停）
    if (downVolume == 0) {
      return null;
    }

    // 没有上涨分钟（可能是跌停）
    if (upVolume == 0) {
      return null;
    }

    final ratio = upVolume / downVolume;

    // 量比过高或过低，可能是异常数据
    if (ratio > StockService.maxValidRatio || ratio < 1 / StockService.maxValidRatio) {
      return null;
    }

    return ratio;
  }

  /// 按日期分组K线
  Map<String, List<KLine>> _groupBarsByDate(List<KLine> bars) {
    final grouped = <String, List<KLine>>{};
    for (final bar in bars) {
      final dateKey = _dateKey(bar.datetime);
      grouped.putIfAbsent(dateKey, () => []).add(bar);
    }
    return grouped;
  }

  /// 获取日期键
  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 解析日期键
  DateTime _parseDate(String dateKey) {
    final parts = dateKey.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  /// 判断日期键是否为今天
  bool _isDateKeyToday(String dateKey, DateTime today) {
    return dateKey == _dateKey(today);
  }

  /// 判断两个日期是否为同一天
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 获取缓存中的所有日期
  Set<String> _getCachedDates() {
    final dates = <String>{};
    for (final data in _trendData.values) {
      for (final point in data.points) {
        dates.add(_dateKey(point.date));
      }
    }
    return dates;
  }

  /// 估算最近N个交易日
  /// 简单估算：排除周末，实际可能需要更精确的交易日历
  List<DateTime> _estimateTradingDays(DateTime from, int count) {
    final days = <DateTime>[];
    var current = from;
    var checked = 0;

    while (days.length < count && checked < count * 2) {
      current = current.subtract(const Duration(days: 1));
      checked++;

      // 跳过周末
      if (current.weekday == DateTime.saturday || current.weekday == DateTime.sunday) {
        continue;
      }

      days.add(DateTime(current.year, current.month, current.day));
    }

    return days;
  }

  /// 合并数据点，新数据覆盖旧数据
  List<DailyRatioPoint> _mergePoints(
    List<DailyRatioPoint> existing,
    List<DailyRatioPoint> newPoints,
  ) {
    final merged = <String, DailyRatioPoint>{};

    for (final point in existing) {
      merged[_dateKey(point.date)] = point;
    }

    for (final point in newPoints) {
      merged[_dateKey(point.date)] = point;
    }

    return merged.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 清理超过30天的旧数据
  void _cleanupOldData() {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxCacheDays));
    final cutoffKey = _dateKey(cutoff);

    final cleanedData = <String, IndustryTrendData>{};
    for (final entry in _trendData.entries) {
      final filteredPoints = entry.value.points
          .where((p) => _dateKey(p.date).compareTo(cutoffKey) >= 0)
          .toList();

      if (filteredPoints.isNotEmpty) {
        cleanedData[entry.key] = entry.value.copyWith(points: filteredPoints);
      }
    }

    _trendData = cleanedData;
  }

  /// 保存缓存到 SharedPreferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = _serializeCache();
      await prefs.setString(_storageKey, jsonEncode(json));
    } catch (e) {
      debugPrint('Failed to save industry trend cache: $e');
    }
  }

  /// 序列化缓存数据
  Map<String, dynamic> _serializeCache() {
    final data = <String, dynamic>{};
    for (final entry in _trendData.entries) {
      data[entry.key] = entry.value.toJson();
    }
    return {
      'version': 1,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 反序列化缓存数据
  Map<String, IndustryTrendData> _deserializeCache(Map<String, dynamic> json) {
    final result = <String, IndustryTrendData>{};

    // 检查版本
    final version = json['version'] as int? ?? 0;
    if (version != 1) {
      return result; // 版本不兼容，返回空数据
    }

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return result;

    for (final entry in data.entries) {
      try {
        result[entry.key] = IndustryTrendData.fromJson(entry.value as Map<String, dynamic>);
      } catch (e) {
        debugPrint('Failed to deserialize industry trend data for ${entry.key}: $e');
      }
    }

    return result;
  }
}
