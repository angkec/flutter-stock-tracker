import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/data_management_screen.dart';
import 'package:stock_rtwatcher/screens/industry_detail_screen.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/widgets/industry_rank_list.dart';
import 'package:stock_rtwatcher/widgets/sparkline_chart.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class IndustryScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const IndustryScreen({super.key, this.onIndustryTap});

  @override
  State<IndustryScreen> createState() => _IndustryScreenState();
}

class _IndustryScreenState extends State<IndustryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _hasCheckedTrend = false;
  bool _hasMarketDataWhenChecked = false;

  // 排序状态
  IndustrySortMode _sortMode = IndustrySortMode.ratioPercent;
  bool _sortAscending = false;

  // 筛选状态
  IndustryFilter _filter = const IndustryFilter();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onSortModeChanged(IndustrySortMode mode) {
    setState(() {
      if (_sortMode == mode) {
        _sortAscending = !_sortAscending;
      } else {
        _sortMode = mode;
        _sortAscending = false;
      }
    });
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterBottomSheet(
        currentFilter: _filter,
        onFilterChanged: (newFilter) {
          setState(() {
            _filter = newFilter;
          });
        },
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasCheckedTrend) {
      _hasCheckedTrend = true;
      _checkAndRefreshTrend();
    }
  }

  void _checkAndRefreshTrend() {
    final trendService = context.read<IndustryTrendService>();
    final marketProvider = context.read<MarketDataProvider>();

    if (marketProvider.allData.isNotEmpty) {
      _hasMarketDataWhenChecked = true;
      trendService.checkMissingDays();
    }
  }

  void _maybeRecheckTrend(MarketDataProvider marketProvider) {
    if (_hasCheckedTrend &&
        !_hasMarketDataWhenChecked &&
        marketProvider.allData.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkAndRefreshTrend();
        }
      });
      _hasMarketDataWhenChecked = true;
    }
  }

  Future<void> _manualRefreshTrend() async {
    final trendService = context.read<IndustryTrendService>();
    final marketProvider = context.read<MarketDataProvider>();

    if (marketProvider.allData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先获取市场数据')),
        );
      }
      return;
    }

    final missingDays = trendService.missingDays;
    final dataEmpty = trendService.trendData.isEmpty;
    if (missingDays > 0 || dataEmpty) {
      if (!mounted) return;
      final shouldFetch = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('趋势数据过时'),
          content: Text(dataEmpty
              ? '尚无历史趋势数据，是否拉取？'
              : '缺失 $missingDays 天数据，是否重新拉取？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('使用旧数据'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('重新拉取'),
            ),
          ],
        ),
      );

      if (shouldFetch == true && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DataManagementScreen(),
          ),
        );
        return;
      }
    }

    trendService.refresh();
  }

  List<IndustryStats> _calculateStats(
    List<StockMonitorData> data,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    final Map<String, List<StockMonitorData>> grouped = {};

    for (final stock in data) {
      final industry = stock.industry ?? '未知';
      grouped.putIfAbsent(industry, () => []).add(stock);
    }

    final result = <String, IndustryStats>{};
    for (final entry in grouped.entries) {
      int up = 0, down = 0, flat = 0, ratioAbove = 0, ratioBelow = 0;

      for (final stock in entry.value) {
        if (stock.changePercent > 0.001) {
          up++;
        } else if (stock.changePercent < -0.001) {
          down++;
        } else {
          flat++;
        }
        if (stock.ratio >= 1.0) {
          ratioAbove++;
        } else {
          ratioBelow++;
        }
      }

      result[entry.key] = IndustryStats(
        name: entry.key,
        upCount: up,
        downCount: down,
        flatCount: flat,
        ratioAbove: ratioAbove,
        ratioBelow: ratioBelow,
      );
    }

    final statsList = result.values.toList();

    final Map<String, double> sortValues = {};
    for (final stats in statsList) {
      switch (_sortMode) {
        case IndustrySortMode.ratioPercent:
          sortValues[stats.name] = stats.ratioSortValue;
          break;
        case IndustrySortMode.trendSlope:
          final trendData = _getTrendData(stats.name, trendService, todayTrend);
          sortValues[stats.name] = calculateTrendSlope(trendData);
          break;
        case IndustrySortMode.todayChange:
          final historical = trendService.getTrend(stats.name);
          sortValues[stats.name] = calculateTodayChange(
            todayTrend[stats.name],
            historical?.points ?? [],
          );
          break;
      }
    }

    statsList.sort((a, b) {
      final aValue = sortValues[a.name] ?? 0.0;
      final bValue = sortValues[b.name] ?? 0.0;

      if (aValue.isInfinite && bValue.isInfinite) return 0;
      if (aValue.isInfinite) return _sortAscending ? 1 : -1;
      if (bValue.isInfinite) return _sortAscending ? -1 : 1;

      final comparison = aValue.compareTo(bValue);
      return _sortAscending ? comparison : -comparison;
    });

    return statsList;
  }

  List<IndustryStats> _applyFilter(
    List<IndustryStats> stats,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    if (!_filter.hasActiveFilters) {
      return stats;
    }

    return stats.where((stat) {
      final todayRatio = todayTrend[stat.name]?.ratioAbovePercent;
      if (!filterMatchesMinRatioPercent(todayRatio, _filter.minRatioAbovePercent)) {
        return false;
      }

      if (_filter.consecutiveRisingDays != null) {
        final trendData = _getTrendData(stat.name, trendService, todayTrend);
        if (!filterMatchesConsecutiveRising(trendData, _filter.consecutiveRisingDays)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  List<double> _getTrendData(
    String industry,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    final historicalData = trendService.getTrend(industry);
    final points = <double>[];

    if (historicalData != null && historicalData.points.isNotEmpty) {
      final recentPoints = historicalData.points.length > 14
          ? historicalData.points.sublist(historicalData.points.length - 14)
          : historicalData.points;
      for (final point in recentPoints) {
        points.add(point.ratioAbovePercent);
      }
    }

    final todayPoint = todayTrend[industry];
    if (todayPoint != null) {
      points.add(todayPoint.ratioAbovePercent);
    }

    return points;
  }

  Widget _buildStaleDataBanner(BuildContext context, IndustryTrendService trendService) {
    final missingDays = trendService.missingDays;
    if (missingDays == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '历史数据缺失 $missingDays 天，部分趋势可能不准确',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DataManagementScreen(),
                ),
              );
            },
            child: const Text('前往更新'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();
    final rankService = context.watch<IndustryRankService>();
    final klineService = context.watch<HistoricalKlineService>();

    _maybeRecheckTrend(marketProvider);

    // 计算今日行业排名
    if (marketProvider.allData.isNotEmpty && !rankService.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          rankService.calculateTodayRanks(marketProvider.allData);
        }
      });
    }

    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);
    final allStats = _calculateStats(marketProvider.allData, trendService, todayTrend);
    final filteredStats = _applyFilter(allStats, trendService, todayTrend);

    final hasActiveFilter = _filter.hasActiveFilters;

    return Scaffold(
      appBar: AppBar(
        title: const Text('行业'),
        automaticallyImplyLeading: false,
        actions: [
          // 筛选按钮（仅行业统计 Tab）
          if (_tabController.index == 0)
            IconButton(
              onPressed: _showFilterBottomSheet,
              icon: Badge(
                isLabelVisible: hasActiveFilter,
                child: Icon(
                  hasActiveFilter ? Icons.filter_alt : Icons.filter_alt_outlined,
                  size: 20,
                ),
              ),
              tooltip: '筛选',
            ),
          // 更新趋势按钮
          if (marketProvider.allData.isNotEmpty && !trendService.isLoading)
            IconButton(
              onPressed: _manualRefreshTrend,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '更新趋势',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            _buildStaleDataBanner(context, trendService),
            // Tab 切换
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}), // 刷新 AppBar actions
                tabs: [
                  Tab(
                    text: hasActiveFilter
                        ? '行业统计 (${filteredStats.length}/${allStats.length})'
                        : '行业统计',
                  ),
                  const Tab(text: '排名趋势'),
                ],
              ),
            ),
            // Tab 内容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 行业统计
                  _buildStatsTab(
                    context,
                    marketProvider,
                    trendService,
                    filteredStats,
                    todayTrend,
                  ),
                  // Tab 2: 排名趋势
                  IndustryRankList(
                    fullHeight: true,
                    onFetchData: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DataManagementScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab(
    BuildContext context,
    MarketDataProvider marketProvider,
    IndustryTrendService trendService,
    List<IndustryStats> filteredStats,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    if (filteredStats.isEmpty && !marketProvider.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无数据',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '点击刷新按钮获取数据',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 表头
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 64,
                child: Text(
                  '行业',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '涨跌',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _SortableHeader(
                  title: '量比',
                  sortMode: IndustrySortMode.ratioPercent,
                  currentMode: _sortMode,
                  isAscending: _sortAscending,
                  onTap: () => _onSortModeChanged(IndustrySortMode.ratioPercent),
                ),
              ),
              SizedBox(
                width: 60,
                child: Center(
                  child: trendService.isLoading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _TrendSortHeader(
                          currentMode: _sortMode,
                          isAscending: _sortAscending,
                          onTrendSlopeTap: () =>
                              _onSortModeChanged(IndustrySortMode.trendSlope),
                          onTodayChangeTap: () =>
                              _onSortModeChanged(IndustrySortMode.todayChange),
                        ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => marketProvider.refresh(),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filteredStats.length,
              itemExtent: 48,
              itemBuilder: (context, index) => _buildRow(
                context,
                filteredStats[index],
                index,
                trendService,
                todayTrend,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    IndustryStats stats,
    int index,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    const upColor = Color(0xFFFF4444);
    const downColor = Color(0xFF00AA00);

    final trendData = _getTrendData(stats.name, trendService, todayTrend);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => IndustryDetailScreen(industry: stats.name),
          ),
        );
      },
      onLongPress: widget.onIndustryTap != null
          ? () => widget.onIndustryTap!(stats.name)
          : null,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: index.isOdd
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            // 行业名
            SizedBox(
              width: 64,
              child: Text(
                stats.name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 涨跌进度条 + 数字
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Row(
                        children: [
                          if (stats.upCount > 0)
                            Expanded(
                              flex: stats.upCount,
                              child: Container(height: 6, color: upColor),
                            ),
                          if (stats.downCount > 0)
                            Expanded(
                              flex: stats.downCount,
                              child: Container(height: 6, color: downColor),
                            ),
                          if (stats.upCount == 0 && stats.downCount == 0)
                            Expanded(
                              child: Container(
                                height: 6,
                                color: Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.upCount}↑ ${stats.downCount}↓',
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // 量比进度条 + 数字
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Row(
                        children: [
                          if (stats.ratioAbove > 0)
                            Expanded(
                              flex: stats.ratioAbove,
                              child: Container(height: 6, color: upColor),
                            ),
                          if (stats.ratioBelow > 0)
                            Expanded(
                              flex: stats.ratioBelow,
                              child: Container(height: 6, color: downColor),
                            ),
                          if (stats.ratioAbove == 0 && stats.ratioBelow == 0)
                            Expanded(
                              child: Container(
                                height: 6,
                                color: Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.ratioAbove}↑ ${stats.ratioBelow}↓',
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // 趋势迷你图
            SizedBox(
              width: 60,
              child: Center(
                child: trendData.isNotEmpty
                    ? SparklineChart(
                        data: trendData,
                        width: 56,
                        height: 24,
                        referenceValue: 50,
                      )
                    : Text(
                        '-',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 可排序的表头组件
class _SortableHeader extends StatelessWidget {
  final String title;
  final IndustrySortMode sortMode;
  final IndustrySortMode currentMode;
  final bool isAscending;
  final VoidCallback onTap;

  const _SortableHeader({
    required this.title,
    required this.sortMode,
    required this.currentMode,
    required this.isAscending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentMode == sortMode;
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 2),
            Icon(
              isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: color,
            ),
          ],
        ],
      ),
    );
  }
}

/// 趋势排序表头（支持两种排序模式）
class _TrendSortHeader extends StatelessWidget {
  final IndustrySortMode currentMode;
  final bool isAscending;
  final VoidCallback onTrendSlopeTap;
  final VoidCallback onTodayChangeTap;

  const _TrendSortHeader({
    required this.currentMode,
    required this.isAscending,
    required this.onTrendSlopeTap,
    required this.onTodayChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTrendSlope = currentMode == IndustrySortMode.trendSlope;
    final isTodayChange = currentMode == IndustrySortMode.todayChange;
    final isActive = isTrendSlope || isTodayChange;
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: () {
        if (isTrendSlope) {
          onTodayChangeTap();
        } else {
          onTrendSlopeTap();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isTodayChange ? '今变' : '趋势',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 2),
            Icon(
              isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: color,
            ),
          ],
        ],
      ),
    );
  }
}

/// 筛选底部面板
class _FilterBottomSheet extends StatefulWidget {
  final IndustryFilter currentFilter;
  final ValueChanged<IndustryFilter> onFilterChanged;

  const _FilterBottomSheet({
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late bool _consecutiveRisingEnabled;
  late int _consecutiveRisingDays;
  late bool _minRatioEnabled;
  late double _minRatioPercent;

  static const List<int> _dayOptions = [3, 5, 7];
  static const List<double> _percentOptions = [30, 40, 50, 60, 70];

  @override
  void initState() {
    super.initState();
    _consecutiveRisingEnabled = widget.currentFilter.consecutiveRisingDays != null;
    _consecutiveRisingDays = widget.currentFilter.consecutiveRisingDays ?? 3;
    _minRatioEnabled = widget.currentFilter.minRatioAbovePercent != null;
    _minRatioPercent = widget.currentFilter.minRatioAbovePercent ?? 50.0;
  }

  void _applyFilter() {
    final newFilter = IndustryFilter(
      consecutiveRisingDays: _consecutiveRisingEnabled ? _consecutiveRisingDays : null,
      minRatioAbovePercent: _minRatioEnabled ? _minRatioPercent : null,
    );
    widget.onFilterChanged(newFilter);
    Navigator.of(context).pop();
  }

  void _clearFilter() {
    widget.onFilterChanged(const IndustryFilter());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '筛选条件',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFilterSection(
              title: '连续上升天数',
              subtitle: '筛选趋势连续N天上升的行业',
              enabled: _consecutiveRisingEnabled,
              onEnabledChanged: (value) {
                setState(() {
                  _consecutiveRisingEnabled = value;
                });
              },
              child: Wrap(
                spacing: 8,
                children: _dayOptions.map((days) {
                  final isSelected = _consecutiveRisingDays == days;
                  return ChoiceChip(
                    label: Text('$days天'),
                    selected: isSelected,
                    onSelected: _consecutiveRisingEnabled
                        ? (selected) {
                            if (selected) {
                              setState(() {
                                _consecutiveRisingDays = days;
                              });
                            }
                          }
                        : null,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            _buildFilterSection(
              title: '今日占比',
              subtitle: '筛选今日量比>1股票占比超过X%的行业',
              enabled: _minRatioEnabled,
              onEnabledChanged: (value) {
                setState(() {
                  _minRatioEnabled = value;
                });
              },
              child: Wrap(
                spacing: 8,
                children: _percentOptions.map((percent) {
                  final isSelected = _minRatioPercent == percent;
                  return ChoiceChip(
                    label: Text('>${percent.toInt()}%'),
                    selected: isSelected,
                    onSelected: _minRatioEnabled
                        ? (selected) {
                            if (selected) {
                              setState(() {
                                _minRatioPercent = percent;
                              });
                            }
                          }
                        : null,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearFilter,
                    child: const Text('清除筛选'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _applyFilter,
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection({
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onEnabledChanged,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !enabled,
            child: child,
          ),
        ),
      ],
    );
  }
}
