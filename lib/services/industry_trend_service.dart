import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// Isolate 中计算行业趋势的参数
class _TrendComputeParams {
  /// 每股票每日涨跌量: stockCode -> dateKey -> [up, down]
  final Map<String, Map<String, List<double>>> stockVolumes;

  /// 股票行业映射: stockCode -> industry
  final Map<String, String> stockIndustries;

  /// 要计算的日期列表
  final List<String> dates;

  _TrendComputeParams({
    required this.stockVolumes,
    required this.stockIndustries,
    required this.dates,
  });
}

/// Isolate 中计算行业趋势
Map<String, List<Map<String, dynamic>>> _computeTrendInIsolate(
  _TrendComputeParams params,
) {
  final result = <String, List<Map<String, dynamic>>>{};

  // 按行业分组股票
  final industryStocks = <String, List<String>>{};
  for (final entry in params.stockIndustries.entries) {
    industryStocks.putIfAbsent(entry.value, () => []).add(entry.key);
  }

  // 计算每个行业每天的趋势
  for (final industry in industryStocks.keys) {
    final stockCodes = industryStocks[industry]!;
    final points = <Map<String, dynamic>>[];

    for (final dateKey in params.dates) {
      var ratioAboveCount = 0;
      var totalStocks = 0;

      for (final stockCode in stockCodes) {
        final volumes = params.stockVolumes[stockCode]?[dateKey];
        if (volumes == null) continue;
        final up = volumes[0];
        final down = volumes[1];
        if (down <= 0) continue;

        totalStocks++;
        final ratio = up / down;
        if (ratio > 1.0 && ratio <= 1000) {
          ratioAboveCount++;
        }
      }

      if (totalStocks > 0) {
        points.add({
          'date': dateKey,
          'ratioAbovePercent': (ratioAboveCount / totalStocks) * 100,
          'totalStocks': totalStocks,
          'ratioAboveCount': ratioAboveCount,
        });
      }
    }

    if (points.isNotEmpty) {
      result[industry] = points;
    }
  }

  return result;
}

/// 行业趋势服务
/// 计算每个行业的每日分钟涨跌量比趋势
class IndustryTrendService extends ChangeNotifier {
  static const String _storageKey = 'industry_trend_cache';
  static const int _maxCacheDays = 30;

  Map<String, IndustryTrendData> _trendData = {};
  final bool _isLoading = false;
  int _missingDays = 0;

