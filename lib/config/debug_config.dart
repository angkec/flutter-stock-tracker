import 'package:flutter/foundation.dart';

/// 数据限制配置
class DebugConfig {
  /// Debug 模式下最大股票数量
  static const int maxStocksInDebug = 100;

  /// Release 模式下最大股票数量（0 表示不限制）
  static const int maxStocksInRelease = 0;

  /// 获取当前模式下的最大股票数量
  static int get maxStocks => kDebugMode ? maxStocksInDebug : maxStocksInRelease;

  /// 是否应该限制数据量
  static bool get shouldLimitData => maxStocks > 0;

  /// 限制股票列表
  static List<T> limitStocks<T>(List<T> stocks) {
    if (shouldLimitData && stocks.length > maxStocks) {
      debugPrint('[DebugConfig] 限制股票数量: ${stocks.length} -> $maxStocks');
      return stocks.sublist(0, maxStocks);
    }
    return stocks;
  }
}
