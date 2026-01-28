import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:stock_rtwatcher/models/ai_recommendation.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

/// AI 分析服务 - 调用 DeepSeek API 分析自选股
class AIAnalysisService extends ChangeNotifier {
  static const String _apiKeyStorageKey = 'deepseek_api_key';
  static const String _apiEndpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const String _model = 'deepseek-chat';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 永久保存的 API Key
  String? _savedApiKey;

  /// 临时 API Key（仅本次使用）
  String? _tempApiKey;

  /// 获取当前可用的 API Key（优先使用临时 Key）
  String? get apiKey => _tempApiKey ?? _savedApiKey;

  /// 是否已配置 API Key
  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;

  /// 获取脱敏后的 API Key 显示
  String? get maskedApiKey {
    final key = _savedApiKey;
    if (key == null || key.length < 8) return null;
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  /// 加载保存的 API Key
  Future<void> load() async {
    _savedApiKey = await _secureStorage.read(key: _apiKeyStorageKey);
    notifyListeners();
  }

  /// 保存 API Key
  Future<void> saveApiKey(String apiKey) async {
    await _secureStorage.write(key: _apiKeyStorageKey, value: apiKey);
    _savedApiKey = apiKey;
    _tempApiKey = null; // 清除临时 Key
    notifyListeners();
  }

  /// 设置临时 API Key（仅本次使用）
  void setTempApiKey(String apiKey) {
    _tempApiKey = apiKey;
    notifyListeners();
  }

  /// 清除临时 API Key
  void clearTempApiKey() {
    _tempApiKey = null;
    notifyListeners();
  }

  /// 删除保存的 API Key
  Future<void> deleteApiKey() async {
    await _secureStorage.delete(key: _apiKeyStorageKey);
    _savedApiKey = null;
    notifyListeners();
  }
}
