import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

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

  /// 增量拉取缺失的日期
  /// 返回本次拉取的天数
  Future<int> fetchMissingDays(
    TdxPool pool,
    List<Stock> stocks,
    void Function(int current, int total)? onProgress,
  ) async {
    if (stocks.isEmpty || _isLoading) return 0;

    final missingDates = getMissingDateKeys();
    if (missingDates.isEmpty) return 0;

    _isLoading = true;
    notifyListeners();

    try {
      final connected = await pool.ensureConnected();
      if (!connected) throw Exception('无法连接到服务器');

      // 计算需要拉取的页数
      // 每页800条，每天约240条，每页约3.3天
      // 为安全起见，每缺3天拉1页
      final pagesToFetch = (missingDates.length / 3).ceil().clamp(1, 6);
      const int barsPerPage = 800;

      final stockList = stocks;
      final fetchTotal = stockList.length * pagesToFetch;
      final grandTotal = fetchTotal + stockList.length; // 拉取 + 处理

      // 收集所有K线数据
      final allBars = List<List<KLine>>.generate(stockList.length, (_) => []);

      for (var page = 0; page < pagesToFetch; page++) {
        final start = page * barsPerPage;
        final pageBars = await pool.batchGetSecurityBars(
          stocks: stockList,
          category: klineType1Min,
          start: start,
          count: barsPerPage,
          onProgress: (current, total) {
            final completed = page * stockList.length + current;
            onProgress?.call(completed, grandTotal);
          },
        );

        for (var i = 0; i < pageBars.length; i++) {
          if (pageBars[i].isNotEmpty) {
            allBars[i].addAll(pageBars[i]);
          }
        }
      }

      // 合并到现有数据
      final today = DateTime.now();
      final todayKey = formatDate(today);
      final newDates = <String>{};

      for (var i = 0; i < stockList.length; i++) {
        final stockCode = stockList[i].code;
        final bars = allBars[i];
        if (bars.isEmpty) continue;

        // 合并K线（去重）
        final existing = _stockBars[stockCode] ?? [];
        final existingTimes = existing.map((b) => b.datetime.millisecondsSinceEpoch).toSet();

        final newBars = bars.where((b) {
          // 跳过今天的数据
          if (formatDate(b.datetime) == todayKey) return false;
          return !existingTimes.contains(b.datetime.millisecondsSinceEpoch);
        }).toList();

        if (newBars.isNotEmpty) {
          existing.addAll(newBars);
          existing.sort((a, b) => a.datetime.compareTo(b.datetime));
          _stockBars[stockCode] = existing;

          // 记录新增的日期
          for (final bar in newBars) {
            newDates.add(formatDate(bar.datetime));
          }
        }

        onProgress?.call(fetchTotal + i + 1, grandTotal);
      }

      // 更新已完成日期
      // 只有当某个日期有足够多股票的数据时才标记为完成
      final dateCounts = <String, int>{};
      for (final dateKey in newDates) {
        dateCounts[dateKey] = (dateCounts[dateKey] ?? 0) + 1;
      }
      for (final entry in dateCounts.entries) {
        // 至少10%的股票有数据才认为该日期完整
        if (entry.value > stockList.length * 0.1) {
          _completeDates.add(entry.key);
        }
      }

      _lastFetchTime = DateTime.now();
      _cleanupOldData();
      await save();

      return newDates.length;
    } catch (e) {
      debugPrint('Failed to fetch historical kline data: $e');
      return 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 获取数据覆盖范围
  ({String? earliest, String? latest}) getDateRange() {
    if (_completeDates.isEmpty) return (earliest: null, latest: null);
    final sorted = _completeDates.toList()..sort();
    return (earliest: sorted.first, latest: sorted.last);
  }

  /// 获取缓存大小（估算字节数）
  int getCacheSize() {
    int count = 0;
    for (final bars in _stockBars.values) {
      count += bars.length;
    }
    // 每条K线约80字节
    return count * 80;
  }

  /// 格式化缓存大小
  String get cacheSizeFormatted {
    final bytes = getCacheSize();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