  /// 计算时使用的K线数据版本
  int _calculatedFromVersion = -1;

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
  ///
  /// [dataVersion] - 当前数据版本（用于缓存校验）
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    int? dataVersion,
    bool force = false,
  }) async {
    if (stocks.isEmpty) return;

    // 检查是否需要重算
    final currentVersion = dataVersion ?? 0;
    if (!force &&
        _calculatedFromVersion == currentVersion &&
        _trendData.isNotEmpty) {
      debugPrint('[IndustryTrend] 数据版本未变 (v$currentVersion)，跳过重算');
      return;
    }

    debugPrint(
      '[IndustryTrend] 开始重算趋势, ${stocks.length} 只股票, 数据版本 v$currentVersion',
    );

    final totalStopwatch = Stopwatch()..start();
    final prepareStopwatch = Stopwatch()..start();
    var cacheHitCount = 0;
    var cacheMissCount = 0;
    var loadVolumesMs = 0;

    // 准备传给 isolate 的数据（在主线程完成，避免传输大量 K 线数据）
    final stockVolumes = <String, Map<String, List<double>>>{};
    final stockIndustries = <String, String>{};
    final allDates = <String>{};

    for (final stock in stocks) {
      final industry = stock.industry;
      if (industry == null || industry.isEmpty) continue;

      stockIndustries[stock.stock.code] = industry;

      // 获取这只股票的每日涨跌量
      final volumes = await klineService.getDailyVolumes(
        stock.stock.code,
        onProfile: (profile) {
          loadVolumesMs += profile.elapsedMs;
          if (profile.fromCache) {
            cacheHitCount++;
          } else {
            cacheMissCount++;
          }
        },
      );
      if (volumes.isNotEmpty) {
        stockVolumes[stock.stock.code] = volumes.map(
          (dateKey, vol) => MapEntry(dateKey, [vol.up, vol.down]),
        );
        // Collect all dates from the volumes data
        allDates.addAll(volumes.keys);
      }
    }
    prepareStopwatch.stop();

    final dates = allDates.toList()..sort();
    debugPrint(
      '[IndustryTrend] 准备数据完成, ${stockVolumes.length} 只股票, ${dates.length} 个日期, '
      'prepareMs=${prepareStopwatch.elapsedMilliseconds}, '
      'dailyVolumesMs=$loadVolumesMs, cacheHit=$cacheHitCount, cacheMiss=$cacheMissCount',
    );

    // 在 isolate 中计算
    final computeStopwatch = Stopwatch()..start();
    final computeResult = await compute(
      _computeTrendInIsolate,
      _TrendComputeParams(
        stockVolumes: stockVolumes,
        stockIndustries: stockIndustries,
        dates: dates,
      ),
    );
    computeStopwatch.stop();

    // 转换结果
    final transformStopwatch = Stopwatch()..start();
    final newTrendData = <String, IndustryTrendData>{};
    for (final entry in computeResult.entries) {
      final industry = entry.key;
      final points =
          entry.value
              .map(
                (p) => DailyRatioPoint(
                  date: HistoricalKlineService.parseDate(p['date'] as String),
                  ratioAbovePercent: p['ratioAbovePercent'] as double,
                  totalStocks: p['totalStocks'] as int,
                  ratioAboveCount: p['ratioAboveCount'] as int,
                ),
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));

      newTrendData[industry] = IndustryTrendData(
        industry: industry,
        points: points,
      );
    }
    transformStopwatch.stop();

    debugPrint('[IndustryTrend] 计算完成, ${newTrendData.length} 个行业有数据');

    _trendData = newTrendData;
    _missingDays = 0;
    _calculatedFromVersion = currentVersion;

    final saveStopwatch = Stopwatch()..start();
    await _save();
    saveStopwatch.stop();

    totalStopwatch.stop();
    debugPrint(
      '[IndustryTrend][timing] '
      'prepareMs=${prepareStopwatch.elapsedMilliseconds}, '
      'computeMs=${computeStopwatch.elapsedMilliseconds}, '
      'transformMs=${transformStopwatch.elapsedMilliseconds}, '
      'saveMs=${saveStopwatch.elapsedMilliseconds}, '
      'totalMs=${totalStopwatch.elapsedMilliseconds}',
    );

    debugPrint('[IndustryTrend] 保存完成 (基于数据版本 v$currentVersion)');
    notifyListeners();
  }

  /// 计算今日实时行业趋势
  /// 使用股票现有的 ratio 字段（当前会话的分钟涨跌量比）
  /// 返回按行业分组的今日数据点
  Map<String, DailyRatioPoint> calculateTodayTrend(
    List<StockMonitorData> stocks,
  ) {
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
        _deserializeCache(json);
        _cleanupOldData();
        debugPrint(
          '[IndustryTrend] 缓存加载完成, calculatedFromVersion=$_calculatedFromVersion, ${_trendData.length} 个行业',
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load industry trend cache: $e');
    }
  }

  /// 检查缺失天数
  ///
  /// 可传入 [expectedTradingDays] 使用外部真实交易日列表（推荐）；
  /// 未提供时会回退到最近30个日历天内的工作日估算。
  int checkMissingDays({List<DateTime>? expectedTradingDays}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cachedDates = _getCachedDates();

    final requiredDates =
        (expectedTradingDays ??
                _estimateTradingDaysInRecentCalendarWindow(
                  today,
                  _maxCacheDays,
                ))
            .map((d) => DateTime(d.year, d.month, d.day))
            .where((d) => !_isSameDay(d, today))
            .toSet();

    var missing = 0;
    for (final date in requiredDates) {
      if (!cachedDates.contains(_dateKey(date))) {
        missing++;
      }
    }

    _missingDays = missing;
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

  /// 估算最近N个日历天内的交易日（仅排除周末）
  ///
  /// 注意：法定节假日需通过 [checkMissingDays] 的 expectedTradingDays 参数传入真实交易日。
  List<DateTime> _estimateTradingDaysInRecentCalendarWindow(
    DateTime from,
    int calendarDays,
  ) {
    final days = <DateTime>[];
    final normalizedFrom = DateTime(from.year, from.month, from.day);

    for (var i = 1; i <= calendarDays; i++) {
      final current = normalizedFrom.subtract(Duration(days: i));
      if (current.weekday == DateTime.saturday ||
          current.weekday == DateTime.sunday) {
        continue;
      }
      days.add(current);
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
      'calculatedFromVersion': _calculatedFromVersion,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 反序列化缓存数据
  void _deserializeCache(Map<String, dynamic> json) {
    // 检查版本
    final version = json['version'] as int? ?? 0;
    if (version != 1) {
      return; // 版本不兼容
    }

    _calculatedFromVersion = json['calculatedFromVersion'] as int? ?? -1;

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final result = <String, IndustryTrendData>{};
    for (final entry in data.entries) {
      try {
        result[entry.key] = IndustryTrendData.fromJson(
          entry.value as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint(
          'Failed to deserialize industry trend data for ${entry.key}: $e',
        );
      }
    }
    _trendData = result;
  }
}
