import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/industry_detail_screen.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/widgets/sparkline_chart.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class IndustryScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const IndustryScreen({super.key, this.onIndustryTap});

  @override
  State<IndustryScreen> createState() => _IndustryScreenState();
}

class _IndustryScreenState extends State<IndustryScreen> {
  bool _hasCheckedTrend = false;
  bool _hasMarketDataWhenChecked = false; // 检查时是否有市场数据
  int _fetchProgress = 0;
  int _fetchTotal = 0;

  // 排序状态
  IndustrySortMode _sortMode = IndustrySortMode.ratioPercent;
  bool _sortAscending = false; // false = 降序（默认），true = 升序

  // 筛选状态
  IndustryFilter _filter = const IndustryFilter();

  void _onSortModeChanged(IndustrySortMode mode) {
    setState(() {
      if (_sortMode == mode) {
        // 如果点击同一列，切换排序方向
        _sortAscending = !_sortAscending;
      } else {
        // 切换到新列，默认降序
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

  Future<void> _checkAndRefreshTrend() async {
    final trendService = context.read<IndustryTrendService>();
    final marketProvider = context.read<MarketDataProvider>();
    final pool = context.read<TdxPool>();

    // 只有当有数据时才检查刷新
    if (marketProvider.allData.isNotEmpty) {
      _hasMarketDataWhenChecked = true;
      await trendService.checkAndRefresh(pool, marketProvider.allData);
    }
  }

  /// 在build中检查是否需要重新触发趋势检查
  void _maybeRecheckTrend(MarketDataProvider marketProvider) {
    // 如果之前检查时没有市场数据，但现在有了，需要重新检查
    if (_hasCheckedTrend && !_hasMarketDataWhenChecked && marketProvider.allData.isNotEmpty) {
      // 使用 addPostFrameCallback 避免在 build 中调用 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkAndRefreshTrend();
        }
      });
      _hasMarketDataWhenChecked = true; // 防止重复触发
    }
  }

  /// 检查是否需要显示刷新按钮
  /// 显示条件：有市场数据 且 (缺失天数>3 或 历史趋势数据为空)
  bool _shouldShowRefreshButton(
    MarketDataProvider marketProvider,
    IndustryTrendService trendService,
  ) {
    if (trendService.isLoading) return false;
    if (marketProvider.allData.isEmpty) return false;

    // 如果历史趋势数据为空，需要刷新
    if (trendService.trendData.isEmpty) return true;

    // 如果缺失天数>3，需要手动刷新
    if (trendService.missingDays > 3) return true;

    return false;
  }

  Future<void> _manualRefreshTrend() async {
    final trendService = context.read<IndustryTrendService>();
    final marketProvider = context.read<MarketDataProvider>();
    final pool = context.read<TdxPool>();

    if (marketProvider.allData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先获取市场数据')),
        );
      }
      return;
    }

