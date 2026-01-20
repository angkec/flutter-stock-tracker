import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
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
  // 独立的 TDX 连接，不和全市场数据共用
  TdxClient? _client;
  bool _isConnecting = true;
  String? _connectError;

  List<KLine> _dailyBars = [];
  List<KLine> _weeklyBars = [];
  List<DailyRatio> _ratioHistory = [];

  bool _isLoadingKLine = false;
  bool _isLoadingRatio = false;
  String? _klineError;
  String? _ratioError;

  bool _showDaily = true; // true=日线, false=周线

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }

  Future<void> _connectAndLoad() async {
    setState(() {
      _isConnecting = true;
      _connectError = null;
    });

    // 创建独立连接
    _client = TdxClient();
    final connected = await _client!.autoConnect();

    if (!mounted) return;

    if (!connected) {
      setState(() {
        _isConnecting = false;
        _connectError = '连接服务器失败';
      });
      return;
    }

    setState(() {
      _isConnecting = false;
    });

    // 并行加载数据
    await Future.wait([
      _loadKLines(),
      _loadRatioHistory(),
    ]);
  }

  Future<void> _loadData() async {
    if (_client == null || !_client!.isConnected) {
      await _connectAndLoad();
      return;
    }

    await Future.wait([
      _loadKLines(),
      _loadRatioHistory(),
    ]);
  }

  Future<void> _loadKLines() async {
    if (_client == null) return;

    setState(() {
      _isLoadingKLine = true;
      _klineError = null;
    });

    try {
      final daily = await _client!.getSecurityBars(
        market: widget.stock.market,
        code: widget.stock.code,
        category: klineTypeDaily,
        start: 0,
        count: 30,
      );
      final weekly = await _client!.getSecurityBars(
        market: widget.stock.market,
        code: widget.stock.code,
        category: klineTypeWeekly,
        start: 0,
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

  Future<void> _loadRatioHistory() async {
    if (_client == null) return;

    setState(() {
      _isLoadingRatio = true;
      _ratioError = null;
    });

    try {
      const days = 20;
      final allBars = <KLine>[];
      const totalBars = days * 240;
      var fetched = 0;

      while (fetched < totalBars) {
        final count = (totalBars - fetched).clamp(0, 800);
        final bars = await _client!.getSecurityBars(
          market: widget.stock.market,
          code: widget.stock.code,
          category: klineType1Min,
          start: fetched,
          count: count,
        );
        if (bars.isEmpty) break;
        allBars.addAll(bars);
        fetched += bars.length;
        if (bars.length < count) break;
      }

      // 按日期分组
      final Map<String, List<KLine>> grouped = {};
      for (final bar in allBars) {
        final dateKey =
            '${bar.datetime.year}-${bar.datetime.month.toString().padLeft(2, '0')}-${bar.datetime.day.toString().padLeft(2, '0')}';
        grouped.putIfAbsent(dateKey, () => []).add(bar);
      }

      // 计算每天的量比
      final results = <DailyRatio>[];
      final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

      for (final dateKey in sortedKeys.take(days)) {
        final dayBars = grouped[dateKey]!;
        final ratio = StockService.calculateRatio(dayBars);
        final parts = dateKey.split('-');
        results.add(DailyRatio(
          date: DateTime(
              int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
          ratio: ratio,
        ));
      }

      if (!mounted) return;
      setState(() {
        _ratioHistory = results;
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 连接中
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接服务器...'),
          ],
        ),
      );
    }

    // 连接失败
    if (_connectError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(_connectError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _connectAndLoad,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 正常显示
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKLineSection(),
            const Divider(),
            RatioHistoryList(
              ratios: _ratioHistory,
              isLoading: _isLoadingRatio,
              errorMessage: _ratioError,
              onRetry: _loadRatioHistory,
            ),
            const SizedBox(height: 24),
          ],
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
          Row(
            children: [
              Flexible(
                child: Text(
                  'K 线图',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(width: 8),
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
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 8),
                    Text(_klineError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loadKLines,
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
