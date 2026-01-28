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
        if (mounted) {
          Navigator.of(context).pop();
        }
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