    // 显示进度对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ProgressDialog(
        getProgress: () => _fetchProgress,
        getTotal: () => _fetchTotal,
      ),
    );

    try {
      await trendService.fetchHistoricalData(
        pool,
        marketProvider.allData,
        (current, total) {
          setState(() {
            _fetchProgress = current;
            _fetchTotal = total;
          });
        },
      );

      // 关闭对话框
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('趋势数据已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取趋势数据失败: $e')),
        );
      }
    }
  }

  /// 计算行业统计
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
        // 涨跌统计
        if (stock.changePercent > 0.001) {
          up++;
        } else if (stock.changePercent < -0.001) {
          down++;
        } else {
          flat++;
        }
        // 量比统计
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

    // Pre-compute sort values to avoid repeated calculations during sort
    // For N items, sort performs O(N log N) comparisons, so pre-computing
    // reduces function calls from O(N log N) to O(N)
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

    // Sort using pre-computed values
    statsList.sort((a, b) {
      final aValue = sortValues[a.name] ?? 0.0;
      final bValue = sortValues[b.name] ?? 0.0;

      // 处理 infinity 情况
      if (aValue.isInfinite && bValue.isInfinite) return 0;
      if (aValue.isInfinite) return _sortAscending ? 1 : -1;
      if (bValue.isInfinite) return _sortAscending ? -1 : 1;

      final comparison = aValue.compareTo(bValue);
      return _sortAscending ? comparison : -comparison;
    });

    return statsList;
  }

  /// 根据筛选条件过滤行业列表
  List<IndustryStats> _applyFilter(
    List<IndustryStats> stats,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    if (!_filter.hasActiveFilters) {
      return stats;
    }

    return stats.where((stat) {
      // 筛选今日占比
      final todayRatio = todayTrend[stat.name]?.ratioAbovePercent;
      if (!filterMatchesMinRatioPercent(todayRatio, _filter.minRatioAbovePercent)) {
        return false;
      }

      // 筛选连续上升天数
      if (_filter.consecutiveRisingDays != null) {
        final trendData = _getTrendData(stat.name, trendService, todayTrend);
        if (!filterMatchesConsecutiveRising(trendData, _filter.consecutiveRisingDays)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// 获取行业趋势数据（历史 + 今日）
  List<double> _getTrendData(
    String industry,
    IndustryTrendService trendService,
    Map<String, DailyRatioPoint> todayTrend,
  ) {
    final historicalData = trendService.getTrend(industry);
    final points = <double>[];

    // 添加历史数据（最近14天）
    if (historicalData != null && historicalData.points.isNotEmpty) {
      final recentPoints = historicalData.points.length > 14
          ? historicalData.points.sublist(historicalData.points.length - 14)
          : historicalData.points;
      for (final point in recentPoints) {
        points.add(point.ratioAbovePercent);
      }
    }

    // 添加今日数据
    final todayPoint = todayTrend[industry];
    if (todayPoint != null) {
      points.add(todayPoint.ratioAbovePercent);
    }

    return points;
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();

    // 检查是否需要重新触发趋势检查
    _maybeRecheckTrend(marketProvider);

    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);
    final allStats = _calculateStats(marketProvider.allData, trendService, todayTrend);
    final filteredStats = _applyFilter(allStats, trendService, todayTrend);

    // 决定是否显示更新按钮
    final showRefreshButton = _shouldShowRefreshButton(marketProvider, trendService);
    final hasActiveFilter = _filter.hasActiveFilters;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasActiveFilter
            ? '行业 (${filteredStats.length}/${allStats.length})'
            : '行业'),
        automaticallyImplyLeading: false,
        actions: [
          // 筛选按钮
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
          if (showRefreshButton)
            TextButton.icon(
              onPressed: _manualRefreshTrend,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('更新趋势'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            Expanded(
              child: filteredStats.isEmpty && !marketProvider.isLoading
                  ? Center(
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
                    )
                  : Column(
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
                              // 量比列 - 可点击排序
                              Expanded(
                                child: _SortableHeader(
                                  title: '量比',
                                  sortMode: IndustrySortMode.ratioPercent,
                                  currentMode: _sortMode,
                                  isAscending: _sortAscending,
                                  onTap: () => _onSortModeChanged(IndustrySortMode.ratioPercent),
                                ),
                              ),
                              // 趋势列 - 可点击排序（两种模式）
                              SizedBox(
                                width: 60,
                                child: Center(
                                  child: trendService.isLoading
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
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
                    ),
            ),
          ],
        ),
      ),
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

/// 进度对话框
class _ProgressDialog extends StatefulWidget {
  final int Function() getProgress;
  final int Function() getTotal;

  const _ProgressDialog({
    required this.getProgress,
    required this.getTotal,
  });

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  @override
  void initState() {
    super.initState();
    _startUpdating();
  }

  void _startUpdating() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.getProgress();
    final total = widget.getTotal();

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在获取趋势数据',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            total > 0 ? '($progress/$total)' : '准备中...',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
        // 循环切换：无 -> 斜率 -> 今变 -> 斜率 -> ...
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
            // 标题
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

            // 连续上升天数筛选
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

            // 今日占比筛选
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

            // 按钮
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
