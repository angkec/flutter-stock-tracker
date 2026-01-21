import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/pullback_config.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/widgets/kline_chart.dart';
import 'package:stock_rtwatcher/widgets/minute_chart.dart';
import 'package:stock_rtwatcher/widgets/ratio_history_list.dart';
import 'package:stock_rtwatcher/widgets/industry_heat_bar.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:provider/provider.dart';

/// K线图显示模式
enum ChartMode { minute, daily, weekly }

/// 股票详情页
class StockDetailScreen extends StatefulWidget {
  final Stock stock;

  /// 可选的股票列表，用于左右滑动切换
  final List<Stock>? stockList;

  /// 当前股票在列表中的索引
  final int initialIndex;

  const StockDetailScreen({
    super.key,
    required this.stock,
    this.stockList,
    this.initialIndex = 0,
  });

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
  List<KLine> _todayBars = []; // 当日分钟数据
  List<DailyRatio> _ratioHistory = [];

  bool _isLoadingKLine = false;
  bool _isLoadingRatio = false;
  String? _klineError;
  String? _ratioError;

  ChartMode _chartMode = ChartMode.daily; // 默认显示日线

  // 当前显示的股票索引和股票
  late int _currentIndex;
  late Stock _currentStock;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentStock = widget.stock;

    // 如果有股票列表，初始化 PageController
    if (widget.stockList != null && widget.stockList!.length > 1) {
      _pageController = PageController(initialPage: _currentIndex);
    }

