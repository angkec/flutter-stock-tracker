import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/daily_ratio.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/widgets/minute_chart.dart';
import 'package:stock_rtwatcher/widgets/ratio_history_list.dart';
import 'package:stock_rtwatcher/widgets/industry_heat_bar.dart';
import 'package:stock_rtwatcher/widgets/industry_trend_chart.dart';
import 'package:stock_rtwatcher/widgets/linked_dual_kline_view.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/adx_subchart.dart';
import 'package:stock_rtwatcher/widgets/macd_subchart.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/models/linked_layout_config.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';
import 'package:stock_rtwatcher/services/linked_layout_solver.dart';
import 'package:stock_rtwatcher/widgets/linked_layout_debug_sheet.dart';
import 'package:stock_rtwatcher/widgets/power_system_candle_color.dart';

/// K线图显示模式
enum ChartMode { minute, daily, weekly, linked }

/// 股票详情页
class StockDetailScreen extends StatefulWidget {
  final Stock stock;

  /// 可选的股票列表，用于左右滑动切换
  final List<Stock>? stockList;

  /// 当前股票在列表中的索引
  final int initialIndex;
  final ChartMode initialChartMode;
  final bool showWatchlistToggle;
  final bool showIndustryHeatSection;
  final bool skipAutoConnectForTest;
  final List<KLine>? initialDailyBars;
  final List<KLine>? initialWeeklyBars;
  final List<DailyRatio>? initialRatioHistory;
  final MacdCacheStore? macdCacheStoreForTest;
  final AdxCacheStore? adxCacheStoreForTest;
  final EmaCacheStore? emaCacheStoreForTest;
  final PowerSystemCacheStore? powerSystemCacheStoreForTest;

  const StockDetailScreen({
    super.key,
    required this.stock,
    this.stockList,
    this.initialIndex = 0,
    this.initialChartMode = ChartMode.daily,
    this.showWatchlistToggle = true,
    this.showIndustryHeatSection = true,
    this.skipAutoConnectForTest = false,
    this.initialDailyBars,
    this.initialWeeklyBars,
    this.initialRatioHistory,
    this.macdCacheStoreForTest,
    this.adxCacheStoreForTest,
    this.emaCacheStoreForTest,
    this.powerSystemCacheStoreForTest,
  });

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  static const int _dailyTargetBars = 260;
  static const int _weeklyTargetBars = 100;
  static const int _weeklyRangeDays = 760;

  // 独立的 TDX 连接，不和全市场数据共用
  TdxClient? _client;
  bool _isConnecting = true;
  String? _connectError;

  List<KLine> _dailyBars = [];
  List<KLine> _weeklyBars = [];
  List<KLine> _todayBars = []; // 当日分钟数据
  List<DailyRatio> _ratioHistory = [];

  // EMA 覆盖线序列（与对应 bars 等长，无值位置为 null）
  List<double?>? _dailyEmaShort;
  List<double?>? _dailyEmaLong;
  List<double?>? _weeklyEmaShort;
  List<double?>? _weeklyEmaLong;
  CandleColorResolver? _dailyPowerSystemColorResolver;
  CandleColorResolver? _weeklyPowerSystemColorResolver;

  bool _isLoadingKLine = false;
  bool _isLoadingRatio = false;
  String? _klineError;
  String? _ratioError;

  late ChartMode _chartMode; // 默认显示日线
  bool _isChartScaling = false; // K线图是否正在缩放

  // 突破检测结果缓存（用于同步访问异步计算的结果）
  Map<int, BreakoutDetectionResult?> _detectionResultsCache = {};
  Set<int> _breakoutIndices = {};
  Map<int, int> _nearMissIndices = {};

  // 当前显示的股票索引和股票
  late int _currentIndex;
  late Stock _currentStock;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _currentStock = widget.stock;
    _chartMode = widget.initialChartMode;

    // 如果有股票列表，初始化 PageController
    if (widget.stockList != null && widget.stockList!.length > 1) {
      _pageController = PageController(initialPage: _currentIndex);
    }

