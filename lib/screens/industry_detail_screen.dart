import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
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

  const IndustryDetailScreen({
    super.key,
    required this.industry,
  });

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

    // 筛选该行业的股票
    final industryStocks = marketProvider.allData
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
    const double titleHeight = 32.0;
    const double expandedHeight = chartHeight + 12 + summaryHeight + 8 + titleHeight;

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
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Container(
                                  height: summaryHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '今日: $ratioAbovePercent%',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '($ratioAboveCount/$totalStocks 只放量)',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // 成分股列表标题
                              SizedBox(
                                height: titleHeight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '成分股列表',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    child: StockTable.buildStandaloneHeader(context, showIndustry: false),
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
