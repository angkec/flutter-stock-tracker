import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// 历史分钟K线数据服务
/// 统一管理原始分钟K线，支持增量拉取
class HistoricalKlineService extends ChangeNotifier {
  static const String _storageKey = 'historical_kline_cache_v1';
  static const int _maxCacheDays = 30;

  /// 存储：按股票代码索引
  /// stockCode -> List<KLine> (按时间升序排列)
  Map<String, List<KLine>> _stockBars = {};

  /// 已完整拉取的日期集合
  Set<String> _completeDates = {};

  /// 最后拉取时间
  DateTime? _lastFetchTime;

  /// 是否正在加载
  bool _isLoading = false;

  // Getters
  bool get isLoading => _isLoading;
  DateTime? get lastFetchTime => _lastFetchTime;
  Set<String> get completeDates => Set.unmodifiable(_completeDates);
  int get stockCount => _stockBars.length;

  /// 格式化日期为 "YYYY-MM-DD" 字符串
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 解析 "YYYY-MM-DD" 字符串为 DateTime
  static DateTime parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  /// 设置某只股票的K线数据（用于测试）
  @visibleForTesting
  void setStockBars(String stockCode, List<KLine> bars) {
    _stockBars[stockCode] = bars..sort((a, b) => a.datetime.compareTo(b.datetime));
  }

  /// 获取某只股票所有日期的涨跌量汇总
  /// 返回 { dateKey: (up: upVolume, down: downVolume) }
  Map<String, ({double up, double down})> getDailyVolumes(String stockCode) {
    final bars = _stockBars[stockCode];
    if (bars == null || bars.isEmpty) return {};

    final result = <String, ({double up, double down})>{};

    for (final bar in bars) {
      final dateKey = formatDate(bar.datetime);
      final current = result[dateKey];

      double upAdd = 0;
      double downAdd = 0;
      if (bar.isUp) {
        upAdd = bar.volume;
      } else if (bar.isDown) {
        downAdd = bar.volume;
      }

      result[dateKey] = (
        up: (current?.up ?? 0) + upAdd,
        down: (current?.down ?? 0) + downAdd,
      );
    }

    return result;
  }

  /// 添加已完成日期（用于测试）
  @visibleForTesting
  void addCompleteDate(String dateKey) {
    _completeDates.add(dateKey);
  }

  /// 估算最近N个交易日（排除周末）
  List<DateTime> _estimateTradingDays(DateTime from, int count) {
    final days = <DateTime>[];
    var current = from;
    var checked = 0;

    while (days.length < count && checked < count * 2) {
      current = current.subtract(const Duration(days: 1));
      checked++;
      if (current.weekday == DateTime.saturday || current.weekday == DateTime.sunday) {
        continue;
      }
      days.add(DateTime(current.year, current.month, current.day));
    }

    return days;
  }

  /// 获取缺失天数
  int getMissingDays() {
    final today = DateTime.now();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);

    int missing = 0;
    for (final day in tradingDays) {
      final key = formatDate(day);
      if (!_completeDates.contains(key)) {
        missing++;
      }
    }
    return missing;
  }

  /// 获取缺失的日期列表
  List<String> getMissingDateKeys() {
    final today = DateTime.now();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);

    final missing = <String>[];
    for (final day in tradingDays) {
      final key = formatDate(day);
      if (!_completeDates.contains(key)) {
        missing.add(key);
      }
    }
    return missing;
  }

  /// 序列化缓存数据
  Map<String, dynamic> serializeCache() {
    final stocks = <String, dynamic>{};
    for (final entry in _stockBars.entries) {
      stocks[entry.key] = entry.value.map((bar) => bar.toJson()).toList();
    }

    return {
      'version': 1,
      'lastFetchTime': _lastFetchTime?.toIso8601String(),
      'completeDates': _completeDates.toList(),
      'stocks': stocks,
    };
  }

  /// 反序列化缓存数据
  void deserializeCache(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    if (version != 1) return;

    final lastFetchStr = json['lastFetchTime'] as String?;
    _lastFetchTime = lastFetchStr != null ? DateTime.parse(lastFetchStr) : null;

    final dates = json['completeDates'] as List<dynamic>?;
    _completeDates = dates?.map((e) => e as String).toSet() ?? {};

    final stocks = json['stocks'] as Map<String, dynamic>?;
    if (stocks != null) {
      _stockBars = {};
      for (final entry in stocks.entries) {
        final barsList = entry.value as List<dynamic>;
        _stockBars[entry.key] = barsList
            .map((e) => KLine.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.datetime.compareTo(b.datetime));
      }
    }

    _cleanupOldData();
  }

  /// 清理超过30天的旧数据
  void _cleanupOldData() {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxCacheDays));
    final cutoffKey = formatDate(cutoff);

    // 清理过期日期
    _completeDates.removeWhere((key) => key.compareTo(cutoffKey) < 0);

    // 清理过期K线
    for (final entry in _stockBars.entries) {
      entry.value.removeWhere((bar) => formatDate(bar.datetime).compareTo(cutoffKey) < 0);
    }
    _stockBars.removeWhere((_, bars) => bars.isEmpty);
  }

  /// 从本地缓存加载
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        deserializeCache(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load historical kline cache: $e');
    }
  }

  /// 保存到本地缓存
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(serializeCache()));
    } catch (e) {
      debugPrint('Failed to save historical kline cache: $e');
    }
  }

  /// 清空缓存
  Future<void> clear() async {
    _stockBars = {};
    _completeDates = {};
    _lastFetchTime = null;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('Failed to clear historical kline cache: $e');
    }
  }
}
