import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/ratio_history_list.dart';

/// 股票详情页
class StockDetailScreen extends StatefulWidget {
  final Stock stock;

  const StockDetailScreen({super.key, required this.stock});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  List<KLine> _dailyBars = [];
  List<KLine> _weeklyBars = [];
  List<DailyRatio> _ratioHistory = [];

  bool _isLoadingKLine = true;
  bool _isLoadingRatio = true;
  String? _klineError;
  String? _ratioError;

  bool _showDaily = true; // true=日线, false=周线

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final stockService = context.read<StockService>();

    // 并行加载日线、周线、量比历史
    await Future.wait([
      _loadKLines(stockService),
      _loadRatioHistory(stockService),
    ]);
  }

  Future<void> _loadKLines(StockService stockService) async {
    setState(() {
      _isLoadingKLine = true;
      _klineError = null;
    });

    try {
      final daily = await stockService.getKLines(
        stock: widget.stock,
        category: klineTypeDaily,
        count: 30,
      );
      final weekly = await stockService.getKLines(
        stock: widget.stock,
        category: klineTypeWeekly,
        count: 30,
      );

      if (!mounted) return;
      setState(() {
        _dailyBars = daily;
        _weeklyBars = weekly;
        _isLoadingKLine = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _klineError = '加载 K 线失败: $e';
        _isLoadingKLine = false;
      });
    }
  }

  Future<void> _loadRatioHistory(StockService stockService) async {
    setState(() {
      _isLoadingRatio = true;
      _ratioError = null;
    });

    try {
      final history = await stockService.getRatioHistory(
        stock: widget.stock,
        days: 20,
      );

      if (!mounted) return;
      setState(() {
        _ratioHistory = history;
        _isLoadingRatio = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ratioError = '加载量比历史失败: $e';
        _isLoadingRatio = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stock.name} (${widget.stock.code})'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // K 线图区域
              _buildKLineSection(),
              const Divider(),
              // 量比历史区域
              RatioHistoryList(
                ratios: _ratioHistory,
                isLoading: _isLoadingRatio,
                errorMessage: _ratioError,
                onRetry: () => _loadRatioHistory(context.read<StockService>()),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKLineSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 切换按钮
          Row(
            children: [
              Text(
                'K 线图',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('日线')),
                  ButtonSegment(value: false, label: Text('周线')),
                ],
                selected: {_showDaily},
                onSelectionChanged: (selected) {
                  setState(() => _showDaily = selected.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // K 线图
          if (_isLoadingKLine)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_klineError != null)
            SizedBox(
              height: 220,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 8),
                    Text(_klineError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _loadKLines(context.read<StockService>()),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else
            KLineChart(bars: _showDaily ? _dailyBars : _weeklyBars),
        ],
      ),
    );
  }
}
