import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_config_store.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/industry_buildup_stage.dart';
import 'package:stock_rtwatcher/models/industry_buildup_tag_config.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/widgets/industry_ema_breadth_chart.dart';
import 'package:stock_rtwatcher/widgets/industry_trend_chart.dart';
import 'package:stock_rtwatcher/widgets/market_stats_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

/// 固定表头代理
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyHeaderDelegate({required this.child});

  @override
  double get minExtent => 44.0;

  @override
  double get maxExtent => 44.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// 行业详情页
class IndustryDetailScreen extends StatefulWidget {
  final String industry;
  final IndustryEmaBreadthConfigStore? emaBreadthConfigStoreForTest;

  const IndustryDetailScreen({
    super.key,
    required this.industry,
    this.emaBreadthConfigStoreForTest,
  });

  @override
  State<IndustryDetailScreen> createState() => _IndustryDetailScreenState();
}

class _IndustryDetailScreenState extends State<IndustryDetailScreen> {
  DateTime? _ratioSortDate;
  Map<String, double> _ratioSortValues = const {};
  bool _isRatioSortLoading = false;
  String? _ratioSortError;
  int _ratioSortRequestToken = 0;
  IndustryEmaBreadthSeries? _emaBreadthSeries;
  IndustryEmaBreadthConfig _emaBreadthConfig =
      IndustryEmaBreadthConfig.defaultConfig;
  bool _isEmaBreadthLoading = false;
  int _emaBreadthRequestToken = 0;

  IndustryEmaBreadthConfigStore get _emaBreadthConfigStore =>
      widget.emaBreadthConfigStoreForTest ?? IndustryEmaBreadthConfigStore();

  @override
  void initState() {
    super.initState();
    _loadEmaBreadthCard();
  }

