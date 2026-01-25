import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// 行业趋势服务
/// 计算每个行业的每日分钟涨跌量比趋势
class IndustryTrendService extends ChangeNotifier {
  static const String _storageKey = 'industry_trend_cache';
  static const int _maxCacheDays = 30;

  Map<String, IndustryTrendData> _trendData = {};
  final bool _isLoading = false;
  int _missingDays = 0;

  /// 按行业名索引的趋势数据
  Map<String, IndustryTrendData> get trendData => Map.unmodifiable(_trendData);

  /// 是否正在加载
  bool get isLoading => _isLoading;

  /// 缺失天数
  int get missingDays => _missingDays;

  /// 获取某行业趋势
  IndustryTrendData? getTrend(String industry) => _trendData[industry];

  /// 通知UI刷新（使用现有缓存数据重算）
  void refresh() => notifyListeners();

  /// 清空趋势缓存
  void clearCache() {
    _trendData = {};
    _missingDays = 0;
    notifyListeners();
  }

  /// 从历史K线数据重新计算趋势
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks,
  ) async {
    if (stocks.isEmpty) return;

    // 按行业分组股票
    final industryStocks = <String, List<StockMonitorData>>{};
    for (final stock in stocks) {
      final industry = stock.industry;
      if (industry != null && industry.isNotEmpty) {
        industryStocks.putIfAbsent(industry, () => []).add(stock);
      }
    }

    // 收集所有日期
    final allDates = <String>{};
    for (final stock in stocks) {
      final volumes = klineService.getDailyVolumes(stock.stock.code);
      allDates.addAll(volumes.keys);
    }

    // 计算每个行业每天的趋势
    final newTrendData = <String, IndustryTrendData>{};

    for (final entry in industryStocks.entries) {
      final industry = entry.key;
      final industryStockList = entry.value;
      final points = <DailyRatioPoint>[];

      for (final dateKey in allDates) {
        var ratioAboveCount = 0;
        var totalStocks = 0;

        for (final stock in industryStockList) {
          final volumes = klineService.getDailyVolumes(stock.stock.code);
          final vol = volumes[dateKey];
          if (vol == null) continue;
          if (vol.down <= 0) continue;

          totalStocks++;
          final ratio = vol.up / vol.down;
          if (ratio > 1.0 && ratio <= StockService.maxValidRatio) {
            ratioAboveCount++;
          }
        }

        if (totalStocks > 0) {
          final ratioAbovePercent = (ratioAboveCount / totalStocks) * 100;
          points.add(DailyRatioPoint(
            date: HistoricalKlineService.parseDate(dateKey),
            ratioAbovePercent: ratioAbovePercent,
            totalStocks: totalStocks,
            ratioAboveCount: ratioAboveCount,
          ));
        }
      }

      if (points.isNotEmpty) {
        points.sort((a, b) => a.date.compareTo(b.date));
        newTrendData[industry] = IndustryTrendData(
          industry: industry,
          points: points,
        );
      }
    }

    _trendData = newTrendData;
    _missingDays = 0;
    await _save();
    notifyListeners();
  }

  /// 计算今日实时行业趋势
  /// 使用股票现有的 ratio 字段（当前会话的分钟涨跌量比）
  /// 返回按行业分组的今日数据点
  Map<String, DailyRatioPoint> calculateTodayTrend(List<StockMonitorData> stocks) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final result = <String, DailyRatioPoint>{};

    // 按行业分组股票
    final industryStocks = <String, List<StockMonitorData>>{};
    for (final stock in stocks) {
      final industry = stock.industry;
      if (industry != null && industry.isNotEmpty) {
        industryStocks.putIfAbsent(industry, () => []).add(stock);
      }
    }

    // 计算每个行业的今日趋势
    for (final entry in industryStocks.entries) {
      final industry = entry.key;
      final industryStockList = entry.value;

      var ratioAboveCount = 0;
      final totalStocks = industryStockList.length;

      for (final stock in industryStockList) {
        if (stock.ratio > 1.0) {
          ratioAboveCount++;
        }
      }

      if (totalStocks > 0) {
        final ratioAbovePercent = (ratioAboveCount / totalStocks) * 100;
        result[industry] = DailyRatioPoint(
          date: todayDate,
          ratioAbovePercent: ratioAbovePercent,
          totalStocks: totalStocks,
          ratioAboveCount: ratioAboveCount,
        );
      }
    }

    return result;
  }

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

  /// 检查缺失天数
  /// 返回缺失天数（历史数据应通过 HistoricalKlineService 统一获取）
  int checkMissingDays() {
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

    return _missingDays;
  }

  /// 获取日期键
  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
