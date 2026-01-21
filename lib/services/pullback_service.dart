import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/pullback_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// 高质量回踩检测服务
class PullbackService extends ChangeNotifier {
  static const String _storageKey = 'pullback_config';

  PullbackConfig _config = PullbackConfig.defaults;

  /// 当前配置
  PullbackConfig get config => _config;

  /// 从 SharedPreferences 加载配置
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _config = PullbackConfig.fromJson(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load pullback config: $e');
    }
  }

  /// 更新配置并保存
  Future<void> updateConfig(PullbackConfig newConfig) async {
    _config = newConfig;
    notifyListeners();
    await _save();
  }

  /// 重置为默认配置
  Future<void> resetToDefaults() async {
    _config = PullbackConfig.defaults;
    notifyListeners();
    await _save();
  }

  /// 保存配置到 SharedPreferences
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('Failed to save pullback config: $e');
    }
  }

  /// 检测是否为高质量回踩
  /// [dailyBars] 需要最近至少7天的日K数据，按时间升序排列（最早的在前）
  /// 返回 true 表示符合高质量回踩条件
  bool isPullback(List<KLine> dailyBars) {
    // 至少需要7根K线：前5日 + 昨日 + 今日
    if (dailyBars.length < 7) {
      return false;
    }

    // 取最后7根K线
    final bars = dailyBars.length > 7
        ? dailyBars.sublist(dailyBars.length - 7)
        : dailyBars;

    final prev5 = bars.sublist(0, 5);  // 前5日
    final yesterday = bars[5];          // 昨日
    final today = bars[6];              // 今日

    // 1. 昨日高量：昨日成交量 > 前5日均量 × volumeMultiplier
    final avg5Volume = prev5.map((b) => b.volume).reduce((a, b) => a + b) / 5;
    if (yesterday.volume <= avg5Volume * _config.volumeMultiplier) {
      return false;
    }

    // 2. 昨日上涨：昨日收盘 > 昨日开盘 × (1 + minYesterdayGain)
    if (yesterday.close <= yesterday.open * (1 + _config.minYesterdayGain)) {
      return false;
    }

    // 3. 今日缩量：今日成交量 < 昨日成交量
    if (today.volume >= yesterday.volume) {
      return false;
    }

    // 4. 今日下跌：今日收盘 < 今日开盘
    if (today.close >= today.open) {
      return false;
    }

    // 5. 跌幅限制：今日跌幅 < 昨日涨幅 × maxDropRatio
    final yesterdayGain = (yesterday.close - yesterday.open) / yesterday.open;
    final todayDrop = (today.open - today.close) / today.open;
    if (todayDrop >= yesterdayGain * _config.maxDropRatio) {
      return false;
    }

    // 6. 量比要求：今日日K量比 > minDailyRatio
    // 日K量比 = 今日成交量 / 前5日均量
    final todayRatio = today.volume / avg5Volume;
    if (todayRatio <= _config.minDailyRatio) {
      return false;
    }

    return true;
  }
}