  @override
  void didUpdateWidget(covariant IndustryDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.industry != widget.industry) {
      _loadEmaBreadthCard();
    }
  }

  Future<void> _loadEmaBreadthCard() async {
    final requestToken = ++_emaBreadthRequestToken;
    setState(() {
      _isEmaBreadthLoading = true;
    });

    IndustryEmaBreadthConfig config = IndustryEmaBreadthConfig.defaultConfig;
    try {
      config = await _emaBreadthConfigStore
          .load(defaults: IndustryEmaBreadthConfig.defaultConfig)
          .timeout(
            const Duration(milliseconds: 300),
            onTimeout: () => IndustryEmaBreadthConfig.defaultConfig,
          );
    } catch (_) {
      config = IndustryEmaBreadthConfig.defaultConfig;
    }

    IndustryEmaBreadthSeries? series;
    try {
      final service = context
          .read<MarketDataProvider>()
          .industryEmaBreadthService;
      if (service != null) {
        series = await service
            .getCachedSeries(widget.industry)
            .timeout(const Duration(milliseconds: 300), onTimeout: () => null);
      }
    } catch (_) {
      series = null;
    }

    if (!mounted || requestToken != _emaBreadthRequestToken) {
      return;
    }
    setState(() {
      _emaBreadthConfig = config;
      _emaBreadthSeries = series;
      _isEmaBreadthLoading = false;
    });
  }

  /// 获取行业趋势数据（历史 + 今日）
  List<DailyRatioPoint> _getTrendData(
    IndustryTrendService trendService,
    DailyRatioPoint? todayPoint,
  ) {
    final historicalData = trendService.getTrend(widget.industry);
    final points = <DailyRatioPoint>[];

    // 添加历史数据（最近30天）
    if (historicalData != null && historicalData.points.isNotEmpty) {
      points.addAll(historicalData.points);
    }

    // 添加今日数据
    if (todayPoint != null) {
      points.add(todayPoint);
    }

    return points;
  }

  Future<void> _onRatioSortDateSelected(
    DateTime? selectedDate,
    List<StockMonitorData> industryStocks,
  ) async {
    if (selectedDate == null) {
      if (!mounted) return;
      setState(() {
        _ratioSortDate = null;
        _ratioSortValues = const {};
        _ratioSortError = null;
        _isRatioSortLoading = false;
      });
      return;
    }

    final normalizedDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final stockCodes = industryStocks.map((item) => item.stock.code).toList();
    if (stockCodes.isEmpty) {
      if (!mounted) return;
      setState(() {
        _ratioSortDate = normalizedDate;
        _ratioSortValues = const {};
        _ratioSortError = null;
        _isRatioSortLoading = false;
      });
      return;
    }

    final requestToken = ++_ratioSortRequestToken;
    if (!mounted) return;
    setState(() {
      _ratioSortDate = normalizedDate;
      _isRatioSortLoading = true;
      _ratioSortError = null;
    });

    try {
      final repository = context.read<DataRepository>();
      final dayStart = DateTime(
        normalizedDate.year,
        normalizedDate.month,
        normalizedDate.day,
      );
      final dayEnd = dayStart
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final klinesByCode = await repository.getKlines(
        stockCodes: stockCodes,
        dateRange: DateRange(dayStart, dayEnd),
        dataType: KLineDataType.oneMinute,
      );

      final ratios = <String, double>{};
      for (final entry in klinesByCode.entries) {
        final ratio = StockService.calculateRatio(entry.value);
        if (ratio != null) {
          ratios[entry.key] = ratio;
        }
      }

      if (!mounted || requestToken != _ratioSortRequestToken) return;
      setState(() {
        _ratioSortValues = ratios;
        _ratioSortError = ratios.isEmpty ? '该日期无可用量比数据' : null;
        _isRatioSortLoading = false;
      });
    } catch (_) {
      if (!mounted || requestToken != _ratioSortRequestToken) return;
      setState(() {
        _ratioSortValues = const {};
        _ratioSortError = '排序日量比加载失败';
        _isRatioSortLoading = false;
      });
    }
  }

  List<DateTime> _buildRatioSortDates(
    List<IndustryBuildupDailyRecord> buildUpHistory,
    DateTime? latestResultDate,
    DateTime? dataDate,
  ) {
    final dates = <DateTime>{};
    for (final record in buildUpHistory) {
      dates.add(record.dateOnly);
    }
    if (latestResultDate != null) {
      dates.add(
        DateTime(
          latestResultDate.year,
          latestResultDate.month,
          latestResultDate.day,
        ),
      );
    }
    if (dataDate != null) {
      dates.add(DateTime(dataDate.year, dataDate.month, dataDate.day));
    }
    final result = dates.toList()..sort((a, b) => b.compareTo(a));
    return result.take(10).toList(growable: false);
  }

  List<StockMonitorData> _buildSortedIndustryStocks(
    List<StockMonitorData> stocks,
  ) {
    final sorted = List<StockMonitorData>.from(stocks);
    if (_ratioSortDate == null) {
      sorted.sort((a, b) => b.ratio.compareTo(a.ratio));
      return sorted;
    }

    sorted.sort((a, b) {
      final aRatio = _ratioSortValues[a.stock.code];
      final bRatio = _ratioSortValues[b.stock.code];
      if (aRatio == null && bRatio == null) {
        return b.ratio.compareTo(a.ratio);
      }
      if (aRatio == null) return 1;
      if (bRatio == null) return -1;

      final bySelectedDate = bRatio.compareTo(aRatio);
      if (bySelectedDate != 0) return bySelectedDate;
      return b.ratio.compareTo(a.ratio);
    });
    return sorted;
  }

  String _formatMonthDay(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();
    final buildUpService = context.watch<IndustryBuildUpService>();

    if (!buildUpService.hasIndustryHistory(widget.industry) &&
        !buildUpService.isIndustryHistoryLoading(widget.industry)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<IndustryBuildUpService>().loadIndustryHistory(
            widget.industry,
          );
        }
      });
    }
    final buildUpHistory = buildUpService.getIndustryHistory(widget.industry);
    final isHistoryLoading = buildUpService.isIndustryHistoryLoading(
      widget.industry,
    );
    final tagConfig = buildUpService.tagConfig;
    final ratioSortDates = _buildRatioSortDates(
      buildUpHistory,
      buildUpService.latestResultDate,
      marketProvider.dataDate,
    );

    // 筛选该行业的股票
    final baseIndustryStocks = marketProvider.allData
        .where((data) => data.industry == widget.industry)
        .toList();
    final industryStocks = _buildSortedIndustryStocks(baseIndustryStocks);

    // 计算今日数据
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);
    final todayPoint = todayTrend[widget.industry];

    // 获取趋势数据
    final trendData = _getTrendData(trendService, todayPoint);

    // 计算今日统计
    final totalStocks = industryStocks.length;
    final ratioAboveCount = industryStocks.where((s) => s.ratio > 1.0).length;
    final ratioAbovePercent = totalStocks > 0
        ? (ratioAboveCount / totalStocks * 100).toStringAsFixed(0)
        : '0';

    // 计算可折叠区域的高度
    const double chartHeight = 150.0;
    const double summaryHeight = 48.0;
    const double buildupCardHeight = 252.0;
    const double emaBreadthCardHeight = 305.0;
    const double titleHeight = 32.0;
    const double expandedHeight =
        kToolbarHeight +
        chartHeight +
        12 +
        summaryHeight +
        10 +
        buildupCardHeight +
        8 +
        emaBreadthCardHeight +
        8 +
        titleHeight;

    return Scaffold(
      body: Stack(
        children: [
          NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: expandedHeight,
                  floating: false,
                  pinned: true,
                  forceElevated: innerBoxIsScrolled,
                  title: Text(widget.industry),
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(top: kToolbarHeight),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 趋势图区域
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IndustryTrendChart(
                                  data: trendData,
                                  height: chartHeight,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // 今日摘要
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Container(
                                  height: summaryHeight,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '今日: $ratioAbovePercent%',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '($ratioAboveCount/$totalStocks 只放量)',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _IndustryBuildupHistoryCard(
                                records: buildUpHistory,
                                isLoading: isHistoryLoading,
                                height: buildupCardHeight,
                                tagConfig: tagConfig,
                              ),
                              const SizedBox(height: 8),
                              // EMA13 广度卡片
                              Container(
                                key: const ValueKey(
                                  'industry_detail_ema_breadth_card',
                                ),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _isEmaBreadthLoading
                                    ? SizedBox(
                                        height: 180,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ),
                                      )
                                    : IndustryEmaBreadthChart(
                                        series: _emaBreadthSeries,
                                        config: _emaBreadthConfig,
                                        height: 164,
                                      ),
                              ),
                              const SizedBox(height: 8),
                              // 成分股列表标题
                              SizedBox(
                                height: titleHeight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '成分股列表',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 固定表头
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    child: StockTable.buildStandaloneHeader(
                      context,
                      showIndustry: false,
                    ),
                  ),
                ),
              ];
            },
            // 成分股表格（不显示表头和行业列）
            body: Column(
              children: [
                _IndustryRatioSortBar(
                  ratioSortDate: _ratioSortDate,
                  ratioSortDates: ratioSortDates,
                  isRatioSortLoading: _isRatioSortLoading,
                  ratioSortError: _ratioSortError,
                  onSelected: (selected) {
                    _onRatioSortDateSelected(selected, baseIndustryStocks);
                  },
                  formatMonthDay: _formatMonthDay,
                ),
                Expanded(
                  child: StockTable(
                    stocks: industryStocks,
                    isLoading: marketProvider.isLoading,
                    ratioOverrides: _ratioSortDate == null
                        ? null
                        : _ratioSortValues,
                    showHeader: false,
                    showIndustry: false,
                    bottomPadding: 68,
                  ),
                ),
              ],
            ),
          ),
          // 底部统计条
          if (industryStocks.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MarketStatsBar(stocks: industryStocks),
            ),
        ],
      ),
    );
  }
}

