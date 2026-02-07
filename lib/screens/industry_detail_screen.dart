import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/industry_buildup_stage.dart';
import 'package:stock_rtwatcher/models/industry_buildup_tag_config.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
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
class IndustryDetailScreen extends StatelessWidget {
  final String industry;

  const IndustryDetailScreen({super.key, required this.industry});

  /// 获取行业趋势数据（历史 + 今日）
  List<DailyRatioPoint> _getTrendData(
    IndustryTrendService trendService,
    DailyRatioPoint? todayPoint,
  ) {
    final historicalData = trendService.getTrend(industry);
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

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final trendService = context.watch<IndustryTrendService>();
    final buildUpService = context.watch<IndustryBuildUpService>();

    if (!buildUpService.hasIndustryHistory(industry) &&
        !buildUpService.isIndustryHistoryLoading(industry)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.read<IndustryBuildUpService>().loadIndustryHistory(industry);
        }
      });
    }
    final buildUpHistory = buildUpService.getIndustryHistory(industry);
    final isHistoryLoading = buildUpService.isIndustryHistoryLoading(industry);
    final tagConfig = buildUpService.tagConfig;

    // 筛选该行业的股票
    final industryStocks =
        marketProvider.allData
            .where((data) => data.industry == industry)
            .toList()
          ..sort((a, b) => b.ratio.compareTo(a.ratio));

    // 计算今日数据
    final todayTrend = trendService.calculateTodayTrend(marketProvider.allData);
    final todayPoint = todayTrend[industry];

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
    const double buildupCardHeight = 184.0;
    const double titleHeight = 32.0;
    const double expandedHeight =
        chartHeight +
        12 +
        summaryHeight +
        10 +
        buildupCardHeight +
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
                  title: Text(industry),
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
            body: StockTable(
              stocks: industryStocks,
              isLoading: marketProvider.isLoading,
              showHeader: false,
              showIndustry: false,
              bottomPadding: 68,
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

class _IndustryBuildupHistoryCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final latest = records.isEmpty ? null : records.first;
    final latestStage = latest == null
        ? null
        : resolveIndustryBuildupStage(latest, tagConfig);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      height: height,
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
                Icons.radar,
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
                records.isEmpty
                    ? (isLoading ? '加载中' : '暂无')
                    : '${records.length} 条',
                style: TextStyle(fontSize: 11, color: onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            latest == null
                ? (isLoading ? '正在加载建仓雷达历史...' : '暂无建仓雷达历史数据')
                : '最新 ${_formatDate(latest.dateOnly)}  ${latestStage!.label}  Z ${latest.zRel.toStringAsFixed(2)}  广度 ${(latest.breadth * 100).toStringAsFixed(0)}%  Q ${latest.q.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 11, color: onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: records.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final stage = resolveIndustryBuildupStage(
                        record,
                        tagConfig,
                      );
                      final stageColor = _stageColor(stage);
                      return Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              _formatDate(record.dateOnly),
                              style: TextStyle(
                                fontSize: 11,
                                color: onSurface,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          Container(
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
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Z ${record.zRel.toStringAsFixed(2)}  广度 ${(record.breadth * 100).toStringAsFixed(0)}%  Q ${record.q.toStringAsFixed(2)}  排名#${record.rank}',
                              style: TextStyle(fontSize: 11, color: onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                    separatorBuilder: (_, _) => Divider(
                      height: 8,
                      thickness: 0.5,
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.4),
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
