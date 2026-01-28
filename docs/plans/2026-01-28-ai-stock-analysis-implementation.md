# AI 选股助手实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在自选股页面添加 AI 分析功能，调用 DeepSeek API 分析日线和周线数据，返回推荐股票列表。

**Architecture:** 创建 AIAnalysisService 管理 API Key 和分析逻辑，使用 BottomSheet 展示结果。API Key 支持永久保存（flutter_secure_storage）和临时使用（内存）两种模式。

**Tech Stack:** Flutter, flutter_secure_storage, http, DeepSeek API

---

## Task 1: 添加依赖

**Files:**
- Modify: `pubspec.yaml:30-40`

**Step 1: 添加 flutter_secure_storage 和 http 依赖**

在 `pubspec.yaml` 的 `dependencies` 部分添加：

```yaml
  flutter_secure_storage: ^9.2.4
  http: ^1.2.0
```

**Step 2: 运行 flutter pub get**

Run: `flutter pub get`
Expected: 依赖安装成功，无报错

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add flutter_secure_storage and http dependencies"
```

---

## Task 2: 创建 AIRecommendation 模型

**Files:**
- Create: `lib/models/ai_recommendation.dart`

**Step 1: 创建模型文件**

```dart
/// AI 推荐结果
class AIRecommendation {
  final String stockCode;
  final String stockName;
  final String reason;

  const AIRecommendation({
    required this.stockCode,
    required this.stockName,
    required this.reason,
  });

  factory AIRecommendation.fromJson(Map<String, dynamic> json) {
    return AIRecommendation(
      stockCode: json['code'] as String,
      stockName: json['name'] as String,
      reason: json['reason'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': stockCode,
    'name': stockName,
    'reason': reason,
  };
}
```

**Step 2: Commit**

```bash
git add lib/models/ai_recommendation.dart
git commit -m "feat: add AIRecommendation model"
```

---

## Task 3: 创建 AIAnalysisService - API Key 管理部分

**Files:**
- Create: `lib/services/ai_analysis_service.dart`

**Step 1: 创建 service 骨架和 API Key 管理**

```dart
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
```

**Step 2: Commit**

```bash
git add lib/services/ai_analysis_service.dart
git commit -m "feat: add AIAnalysisService with API key management"
```

---

## Task 4: 实现 AIAnalysisService - 数据准备和 API 调用

**Files:**
- Modify: `lib/services/ai_analysis_service.dart`

**Step 1: 添加数据准备方法**

在 `AIAnalysisService` 类末尾添加（`deleteApiKey` 方法之后）：

```dart
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
```

**Step 2: 添加 API 调用方法**

继续在类末尾添加：

```dart
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
```

**Step 3: 添加主分析方法**

继续在类末尾添加：

```dart
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
```

**Step 4: Commit**

```bash
git add lib/services/ai_analysis_service.dart
git commit -m "feat: implement AIAnalysisService data preparation and API call"
```

---

## Task 5: 注册 AIAnalysisService 到 Provider

**Files:**
- Modify: `lib/main.dart:1-20` (imports)
- Modify: `lib/main.dart:49-70` (providers)

**Step 1: 添加 import**

在 `lib/main.dart` 的 import 部分（约第 18 行后）添加：

```dart
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';
```

**Step 2: 添加 Provider**

在 `lib/main.dart` 的 `MultiProvider` 的 `providers` 列表中，在 `WatchlistService` Provider 之后（约第 53 行后）添加：

```dart
        ChangeNotifierProvider(create: (_) {
          final service = AIAnalysisService();
          service.load(); // 异步加载 API Key
          return service;
        }),
```

**Step 3: 验证编译**

Run: `flutter analyze lib/main.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register AIAnalysisService in MultiProvider"
```

---

## Task 6: 创建 API Key 配置对话框

**Files:**
- Create: `lib/widgets/api_key_dialog.dart`

**Step 1: 创建对话框组件**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';

/// API Key 配置对话框
///
/// 返回值：
/// - true: 用户配置了 API Key（保存或临时使用）
/// - false/null: 用户取消
class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({super.key});

  /// 显示对话框
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ApiKeyDialog(),
    );
  }

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  final _controller = TextEditingController();
  bool _obscureText = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _useOnce() {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }
    context.read<AIAnalysisService>().setTempApiKey(key);
    Navigator.of(context).pop(true);
  }

  Future<void> _saveAndUse() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }
    await context.read<AIAnalysisService>().saveApiKey(key);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('配置 DeepSeek API Key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            obscureText: _obscureText,
            decoration: InputDecoration(
              hintText: 'sk-xxxxxxxxxxxxxxxx',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '获取 API Key: platform.deepseek.com',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _useOnce,
          child: const Text('仅本次使用'),
        ),
        FilledButton(
          onPressed: _saveAndUse,
          child: const Text('保存并使用'),
        ),
      ],
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/widgets/api_key_dialog.dart
git commit -m "feat: add ApiKeyDialog for API key configuration"
```

---

## Task 7: 创建 AI 分析结果弹窗

**Files:**
- Create: `lib/widgets/ai_analysis_sheet.dart`

**Step 1: 创建弹窗组件**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/ai_recommendation.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/widgets/api_key_dialog.dart';

/// AI 分析结果弹窗
class AIAnalysisSheet extends StatefulWidget {
  final List<Stock> stocks;

  const AIAnalysisSheet({super.key, required this.stocks});

  /// 显示弹窗
  static Future<void> show(BuildContext context, List<Stock> stocks) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AIAnalysisSheet(stocks: stocks),
    );
  }