class _IndustryBuildupHistoryCard extends StatefulWidget {
  final List<IndustryBuildupDailyRecord> records;
  final bool isLoading;
  final double height;
  final IndustryBuildupTagConfig tagConfig;

  const _IndustryBuildupHistoryCard({
    required this.records,
    required this.isLoading,
    required this.height,
    required this.tagConfig,
  });

  @override
  State<_IndustryBuildupHistoryCard> createState() =>
      _IndustryBuildupHistoryCardState();
}

class _IndustryBuildupHistoryCardState
    extends State<_IndustryBuildupHistoryCard> {
  DateTime? _selectedDay;

  IndustryBuildupDailyRecord? _resolveSelectedRecord(
    List<IndustryBuildupDailyRecord> chronological,
  ) {
    if (chronological.isEmpty) return null;
    if (_selectedDay == null) return chronological.last;
    final index = chronological.indexWhere((record) {
      final date = record.dateOnly;
      return date.year == _selectedDay!.year &&
          date.month == _selectedDay!.month &&
          date.day == _selectedDay!.day;
    });
    if (index < 0) return chronological.last;
    return chronological[index];
  }

  int _selectedRecordIndex(
    List<IndustryBuildupDailyRecord> chronological,
    IndustryBuildupDailyRecord selected,
  ) {
    final index = chronological.indexWhere((record) {
      final date = record.dateOnly;
      final selectedDate = selected.dateOnly;
      return date.year == selectedDate.year &&
          date.month == selectedDate.month &&
          date.day == selectedDate.day;
    });
    return index < 0 ? chronological.length - 1 : index;
  }

  @override
  Widget build(BuildContext context) {
    final latest = widget.records.isEmpty ? null : widget.records.first;
    final earliest = widget.records.isEmpty ? null : widget.records.last;
    final recent = widget.records.take(20).toList(growable: false);
    final chronological = recent.reversed.toList(growable: false);
    final selectedRecord = _resolveSelectedRecord(chronological);
    final selectedIndex = selectedRecord == null
        ? 0
        : _selectedRecordIndex(chronological, selectedRecord);
    final bestRank = chronological.isEmpty
        ? null
        : chronological
              .map((record) => record.rank)
              .reduce((a, b) => a < b ? a : b);
    final worstRank = chronological.isEmpty
        ? null
        : chronological
              .map((record) => record.rank)
              .reduce((a, b) => a > b ? a : b);
    final latestStage = latest == null
        ? null
        : resolveIndustryBuildupStage(latest, widget.tagConfig);
    final trendDirection = (latest != null && earliest != null)
        ? (latest.scoreEma >= earliest.scoreEma ? '上升' : '下降')
        : null;
    final rankFrom = earliest?.rank;
    final rankTo = latest?.rank;
    final rankMove = (rankFrom != null && rankTo != null)
        ? rankFrom - rankTo
        : 0;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      height: widget.height,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.multiline_chart,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '建仓雷达历史',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
              const Spacer(),
              Text(
                widget.records.isEmpty
                    ? (widget.isLoading ? '加载中' : '暂无')
                    : '${widget.records.length} 条',
                style: TextStyle(fontSize: 11, color: onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            latest == null
                ? (widget.isLoading ? '正在加载建仓雷达历史...' : '暂无建仓雷达历史数据')
                : '最新 ${_formatDate(latest.dateOnly)}  ${latestStage!.label}  '
                      'Z ${latest.zRel.toStringAsFixed(2)}  Q ${latest.q.toStringAsFixed(2)}  '
                      '广度 ${(latest.breadth * 100).toStringAsFixed(0)}%  '
                      'Raw ${latest.rawScore.toStringAsFixed(2)}  '
                      'EMA ${latest.scoreEma.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 11, color: onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          if (latest != null && earliest != null)
            Text(
              '近20日趋势：scoreEma $trendDirection  '
              'rank ${rankFrom!} → ${rankTo!} (${rankMove >= 0 ? '+' : ''}$rankMove)',
              style: TextStyle(fontSize: 11, color: onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            latest == null ? '雷达排名趋势' : '雷达排名趋势  当前排名 #${latest.rank}',
            style: TextStyle(
              fontSize: 11,
              color: onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (chronological.isNotEmpty)
            SizedBox(
              height: 98,
              child: _IndustryRadarRankTrendChart(
                key: const ValueKey('industry_detail_radar_rank_chart'),
                records: chronological,
                selectedIndex: selectedIndex,
                onSelectedIndex: (index) {
                  if (index < 0 || index >= chronological.length) return;
                  setState(() {
                    _selectedDay = chronological[index].dateOnly;
                  });
                },
              ),
            ),
          if (chronological.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '手指滑动或点击图表可选择日期',
              style: TextStyle(fontSize: 10, color: onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 6),
          Expanded(
            child: selectedRecord == null
                ? const SizedBox.shrink()
                : Container(
                    key: const ValueKey(
                      'industry_detail_radar_selected_detail',
                    ),
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                '当日详情 ${_formatDate(selectedRecord.dateOnly)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '近20日最高#$bestRank / 最低#$worstRank',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Builder(
                                builder: (context) {
                                  final stage = resolveIndustryBuildupStage(
                                    selectedRecord,
                                    widget.tagConfig,
                                  );
                                  final stageColor = _stageColor(stage);
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: stageColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      stage.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: stageColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '排名 #${selectedRecord.rank}  '
                                  '${selectedRecord.rankArrow}${selectedRecord.rankChange.abs()}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Z ${selectedRecord.zRel.toStringAsFixed(2)}  '
                            'Q ${selectedRecord.q.toStringAsFixed(2)}  '
                            '广度 ${(selectedRecord.breadth * 100).toStringAsFixed(0)}%  '
                            'Gate ${selectedRecord.breadthGate.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 11, color: onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Raw ${selectedRecord.rawScore.toStringAsFixed(2)}  '
                            'EMA ${selectedRecord.scoreEma.toStringAsFixed(2)}  '
                            'zPos ${selectedRecord.zPos.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 11, color: onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Color _stageColor(IndustryBuildupStage stage) {
    switch (stage) {
      case IndustryBuildupStage.emotion:
        return const Color(0xFFD84343);
      case IndustryBuildupStage.allocation:
        return const Color(0xFFB8860B);
      case IndustryBuildupStage.early:
        return const Color(0xFF2E8B57);
      case IndustryBuildupStage.noise:
        return const Color(0xFFB26B00);
      case IndustryBuildupStage.neutral:
        return const Color(0xFF70757A);
      case IndustryBuildupStage.observing:
        return const Color(0xFF2A6BB1);
    }
  }
}

class _IndustryRadarRankTrendChart extends StatelessWidget {
  static const double _horizontalPadding = 12.0;
  static const double _topPadding = 10.0;
  static const double _bottomPadding = 20.0;

  final List<IndustryBuildupDailyRecord> records;
  final int selectedIndex;
  final ValueChanged<int> onSelectedIndex;

  const _IndustryRadarRankTrendChart({
    super.key,
    required this.records,
    required this.selectedIndex,
    required this.onSelectedIndex,
  });

  int _resolveIndex(double dx, double width) {
    if (records.length <= 1) return 0;
    final usableWidth = (width - _horizontalPadding * 2).clamp(1.0, width);
    final localX = (dx - _horizontalPadding).clamp(0.0, usableWidth);
    final step = usableWidth / (records.length - 1);
    return (localX / step).round().clamp(0, records.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            onSelectedIndex(_resolveIndex(details.localPosition.dx, width));
          },
          onHorizontalDragUpdate: (details) {
            onSelectedIndex(_resolveIndex(details.localPosition.dx, width));
          },
          child: CustomPaint(
            size: Size(width, 98),
            painter: _IndustryRadarRankTrendPainter(
              records: records,
              selectedIndex: selectedIndex,
              horizontalPadding: _horizontalPadding,
              topPadding: _topPadding,
              bottomPadding: _bottomPadding,
              colorScheme: Theme.of(context).colorScheme,
            ),
          ),
        );
      },
    );
  }
}

class _IndustryRadarRankTrendPainter extends CustomPainter {
  final List<IndustryBuildupDailyRecord> records;
  final int selectedIndex;
  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;
  final ColorScheme colorScheme;

  _IndustryRadarRankTrendPainter({
    required this.records,
    required this.selectedIndex,
    required this.horizontalPadding,
    required this.topPadding,
    required this.bottomPadding,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty) return;

    final chartRect = Rect.fromLTWH(
      horizontalPadding,
      topPadding,
      (size.width - horizontalPadding * 2).clamp(1.0, size.width),
      (size.height - topPadding - bottomPadding).clamp(1.0, size.height),
    );
    final minRank = records
        .map((record) => record.rank.toDouble())
        .reduce((a, b) => a < b ? a : b);
    final maxRank = records
        .map((record) => record.rank.toDouble())
        .reduce((a, b) => a > b ? a : b);
    final rankRange = (maxRank - minRank).abs() < 0.0001
        ? 1.0
        : maxRank - minRank;

    Offset pointAt(int index) {
      final divisor = records.length > 1 ? records.length - 1 : 1;
      final x = chartRect.left + (index / divisor) * chartRect.width;
      final rank = records[index].rank.toDouble();
      final y =
          chartRect.top + ((rank - minRank) / rankRange) * chartRect.height;
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(chartRect.topLeft, chartRect.topRight, gridPaint);
    canvas.drawLine(chartRect.bottomLeft, chartRect.bottomRight, gridPaint);

    final path = Path();
    for (var i = 0; i < records.length; i++) {
      final point = pointAt(i);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final linePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final selected = selectedIndex.clamp(0, records.length - 1);
    for (var i = 0; i < records.length; i++) {
      final point = pointAt(i);
      final isSelected = i == selected;
      final dotPaint = Paint()
        ..color = isSelected
            ? colorScheme.primary
            : colorScheme.primaryContainer
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, isSelected ? 4 : 2.5, dotPaint);
    }

    final selectedPoint = pointAt(selected);
    final markerPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(selectedPoint.dx, chartRect.top),
      Offset(selectedPoint.dx, chartRect.bottom),
      markerPaint,
    );

    final selectedRecord = records[selected];
    final tooltip =
        '${_formatMonthDay(selectedRecord.dateOnly)}  #${selectedRecord.rank}';
    final tooltipPainter = TextPainter(
      text: TextSpan(
        text: tooltip,
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final tooltipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (selectedPoint.dx - tooltipPainter.width / 2 - 6).clamp(
          chartRect.left,
          chartRect.right - tooltipPainter.width - 12,
        ),
        (selectedPoint.dy - tooltipPainter.height - 16).clamp(
          chartRect.top,
          chartRect.bottom - tooltipPainter.height - 4,
        ),
        tooltipPainter.width + 12,
        tooltipPainter.height + 4,
      ),
      const Radius.circular(6),
    );
    final tooltipBgPaint = Paint()
      ..color = colorScheme.primaryContainer.withValues(alpha: 0.95);
    canvas.drawRRect(tooltipRect, tooltipBgPaint);
    tooltipPainter.paint(
      canvas,
      Offset(tooltipRect.left + 6, tooltipRect.top + 2),
    );

    _paintAxisText(
      canvas,
      '#${minRank.toInt()}',
      Offset(chartRect.left, chartRect.top - 10),
    );
    _paintAxisText(
      canvas,
      '#${maxRank.toInt()}',
      Offset(chartRect.left, chartRect.bottom - 10),
    );
    _paintAxisText(
      canvas,
      _formatMonthDay(records.first.dateOnly),
      Offset(chartRect.left, chartRect.bottom + 4),
    );
    final lastLabel = _formatMonthDay(records.last.dateOnly);
    final lastPainter = TextPainter(
      text: TextSpan(
        text: lastLabel,
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    lastPainter.paint(
      canvas,
      Offset(chartRect.right - lastPainter.width, chartRect.bottom + 4),
    );
  }

  void _paintAxisText(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  String _formatMonthDay(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  @override
  bool shouldRepaint(covariant _IndustryRadarRankTrendPainter oldDelegate) {
    return oldDelegate.records != records ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _IndustryRatioSortBar extends StatelessWidget {
  final DateTime? ratioSortDate;
  final List<DateTime> ratioSortDates;
  final bool isRatioSortLoading;
  final String? ratioSortError;
  final void Function(DateTime? selected) onSelected;
  final String Function(DateTime date) formatMonthDay;

  const _IndustryRatioSortBar({
    required this.ratioSortDate,
    required this.ratioSortDates,
    required this.isRatioSortLoading,
    required this.ratioSortError,
    required this.onSelected,
    required this.formatMonthDay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 32,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          PopupMenuButton<DateTime?>(
            key: const ValueKey('industry_detail_ratio_sort_day_menu'),
            tooltip: '量比排序日',
            onSelected: onSelected,
            itemBuilder: (context) {
              return [
                const PopupMenuItem<DateTime?>(value: null, child: Text('最新')),
                ...ratioSortDates.map((date) {
                  return PopupMenuItem<DateTime?>(
                    value: date,
                    child: Text(formatMonthDay(date)),
                  );
                }),
              ];
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                ratioSortDate == null
                    ? '排序: 最新'
                    : '排序: ${formatMonthDay(ratioSortDate!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isRatioSortLoading)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: theme.colorScheme.primary,
              ),
            ),
          if (ratioSortDate != null && !isRatioSortLoading)
            Text(
              '按当日量比排序',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (ratioSortError != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                ratioSortError!,
                style: const TextStyle(fontSize: 10, color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }
}
