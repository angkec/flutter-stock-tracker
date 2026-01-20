import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class IndustryScreen extends StatelessWidget {
  final void Function(String industry)? onIndustryTap;

  const IndustryScreen({super.key, this.onIndustryTap});

  /// 计算行业统计
  List<IndustryStats> _calculateStats(List<StockMonitorData> data) {
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

    final statsList = result.values.toList()
      ..sort((a, b) => b.ratioSortValue.compareTo(a.ratioSortValue));

    return statsList;
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final stats = _calculateStats(marketProvider.allData);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            Expanded(
              child: stats.isEmpty && !marketProvider.isLoading
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
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '量比',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
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
                              itemCount: stats.length,
                              itemExtent: 48,
                              itemBuilder: (context, index) =>
                                  _buildRow(context, stats[index], index),
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

  Widget _buildRow(BuildContext context, IndustryStats stats, int index) {
    const upColor = Color(0xFFFF4444);
    const downColor = Color(0xFF00AA00);

    return GestureDetector(
      onTap: onIndustryTap != null
          ? () => onIndustryTap!(stats.name)
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
          ],
        ),
      ),
    );
  }
}
