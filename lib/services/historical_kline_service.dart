import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
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
}
