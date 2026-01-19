import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 自选股服务 - 管理用户的自选股列表
class WatchlistService extends ChangeNotifier {
  static const String _storageKey = 'watchlist';

  /// 有效的股票代码前缀
  static const List<String> _validPrefixes = [
    '000', '001', '002', '003', // 深圳主板
    '300', '301', // 深圳创业板
    '600', '601', '603', '605', // 上海主板
    '688', // 上海科创板
  ];

  final List<String> _watchlist = [];

  /// 获取自选股列表
  List<String> get watchlist => List.unmodifiable(_watchlist);

  /// 从 SharedPreferences 加载自选股列表
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList(_storageKey);
    _watchlist.clear();
    if (stored != null) {
      _watchlist.addAll(stored);
    }
    notifyListeners();
  }

  /// 添加股票到自选股列表
  Future<void> addStock(String code) async {
    if (!_watchlist.contains(code)) {
      _watchlist.add(code);
      await _save();
      notifyListeners();
    }
  }

  /// 从自选股列表移除股票
  Future<void> removeStock(String code) async {
    if (_watchlist.remove(code)) {
      await _save();
      notifyListeners();
    }
  }

  /// 检查股票是否在自选股列表中
  bool contains(String code) {
    return _watchlist.contains(code);
  }

  /// 保存自选股列表到 SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _watchlist);
  }

  /// 验证股票代码是否有效
  /// 有效的股票代码是6位数字，且以有效前缀开头
  static bool isValidCode(String code) {
    // 必须是6位数字
    if (code.length != 6) {
      return false;
    }

    // 必须全是数字
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      return false;
    }

    // 必须以有效前缀开头
    final prefix = code.substring(0, 3);
    return _validPrefixes.contains(prefix);
  }

  /// 获取股票所属市场
  /// 返回 0 表示深圳市场 (代码以0或3开头)
  /// 返回 1 表示上海市场 (代码以6开头)
  static int getMarket(String code) {
    if (code.isEmpty) {
      return 0;
    }
    final firstChar = code[0];
    if (firstChar == '6') {
      return 1; // 上海市场
    }
    return 0; // 深圳市场 (0或3开头)
  }
}
