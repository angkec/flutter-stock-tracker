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

  /// 格式化 K 线数据为文本
  String _formatKLines(List<KLine> klines, String label) {
    if (klines.isEmpty) return '$label: 无数据\n';

    final buffer = StringBuffer('$label:\n');
    buffer.writeln('日期,开盘,最高,最低,收盘,成交量');
    for (final k in klines) {
      final date = '${k.datetime.month}/${k.datetime.day}';
      buffer.writeln('$date,${k.open.toStringAsFixed(2)},${k.high.toStringAsFixed(2)},${k.low.toStringAsFixed(2)},${k.close.toStringAsFixed(2)},${(k.volume / 10000).toStringAsFixed(0)}万');
    }
    return buffer.toString();
  }

  /// 准备单只股票的分析数据
  String _prepareStockData(Stock stock, List<KLine> dailyBars, List<KLine> weeklyBars) {
    final buffer = StringBuffer();
    buffer.writeln('【${stock.name} (${stock.code})】');
    buffer.writeln(_formatKLines(dailyBars, '日线(近60日)'));
    buffer.writeln(_formatKLines(weeklyBars, '周线(近12周)'));
    buffer.writeln('---');
    return buffer.toString();
  }

  /// 构建分析 Prompt
  String _buildPrompt(String stockData) {
    return '''你是一个专业的 A 股技术分析师。请分析以下自选股的日线和周线数据，
从技术面（均线、形态、支撑阻力）和量价关系（放量缩量、异动）
综合分析，推荐其中值得关注的股票。

每只推荐的股票给出一句话理由，不超过 30 字。
只推荐有明确买入信号或值得关注的股票，没有就不推荐。

请以 JSON 格式返回：
[
  {"code": "600519", "name": "贵州茅台", "reason": "周线放量突破平台，日线回踩20日均线"},
  ...
]

如果没有推荐，返回空数组 []

=== 股票数据 ===
$stockData''';
  }

  /// 调用 DeepSeek API 进行分析
  Future<List<AIRecommendation>> _callDeepSeekApi(String prompt) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      throw Exception('未配置 API Key');
    }

    final response = await http.post(
      Uri.parse(_apiEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.3,
      }),
    ).timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception('API 调用失败: ${error['error']?['message'] ?? response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final content = data['choices'][0]['message']['content'] as String;

    // 提取 JSON 数组（处理可能的 markdown 代码块）
    String jsonStr = content;
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
    if (jsonMatch != null) {
      jsonStr = jsonMatch.group(0)!;
    }

    final List<dynamic> recommendations = jsonDecode(jsonStr);
    return recommendations
        .map((r) => AIRecommendation.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 分析自选股列表
  ///
  /// [stocks] 股票列表
  /// [client] TDX 客户端，用于获取 K 线数据
  /// [onProgress] 进度回调 (current, total)
  Future<List<AIRecommendation>> analyzeStocks({
    required List<Stock> stocks,
    required TdxClient client,
    void Function(int current, int total)? onProgress,
  }) async {
    if (stocks.isEmpty) {
      return [];
    }

    final stockDataBuffer = StringBuffer();

    for (var i = 0; i < stocks.length; i++) {
      final stock = stocks[i];
      onProgress?.call(i + 1, stocks.length);

      // 获取日线数据（60根）
      final dailyBars = await client.getSecurityBars(
        market: stock.market,
        code: stock.code,
        category: klineTypeDaily,
        start: 0,
        count: 60,
      );

      // 获取周线数据（12根）
      final weeklyBars = await client.getSecurityBars(
        market: stock.market,
        code: stock.code,
        category: klineTypeWeekly,
        start: 0,
        count: 12,
      );

      stockDataBuffer.write(_prepareStockData(stock, dailyBars, weeklyBars));
    }

    final prompt = _buildPrompt(stockDataBuffer.toString());
    return _callDeepSeekApi(prompt);
  }
}