    _connectAndLoad();
  }

  @override
  void dispose() {
    _client?.disconnect();
    _pageController?.dispose();
    super.dispose();
  }

  /// 切换到指定索引的股票
  void _switchToStock(int index) {
    if (widget.stockList == null) return;
    if (index < 0 || index >= widget.stockList!.length) return;
    if (index == _currentIndex) return;

    setState(() {
      _currentIndex = index;
      _currentStock = widget.stockList![index];
      // 重置数据
      _dailyBars = [];
      _weeklyBars = [];
      _todayBars = [];
      _ratioHistory = [];
      _klineError = null;
      _ratioError = null;
    });

    // 重新加载数据
    _loadData();
  }

  Future<void> _connectAndLoad() async {
    setState(() {
      _isConnecting = true;
      _connectError = null;
    });

    // 并行尝试所有服务器，使用第一个成功的（快速连接）
    final completer = Completer<TdxClient?>();
    var pendingCount = TdxClient.servers.length;

    for (final server in TdxClient.servers) {
      final host = server['host'] as String;
      final port = server['port'] as int;

      _tryConnect(host, port).then((client) {
        if (client != null && !completer.isCompleted) {
          completer.complete(client);
        } else {
          pendingCount--;
          if (pendingCount == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      });
    }

    _client = await completer.future;

    if (!mounted) return;

    if (_client == null) {
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

  Future<TdxClient?> _tryConnect(String host, int port) async {
    final client = TdxClient();
    if (await client.connect(host, port)) {
      return client;
    }
    return null;
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
        market: _currentStock.market,
        code: _currentStock.code,
        category: klineTypeDaily,
        start: 0,
        count: 30,
      );
      final weekly = await _client!.getSecurityBars(
        market: _currentStock.market,
        code: _currentStock.code,
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
          market: _currentStock.market,
          code: _currentStock.code,
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

      // 提取当日分钟数据（用于分时图）
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final todayBars = grouped[todayKey] ?? [];

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
        _todayBars = todayBars;
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

  /// 通过 PageController 切换页面（带动画，支持循环）
  void _animateToStock(int index) {
    if (_pageController == null || widget.stockList == null) return;

    final length = widget.stockList!.length;
    // 循环处理索引
    final targetIndex = index < 0
        ? length - 1
        : (index >= length ? 0 : index);

    // 跨越边界时直接跳转（无法平滑动画）
    if ((index < 0 && _currentIndex == 0) ||
        (index >= length && _currentIndex == length - 1)) {
      _pageController!.jumpToPage(targetIndex);
      _switchToStock(targetIndex);
    } else {
      _pageController!.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasStockList = widget.stockList != null && widget.stockList!.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_currentStock.name} (${_currentStock.code})',
              style: const TextStyle(fontSize: 16),
            ),
            if (hasStockList)
              Text(
                '${_currentIndex + 1} / ${widget.stockList!.length}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: hasStockList
            ? [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _animateToStock(_currentIndex - 1),
                  tooltip: '上一只',
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _animateToStock(_currentIndex + 1),
                  tooltip: '下一只',
                ),
              ]
            : null,
      ),
      body: hasStockList
          ? GestureDetector(
              onHorizontalDragUpdate: (details) {
                // 手动控制 PageView 跟随手指移动
                _pageController?.position.moveTo(
                  _pageController!.position.pixels - details.delta.dx,
                );
              },
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 300) {
                  _animateToStock(_currentIndex - 1);
                } else if (velocity < -300) {
                  _animateToStock(_currentIndex + 1);
                } else {
                  // 回弹到当前页
                  _pageController?.animateToPage(
                    _currentIndex,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.stockList!.length,
                onPageChanged: (index) {
                  if (index != _currentIndex) {
                    _switchToStock(index);
                  }
                },
                itemBuilder: (context, index) {
                  // 当前页显示完整内容
                  if (index == _currentIndex) {
                    return _buildBody();
                  }
                  // 相邻页显示占位
                  return Center(
                    child: Text(
                      widget.stockList![index].name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  );
                },
              ),
            )
          : _buildBody(),
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
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKLineSection(),
            _buildIndustryHeatBar(),
            const Divider(),
            RatioHistoryList(
              ratios: _ratioHistory,
              isLoading: _isLoadingRatio,
              errorMessage: _ratioError,
              onRetry: _loadRatioHistory,
            ),
            const Divider(),
            _buildPullbackScoreCard(),
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
                  _chartMode == ChartMode.minute ? '分时图' : 'K 线图',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<ChartMode>(
                segments: const [
                  ButtonSegment(value: ChartMode.minute, label: Text('分时')),
                  ButtonSegment(value: ChartMode.daily, label: Text('日线')),
                  ButtonSegment(value: ChartMode.weekly, label: Text('周线')),
                ],
                selected: {_chartMode},
                onSelectionChanged: (selected) {
                  setState(() => _chartMode = selected.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildChart(),
        ],
      ),
    );
  }

  Widget _buildChart() {
    // 分时图使用 ratio 数据的加载状态
    if (_chartMode == ChartMode.minute) {
      if (_isLoadingRatio) {
        return const SizedBox(
          height: 280,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_ratioError != null) {
        return SizedBox(
          height: 280,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 8),
                Text(_ratioError!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loadRatioHistory,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        );
      }
      return MinuteChart(
        bars: _todayBars,
        preClose: _currentStock.preClose,
      );
    }

    // 日线/周线使用 K 线数据的加载状态
    if (_isLoadingKLine) {
      return const SizedBox(
        height: 280,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_klineError != null) {
      return SizedBox(
        height: 280,
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
      );
    }
    return KLineChart(
      bars: _chartMode == ChartMode.daily ? _dailyBars : _weeklyBars,
      ratios: _chartMode == ChartMode.daily ? _ratioHistory : null,
    );
  }

  Widget _buildIndustryHeatBar() {
    final provider = context.watch<MarketDataProvider>();
    final industry = provider.industryService.getIndustry(_currentStock.code);

    if (industry == null) {
      return const SizedBox.shrink();
    }

    final heat = provider.getIndustryHeat(industry);
    if (heat == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          '板块: $industry (暂无热度数据)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey,
          ),
        ),
      );
    }

    final changeDistribution = provider.getIndustryChangeDistribution(industry);

    return IndustryHeatBar(
      industryName: industry,
      hotCount: heat.hot,
      coldCount: heat.cold,
      changeDistribution: changeDistribution,
    );
  }

  Widget _buildPullbackScoreCard() {
    final pullbackService = context.watch<PullbackService>();
    final config = pullbackService.config;
    final marketProvider = context.watch<MarketDataProvider>();

    // 获取该股票的分钟量比
    final stockData = marketProvider.allData
        .where((d) => d.stock.code == _currentStock.code)
        .firstOrNull;
    final minuteRatio = stockData?.ratio;

    // 需要至少7根日K线
    if (_dailyBars.length < 7) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '回踩条件检测',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isLoadingKLine ? '加载中...' : '日K数据不足，无法检测',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    // 取最后7根K线
    final bars = _dailyBars.length > 7
        ? _dailyBars.sublist(_dailyBars.length - 7)
        : _dailyBars;

    final prev5 = bars.sublist(0, 5);
    final yesterday = bars[5];
    final today = bars[6];

    // 计算各项指标
    final avg5Volume = prev5.map((b) => b.volume).reduce((a, b) => a + b) / 5;
    final yesterdayVolumeRatio = yesterday.volume / avg5Volume;
    final yesterdayGain = (yesterday.close - yesterday.open) / yesterday.open;
    final todayDrop = today.close < today.open
        ? (today.open - today.close) / today.open
        : 0.0;
    final dropRatio = yesterdayGain > 0 ? todayDrop / yesterdayGain : 0.0;
    final dailyRatio = today.volume / yesterday.volume;
    final isTodayShrink = today.volume < yesterday.volume;
    final isTodayDown = today.close < today.open;
    final isBelowYesterdayHigh = today.close < yesterday.high;

    // 判断各项是否通过
    final pass1 = yesterdayVolumeRatio > config.volumeMultiplier;
    final pass2 = yesterdayGain > config.minYesterdayGain;
    final pass3 = isTodayShrink;
    // pass4 根据 dropMode 决定
    final bool pass4;
    switch (config.dropMode) {
      case DropMode.todayDown:
        pass4 = isTodayDown;
        break;
      case DropMode.belowYesterdayHigh:
        pass4 = isBelowYesterdayHigh;
        break;
      case DropMode.none:
        pass4 = true;
        break;
    }
    final pass5 = dropRatio < config.maxDropRatio;
    final pass6 = dailyRatio <= config.maxDailyRatio;
    final pass7 = minuteRatio != null && minuteRatio >= config.minMinuteRatio;

    final allPass = pass1 && pass2 && pass3 && pass4 && pass5 && pass6 && pass7;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '回踩条件检测',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: allPass ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  allPass ? '符合' : '不符合',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildScoreRow(
            '昨日放量',
            '${yesterdayVolumeRatio.toStringAsFixed(2)}x',
            '>${config.volumeMultiplier}x',
            pass1,
          ),
          _buildScoreRow(
            '昨日涨幅',
            '${(yesterdayGain * 100).toStringAsFixed(2)}%',
            '>${(config.minYesterdayGain * 100).toStringAsFixed(0)}%',
            pass2,
          ),
          _buildScoreRow(
            '今日缩量',
            isTodayShrink ? '是' : '否',
            '是',
            pass3,
          ),
          if (config.dropMode != DropMode.none)
            _buildScoreRow(
              config.dropMode == DropMode.todayDown ? '今日下跌' : '低于昨高',
              config.dropMode == DropMode.todayDown
                  ? (isTodayDown ? '是' : '否')
                  : (isBelowYesterdayHigh ? '是' : '否'),
              '是',
              pass4,
            ),
          _buildScoreRow(
            '跌幅/涨幅',
            '${(dropRatio * 100).toStringAsFixed(1)}%',
            '<${(config.maxDropRatio * 100).toStringAsFixed(0)}%',
            pass5,
          ),
          _buildScoreRow(
            '日K量比',
            dailyRatio.toStringAsFixed(2),
            '<=${config.maxDailyRatio}',
            pass6,
          ),
          _buildScoreRow(
            '分钟量比',
            minuteRatio?.toStringAsFixed(2) ?? '-',
            '>=${config.minMinuteRatio}',
            pass7,
          ),
        ],
      ),
    );
  }

  Widget _buildScoreRow(String label, String value, String condition, bool pass) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            pass ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: pass ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: pass ? Colors.green : Colors.red,
              ),
            ),
          ),
          Text(
            condition,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