    if (widget.skipAutoConnectForTest) {
      _isConnecting = false;
      _dailyBars = widget.initialDailyBars ?? const <KLine>[];
      _weeklyBars = widget.initialWeeklyBars ?? const <KLine>[];
      _ratioHistory = widget.initialRatioHistory ?? const <DailyRatio>[];
      // Load EMA overlays even in test mode (uses emaCacheStoreForTest if set)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadEmaOverlays(daily: _dailyBars, weekly: _weeklyBars);
        }
      });
      return;
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
      _detectionResultsCache = {};
      _breakoutIndices = {};
      _nearMissIndices = {};
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
    await Future.wait([_loadKLines(), _loadRatioHistory()]);
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

    await Future.wait([_loadKLines(), _loadRatioHistory()]);
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
        count: _dailyTargetBars,
      );
      final weekly = await _loadWeeklyBarsLocalFirst();

      if (!mounted) return;
      setState(() {
        _dailyBars = daily;
        _weeklyBars = weekly;
        _isLoadingKLine = false;
      });

      // 异步加载 EMA 缓存（不阻塞 K 线显示）
      _loadEmaOverlays(daily: daily, weekly: weekly);

      // 预加载突破检测结果（异步，不阻塞UI）
      _preloadDetectionResults();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _klineError = '加载 K 线失败: $e';
        _isLoadingKLine = false;
      });
    }
  }

  Future<void> _loadEmaOverlays({
    required List<KLine> daily,
    required List<KLine> weekly,
  }) async {
    final store = widget.emaCacheStoreForTest ?? EmaCacheStore();
    final powerStore =
        widget.powerSystemCacheStoreForTest ?? PowerSystemCacheStore();
    final code = _currentStock.code;

    final emaResults = await Future.wait([
      store.loadSeries(stockCode: code, dataType: KLineDataType.daily),
      store.loadSeries(stockCode: code, dataType: KLineDataType.weekly),
    ]);

    if (!mounted) return;

    final dailySeries = emaResults[0] as EmaCacheSeries?;
    final weeklySeries = emaResults[1] as EmaCacheSeries?;

    setState(() {
      if (dailySeries != null) {
        final aligned = _alignEmaToBars(daily, dailySeries);
        _dailyEmaShort = aligned.$1;
        _dailyEmaLong = aligned.$2;
      } else {
        _dailyEmaShort = null;
        _dailyEmaLong = null;
      }
      if (weeklySeries != null) {
        final aligned = _alignEmaToBars(weekly, weeklySeries);
        _weeklyEmaShort = aligned.$1;
        _weeklyEmaLong = aligned.$2;
      } else {
        _weeklyEmaShort = null;
        _weeklyEmaLong = null;
      }
    });

    final powerResults = await Future.wait([
      powerStore.loadSeries(stockCode: code, dataType: KLineDataType.daily),
      powerStore.loadSeries(stockCode: code, dataType: KLineDataType.weekly),
    ]);
    if (!mounted) return;

    final dailyPowerSeries = powerResults[0] as PowerSystemCacheSeries?;
    final weeklyPowerSeries = powerResults[1] as PowerSystemCacheSeries?;
    setState(() {
      _dailyPowerSystemColorResolver = dailyPowerSeries == null
          ? null
          : PowerSystemCandleColor.fromSeries(dailyPowerSeries);
      _weeklyPowerSystemColorResolver = weeklyPowerSeries == null
          ? null
          : PowerSystemCandleColor.fromSeries(weeklyPowerSeries);
    });
  }

  /// Aligns EMA points to bars by date. Returns (shortSeries, longSeries),
  /// each list is the same length as [bars], with null where no EMA point
  /// matches that bar's date.
  (List<double?>, List<double?>) _alignEmaToBars(
    List<KLine> bars,
    EmaCacheSeries series,
  ) {
    // Build a date-keyed map from EMA points
    final pointMap = <String, EmaPoint>{};
    for (final p in series.points) {
      final key = '${p.datetime.year}-${p.datetime.month}-${p.datetime.day}';
      pointMap[key] = p;
    }

    final shortList = List<double?>.filled(bars.length, null);
    final longList = List<double?>.filled(bars.length, null);

    for (var i = 0; i < bars.length; i++) {
      final d = bars[i].datetime;
      final key = '${d.year}-${d.month}-${d.day}';
      final point = pointMap[key];
      if (point != null) {
        shortList[i] = point.emaShort;
        longList[i] = point.emaLong;
      }
    }

    return (shortList, longList);
  }

  DateRange _buildWeeklyDateRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999);
    final start = end.subtract(const Duration(days: _weeklyRangeDays));
    return DateRange(start, end);
  }

  Future<List<KLine>> _loadWeeklyBarsLocalFirst() async {
    final dateRange = _buildWeeklyDateRange();

    try {
      final repository = context.read<DataRepository>();

      final localResult = await repository.getKlines(
        stockCodes: [_currentStock.code],
        dateRange: dateRange,
        dataType: KLineDataType.weekly,
      );
      final localBars = localResult[_currentStock.code] ?? const <KLine>[];
      if (localBars.length >= _weeklyTargetBars) {
        return localBars;
      }

      await repository.fetchMissingData(
        stockCodes: [_currentStock.code],
        dateRange: dateRange,
        dataType: KLineDataType.weekly,
      );

      final refreshedResult = await repository.getKlines(
        stockCodes: [_currentStock.code],
        dateRange: dateRange,
        dataType: KLineDataType.weekly,
      );
      final refreshedBars =
          refreshedResult[_currentStock.code] ?? const <KLine>[];
      if (refreshedBars.isNotEmpty) {
        return refreshedBars;
      }

      return localBars;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[StockDetail] weekly local-first load failed: $error');
        debugPrint('[StockDetail] weekly local-first stack: $stackTrace');
      }
    }

    if (_client != null && _client!.isConnected) {
      try {
        return await _client!.getSecurityBars(
          market: _currentStock.market,
          code: _currentStock.code,
          category: klineTypeWeekly,
          start: 0,
          count: _weeklyTargetBars,
        );
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[StockDetail] weekly remote fallback failed: $error');
          debugPrint('[StockDetail] weekly remote fallback stack: $stackTrace');
        }
      }
    }

    return const <KLine>[];
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
        results.add(
          DailyRatio(
            date: DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            ),
            ratio: ratio,
          ),
        );
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

  /// 预加载突破检测结果到缓存
  /// 在日K数据加载完成后调用，用于将异步检测结果预先计算并缓存
  Future<void> _preloadDetectionResults() async {
    if (_dailyBars.isEmpty) return;

    final stockCode =
        _currentStock.code; // Capture at start to detect stock switches
    final breakoutService = context.read<BreakoutService>();

    // 计算突破日标记（异步）
    final breakouts = await breakoutService.findBreakoutDays(
      _dailyBars,
      stockCode: stockCode,
    );

    // 计算近似命中（同步）
    final nearMisses = breakoutService.findNearMissBreakoutDays(_dailyBars);
    // 从近似命中中移除已经是突破日的索引
    nearMisses.removeWhere((key, _) => breakouts.contains(key));

    // 计算每个索引的检测结果（并行执行）
    // 从索引5开始（需要至少5根K线计算均量）
    final futures = <Future<MapEntry<int, BreakoutDetectionResult?>>>[];
    for (int i = 5; i < _dailyBars.length; i++) {
      futures.add(
        breakoutService
            .getDetectionResult(_dailyBars, i, stockCode: stockCode)
            .then((result) => MapEntry(i, result)),
      );
    }
    final entries = await Future.wait(futures);
    final newCache = Map.fromEntries(entries);

    if (mounted && _currentStock.code == stockCode) {
      // Verify still same stock
      setState(() {
        _breakoutIndices = breakouts;
        _nearMissIndices = nearMisses;
        _detectionResultsCache = newCache;
      });
    }
  }

  /// 构建自选股切换按钮
  Widget _buildWatchlistToggle() {
    final watchlistService = context.watch<WatchlistService>();
    final isInWatchlist = watchlistService.contains(_currentStock.code);

    return IconButton(
      icon: Icon(
        isInWatchlist ? Icons.star : Icons.star_outline,
        color: isInWatchlist ? Colors.amber : null,
      ),
      onPressed: () async {
        if (isInWatchlist) {
          await watchlistService.removeStock(_currentStock.code);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已从自选移除: ${_currentStock.name}'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          await watchlistService.addStock(_currentStock.code);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('已加入自选: ${_currentStock.name}'),
                duration: const Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
      tooltip: isInWatchlist ? '从自选移除' : '加入自选',
    );
  }

  PopupMenuButton<String> _buildMoreMenu() {
    return PopupMenuButton<String>(
      key: const ValueKey('stock_detail_more_menu_button'),
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'linked_layout_debug') {
          _openLinkedLayoutDebugSheet();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'linked_layout_debug',
          child: Text('联动布局调试'),
        ),
      ],
    );
  }

  Future<void> _openLinkedLayoutDebugSheet() async {
    final service = context.read<LinkedLayoutConfigService?>();
    if (service == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未注入联动布局配置服务，无法打开调试面板'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<LinkedLayoutConfigService>.value(
        value: service,
        child: const LinkedLayoutDebugSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStockList =
        widget.stockList != null && widget.stockList!.length > 1;

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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if (widget.showWatchlistToggle) _buildWatchlistToggle(),
          _buildMoreMenu(),
        ],
      ),
      body: hasStockList
          ? PageView.builder(
              controller: _pageController,
              // 缩放时禁用 PageView 滑动
              physics: _isChartScaling
                  ? const NeverScrollableScrollPhysics()
                  : null,
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _connectError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _connectAndLoad, child: const Text('重试')),
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
            if (widget.showIndustryHeatSection) ...[
              _buildIndustryHeatBar(),
              const Divider(),
            ],
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SegmentedButton<ChartMode>(
              segments: const [
                ButtonSegment(value: ChartMode.minute, label: Text('分时')),
                ButtonSegment(value: ChartMode.daily, label: Text('日线')),
                ButtonSegment(value: ChartMode.weekly, label: Text('周线')),
                ButtonSegment(value: ChartMode.linked, label: Text('联动')),
              ],
              selected: {_chartMode},
              onSelectionChanged: (selected) {
                setState(() => _chartMode = selected.first);
              },
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
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
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 8),
                Text(
                  _ratioError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
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
      return MinuteChart(bars: _todayBars, preClose: _currentStock.preClose);
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
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                _klineError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _loadKLines, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    if (_chartMode == ChartMode.linked) {
      final layoutConfig =
          context.watch<LinkedLayoutConfigService?>()?.config ??
          const LinkedLayoutConfig.balanced();
      final resolvedLayout = LinkedLayoutSolver.resolve(
        availableHeight: MediaQuery.sizeOf(context).height * 0.72,
        topSubchartCount: 2,
        bottomSubchartCount: 2,
        config: layoutConfig,
      );

      return SizedBox(
        height: resolvedLayout.containerHeight,
        child: LinkedDualKlineView(
          stockCode: _currentStock.code,
          weeklyBars: _weeklyBars,
          dailyBars: _dailyBars,
          ratios: _ratioHistory,
          layout: resolvedLayout,
          macdCacheStoreForTest: widget.macdCacheStoreForTest,
          adxCacheStoreForTest: widget.adxCacheStoreForTest,
          emaCacheStoreForTest: widget.emaCacheStoreForTest,
          powerSystemCacheStoreForTest: widget.powerSystemCacheStoreForTest,
        ),
      );
    }

    // 使用预加载的突破日标记和近似命中（仅日K）
    final markedIndices = _chartMode == ChartMode.daily
        ? _breakoutIndices
        : null;
    final nearMissIndices = _chartMode == ChartMode.daily
        ? _nearMissIndices
        : null;

    return KLineChartWithSubCharts(
      stockCode: _currentStock.code,
      bars: _chartMode == ChartMode.daily ? _dailyBars : _weeklyBars,
      ratios: _chartMode == ChartMode.daily ? _ratioHistory : null,
      markedIndices: markedIndices,
      nearMissIndices: nearMissIndices,
      showWeeklySeparators: _chartMode == ChartMode.daily,
      getDetectionResult: _chartMode == ChartMode.daily
          ? (index) => _detectionResultsCache[index]
          : null,
      onScaling: (isScaling) {
        setState(() => _isChartScaling = isScaling);
      },
      emaShortSeries: _chartMode == ChartMode.daily
          ? _dailyEmaShort
          : _weeklyEmaShort,
      emaLongSeries: _chartMode == ChartMode.daily
          ? _dailyEmaLong
          : _weeklyEmaLong,
      candleColorResolver: _chartMode == ChartMode.daily
          ? _dailyPowerSystemColorResolver
          : _weeklyPowerSystemColorResolver,
      subCharts: [
        MacdSubChart(
          key: ValueKey('stock_detail_macd_${_chartMode.name}'),
          dataType: _chartMode == ChartMode.daily
              ? KLineDataType.daily
              : KLineDataType.weekly,
          cacheStore: widget.macdCacheStoreForTest,
          chartKey: ValueKey('stock_detail_macd_paint_${_chartMode.name}'),
        ),
        AdxSubChart(
          key: ValueKey('stock_detail_adx_${_chartMode.name}'),
          dataType: _chartMode == ChartMode.daily
              ? KLineDataType.daily
              : KLineDataType.weekly,
          cacheStore: widget.adxCacheStoreForTest,
          chartKey: ValueKey('stock_detail_adx_paint_${_chartMode.name}'),
        ),
      ],
    );
  }

  Widget _buildIndustryHeatBar() {
    final provider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();
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
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      );
    }

    final changeDistribution = provider.getIndustryChangeDistribution(industry);

    // 获取行业趋势数据
    final trendData = _getIndustryTrendData(trendService, provider, industry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 原有的热度条
        IndustryHeatBar(
          industryName: industry,
          hotCount: heat.hot,
          coldCount: heat.cold,
          changeDistribution: changeDistribution,
        ),
        // 行业趋势折线图
        if (trendData.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IndustryTrendChart(data: trendData, height: 100),
          ),
      ],
    );
  }

  /// 获取行业趋势数据（历史 + 今日）
  List<DailyRatioPoint> _getIndustryTrendData(
    IndustryTrendService trendService,
    MarketDataProvider provider,
    String industry,
  ) {
    final historicalData = trendService.getTrend(industry);
    final points = <DailyRatioPoint>[];

    // 添加历史数据
    if (historicalData != null && historicalData.points.isNotEmpty) {
      points.addAll(historicalData.points);
    }

    // 添加今日数据
    final todayTrend = trendService.calculateTodayTrend(provider.allData);
    final todayPoint = todayTrend[industry];
    if (todayPoint != null) {
      points.add(todayPoint);
    }

    return points;
  }
}
