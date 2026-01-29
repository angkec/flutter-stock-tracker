import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 持仓服务 - 管理用户从截图导入的持仓列表
class HoldingsService extends ChangeNotifier {
  static const String _storageKey = 'holdings';

  final List<String> _holdings = [];

  /// 获取持仓列表
  List<String> get holdings => List.unmodifiable(_holdings);

  /// 从 SharedPreferences 加载持仓列表
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? stored = prefs.getStringList(_storageKey);
    _holdings.clear();
    if (stored != null) {
      _holdings.addAll(stored);
    }
    notifyListeners();
  }

  /// 设置持仓列表（替换模式）
  Future<void> setHoldings(List<String> codes) async {
    _holdings.clear();
    _holdings.addAll(codes);
    await _save();
    notifyListeners();
  }

  /// 清空持仓列表
  Future<void> clear() async {
    _holdings.clear();
    await _save();
    notifyListeners();
  }

  /// 检查股票是否在持仓列表中
  bool contains(String code) {
    return _holdings.contains(code);
  }

  /// 保存持仓列表到 SharedPreferences
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _holdings);
  }
}