  @override
  State<AIAnalysisSheet> createState() => _AIAnalysisSheetState();
}

class _AIAnalysisSheetState extends State<AIAnalysisSheet> {
  TdxClient? _client;
  bool _isLoading = true;
  String? _error;
  List<AIRecommendation>? _recommendations;
  String _progressText = '准备中...';

  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    final aiService = context.read<AIAnalysisService>();

    // 检查 API Key
    if (!aiService.hasApiKey) {
      final configured = await ApiKeyDialog.show(context);
      if (configured != true || !mounted) {
        Navigator.of(context).pop();
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _progressText = '连接服务器...';
    });

    try {
      // 连接 TDX 服务器
      _client = TdxClient();
      bool connected = false;
      for (final server in TdxClient.servers) {
        connected = await _client!.connect(
          server['host'] as String,
          server['port'] as int,
        );
        if (connected) break;
      }

      if (!connected) {
        throw Exception('无法连接到行情服务器');
      }

      if (!mounted) return;

      // 开始分析
      final recommendations = await aiService.analyzeStocks(
        stocks: widget.stocks,
        client: _client!,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progressText = '获取数据 ($current/$total)...';
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _recommendations = recommendations;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'AI 选股建议',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // 内容区
            Expanded(
              child: _buildContent(scrollController),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_progressText),
            if (_progressText.contains('获取数据'))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'AI 正在分析...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _startAnalysis,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final recommendations = _recommendations ?? [];
    if (recommendations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sentiment_neutral,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text('当前自选股暂无明确买入信号'),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: recommendations.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final r = recommendations[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${r.stockName} (${r.stockCode})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text(
                  r.reason,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/widgets/ai_analysis_sheet.dart
git commit -m "feat: add AIAnalysisSheet for displaying analysis results"
```

---

## Task 8: 在自选股页面添加 AI 按钮

**Files:**
- Modify: `lib/screens/watchlist_screen.dart`

**Step 1: 添加 import**

在 `lib/screens/watchlist_screen.dart` 顶部 import 部分添加：

```dart
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';
import 'package:stock_rtwatcher/widgets/ai_analysis_sheet.dart';
```

**Step 2: 添加 AI 按钮**

在 `_buildEmptyState` 方法之前，添加新方法：

```dart
  void _showAIAnalysis() {
    final watchlistService = context.read<WatchlistService>();
    final marketProvider = context.read<MarketDataProvider>();

    // 从 marketProvider 获取自选股的 Stock 对象
    final stocks = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .map((d) => d.stock)
        .toList();

    if (stocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加自选股')),
      );
      return;
    }

    AIAnalysisSheet.show(context, stocks);
  }
```

**Step 3: 修改 build 方法，添加 AppBar**

将 `build` 方法中的 `return SafeArea(` 改为带 Scaffold 和 AppBar 的结构：

```dart
  @override
  Widget build(BuildContext context) {
    final watchlistService = context.watch<WatchlistService>();
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    // 从共享数据中过滤自选股
    final watchlistData = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .toList();

    // 计算今日实时趋势数据
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);

    return Scaffold(
      appBar: AppBar(
        title: const Text('自选股'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI 分析',
            onPressed: _showAIAnalysis,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            // 添加股票输入框
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        hintText: '输入股票代码',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onSubmitted: (_) => _addStock(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addStock,
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
            // 自选股列表
            Expanded(
              child: watchlistData.isEmpty
                  ? _buildEmptyState(watchlistService)
                  : RefreshIndicator(
                      onRefresh: () => marketProvider.refresh(),
                      child: StockTable(
                        stocks: watchlistData,
                        isLoading: marketProvider.isLoading,
                        onLongPress: (data) => _removeStock(data.stock.code),
                        onIndustryTap: widget.onIndustryTap,
                        industryTrendData: trendService.trendData,
                        todayTrendData: todayTrend,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
```

**Step 4: 验证编译**

Run: `flutter analyze lib/screens/watchlist_screen.dart`
Expected: No issues found

**Step 5: Commit**

```bash
git add lib/screens/watchlist_screen.dart
git commit -m "feat: add AI analysis button to watchlist screen"
```

---

## Task 9: 创建 AI 设置页面入口

**Files:**
- Create: `lib/screens/ai_settings_screen.dart`

**Step 1: 创建设置页面**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';

/// AI 设置页面
class AISettingsScreen extends StatefulWidget {
  const AISettingsScreen({super.key});

  @override
  State<AISettingsScreen> createState() => _AISettingsScreenState();
}

class _AISettingsScreenState extends State<AISettingsScreen> {
  final _controller = TextEditingController();
  bool _obscureText = true;
  bool _isEditing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _controller.clear();
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _controller.clear();
    });
  }

  Future<void> _saveApiKey() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 API Key')),
      );
      return;
    }
    await context.read<AIAnalysisService>().saveApiKey(key);
    setState(() {
      _isEditing = false;
      _controller.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key 已保存')),
      );
    }
  }

  Future<void> _deleteApiKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除已保存的 API Key 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<AIAnalysisService>().deleteApiKey();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key 已删除')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiService = context.watch<AIAnalysisService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 设置'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'DeepSeek API Key',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _controller,
                    obscureText: _obscureText,
                    decoration: InputDecoration(
                      hintText: 'sk-xxxxxxxxxxxxxxxx',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscureText = !_obscureText),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _cancelEditing,
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveApiKey,
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            ListTile(
              title: Text(
                aiService.hasApiKey ? aiService.maskedApiKey ?? '已配置' : '未配置',
              ),
              subtitle: const Text('用于 AI 选股分析'),
              trailing: aiService.hasApiKey
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: _startEditing,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: _deleteApiKey,
                        ),
                      ],
                    )
                  : FilledButton(
                      onPressed: _startEditing,
                      child: const Text('配置'),
                    ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '说明：\n'
              '• API Key 用于调用 DeepSeek AI 进行股票分析\n'
              '• 获取地址: platform.deepseek.com\n'
              '• Key 会加密保存在本地，不会上传到任何服务器',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/screens/ai_settings_screen.dart
git commit -m "feat: add AI settings screen"
```

---

## Task 10: 在自选股页面 AppBar 添加设置入口

**Files:**
- Modify: `lib/screens/watchlist_screen.dart`

**Step 1: 添加 import**

在 `lib/screens/watchlist_screen.dart` 的 import 部分添加：

```dart
import 'package:stock_rtwatcher/screens/ai_settings_screen.dart';
```

**Step 2: 在 AppBar actions 添加设置按钮**

在 `build` 方法中的 `AppBar` 的 `actions` 列表里，AI 按钮之后添加设置按钮：

```dart
          actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'AI 分析',
              onPressed: _showAIAnalysis,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '设置',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AISettingsScreen()),
                );
              },
            ),
          ],
```

**Step 3: 验证编译**

Run: `flutter analyze lib/screens/watchlist_screen.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/screens/watchlist_screen.dart
git commit -m "feat: add settings button to watchlist appbar"
```

---

## Task 11: 端到端测试

**Files:**
- No file changes, manual testing

**Step 1: 运行应用**

Run: `flutter run`

**Step 2: 测试流程**

1. 进入自选股 Tab
2. 确认 AppBar 显示「AI」和「设置」按钮
3. 点击「设置」→ 进入 AI 设置页面 → 配置 API Key → 保存
4. 返回自选股页面
5. 添加几只自选股（如 600519, 000001）
6. 刷新数据
7. 点击「AI」按钮
8. 确认弹窗显示加载状态
9. 等待分析完成，确认显示推荐结果或"暂无推荐"

**Step 3: 测试临时 API Key 流程**

1. 进入设置 → 删除已保存的 API Key
2. 点击「AI」按钮
3. 确认弹出配置对话框
4. 输入 API Key → 点击「仅本次使用」
5. 确认分析正常进行
6. 重启应用 → 确认需要重新配置 API Key

**Step 4: 最终 Commit（如有修复）**

```bash
git add -A
git commit -m "fix: address issues found in e2e testing"
```

---

## Task 12: iOS 安全存储配置

**Files:**
- Modify: `ios/Runner/Info.plist`

**注意：** flutter_secure_storage 在 iOS 上需要配置 Keychain。如果遇到问题，需要在 `ios/Runner/Info.plist` 添加：

```xml
<key>NSFaceIDUsageDescription</key>
<string>用于安全访问 API Key</string>
```

但通常默认配置即可工作，只在遇到问题时添加。

**Step 1: 测试 iOS 构建**

Run: `flutter build ios --simulator`
Expected: Build succeeds

**Step 2: Commit（如有改动）**

```bash
git add ios/Runner/Info.plist
git commit -m "chore: add iOS keychain configuration for secure storage"
```

---

## Summary

完成以上 12 个 Task 后，AI 选股助手功能将完整实现：

1. ✅ 依赖添加
2. ✅ 数据模型
3. ✅ API Key 管理服务
4. ✅ 数据准备和 API 调用
5. ✅ Provider 注册
6. ✅ API Key 配置对话框
7. ✅ 分析结果弹窗
8. ✅ 自选股页面 AI 按钮
9. ✅ AI 设置页面
10. ✅ 设置入口
11. ✅ 端到端测试
12. ✅ iOS 配置（如需要）
