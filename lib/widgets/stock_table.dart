import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stock_rtwatcher/models/industry_trend.dart';
import 'package:stock_rtwatcher/screens/stock_detail_screen.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/theme/theme.dart';
import 'package:stock_rtwatcher/widgets/sparkline_chart.dart';

/// A股风格颜色 - 红涨绿跌
const Color upColor = AppColors.stockUp;
const Color downColor = AppColors.stockDown;

// 列宽定义
const double _codeWidth = 95;
const double _nameWidth = 100;
const double _changeWidth = 75;
const double _ratioWidth = 65;
const double _industryWidth = 135; // 包含行业标签和趋势折线
const double _rowHeight = 44;

/// 格式化量比
String formatRatio(double ratio) {
  if (ratio >= 999) return '999+';
  return ratio.toStringAsFixed(2);
}

/// 格式化涨跌幅
String formatChangePercent(double percent) {
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(2)}%';
}

/// 股票表格组件
class StockTable extends StatelessWidget {
  final List<StockMonitorData> stocks;
  final bool isLoading;
  final Set<String> highlightCodes;
  final void Function(StockMonitorData data)? onLongPress;
  final void Function(String industry)? onIndustryTap;

  /// 行业趋势数据，key 为行业名称
  final Map<String, IndustryTrendData>? industryTrendData;

  /// 今日实时行业趋势数据，key 为行业名称
  final Map<String, DailyRatioPoint>? todayTrendData;

  /// 是否显示行业列
  final bool showIndustry;

  /// 是否显示表头（用于外部固定表头的场景）
  final bool showHeader;

  /// 是否优先显示突破回踩股票
  final bool prioritizeBreakout;

  /// 底部内边距（用于避免被底部元素遮挡）
  final double bottomPadding;

  const StockTable({
    super.key,
    required this.stocks,
    this.isLoading = false,
    this.highlightCodes = const {},
    this.onLongPress,
    this.onIndustryTap,
    this.industryTrendData,
    this.todayTrendData,
    this.showIndustry = true,
    this.showHeader = true,
    this.prioritizeBreakout = true,
    this.bottomPadding = 0,
  });

  void _copyToClipboard(BuildContext context, String code, String name) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $code ($name)'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildHeaderCell(String text, double width, {bool numeric = false}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          textAlign: numeric ? TextAlign.right : TextAlign.left,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, {bool withIndustry = true}) {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildHeaderCell('代码', _codeWidth),
          _buildHeaderCell('名称', _nameWidth),
          _buildHeaderCell('涨跌幅', _changeWidth, numeric: true),
          _buildHeaderCell('量比', _ratioWidth, numeric: true),
          if (withIndustry) _buildHeaderCell('行业', _industryWidth),
        ],
      ),
    );
  }

  /// 构建独立的表头组件（用于外部固定表头）
  static Widget buildStandaloneHeader(BuildContext context, {bool showIndustry = true}) {
    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildStaticHeaderCell(context, '代码', _codeWidth),
          _buildStaticHeaderCell(context, '名称', _nameWidth),
          _buildStaticHeaderCell(context, '涨跌幅', _changeWidth, numeric: true),
          _buildStaticHeaderCell(context, '量比', _ratioWidth, numeric: true),
          if (showIndustry) _buildStaticHeaderCell(context, '行业', _industryWidth),
        ],
      ),
    );
  }

  static Widget _buildStaticHeaderCell(BuildContext context, String text, double width, {bool numeric = false}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          textAlign: numeric ? TextAlign.right : TextAlign.left,
        ),
      ),
    );
  }

  /// 获取表格总宽度
  static double getTotalWidth({bool showIndustry = true}) {
    return _codeWidth + _nameWidth + _changeWidth + _ratioWidth + (showIndustry ? _industryWidth : 0);
  }

  Widget _buildRow(BuildContext context, StockMonitorData data, int index, List<StockMonitorData> displayStocks) {
    final ratioColor = data.ratio >= 1 ? upColor : downColor;
    final changeColor = data.changePercent >= 0 ? upColor : downColor;
    final isHighlighted = highlightCodes.contains(data.stock.code);

    return GestureDetector(
      onLongPress: onLongPress != null ? () => onLongPress!(data) : null,
      onTap: () {
        // 构建股票列表用于左右滑动切换
        final stockList = displayStocks.map((s) => s.stock).toList();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StockDetailScreen(
              stock: data.stock,
              stockList: stockList,
              initialIndex: index,
            ),
          ),
        );
      },
      child: Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: isHighlighted
            ? Colors.amber.withValues(alpha: 0.15)
            : (index.isOdd
                ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.15)
                : null),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 代码列
          GestureDetector(
            onTap: () => _copyToClipboard(context, data.stock.code, data.stock.name),
            child: SizedBox(
              width: _codeWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.stock.code,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.copy,
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 名称列
          SizedBox(
            width: _nameWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: data.stock.name,
                      style: TextStyle(
                        color: data.stock.isST ? Colors.orange : null,
                        fontSize: 13,
                      ),
                    ),
                    // 多日回踩标记（突破+回踩）- 蓝色星号
                    if (data.isBreakout)
                      const TextSpan(
                        text: '★',
                        style: TextStyle(
                          color: Colors.cyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    // 单日回踩标记 - 红色星号
                    if (data.isPullback)
                      const TextSpan(
                        text: '*',
                        style: TextStyle(
                          color: upColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // 涨跌幅列
          SizedBox(
            width: _changeWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                formatChangePercent(data.changePercent),
                style: TextStyle(
                  color: changeColor,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
          // 量比列
          SizedBox(
            width: _ratioWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                formatRatio(data.ratio),
                style: TextStyle(
                  color: ratioColor,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ),
          // 行业列（包含行业标签和趋势折线）
          if (showIndustry)
            SizedBox(
              width: _industryWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: data.industry != null
                    ? GestureDetector(
                        onTap: onIndustryTap != null
                            ? () => onIndustryTap!(data.industry!)
                            : null,
                        child: Row(
                          children: [
                            // 行业标签
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                data.industry!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // 趋势折线图
                            Expanded(
                              child: _buildTrendSparkline(data.industry),
                            ),
                          ],
                        ),
                      )
                    : const Text('-', style: TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
      ),
    );
  }

  /// 构建行业趋势迷你折线图
  Widget _buildTrendSparkline(String? industry) {
    if (industry == null) return const SizedBox.shrink();

    // 获取历史趋势数据
    final trendData = industryTrendData?[industry];
    final todayData = todayTrendData?[industry];

    // 构建数据点列表
    final points = <double>[];

    // 添加历史数据点
    if (trendData != null) {
      for (final point in trendData.points) {
        points.add(point.ratioAbovePercent);
      }
    }

    // 添加今日数据点
    if (todayData != null) {
      points.add(todayData.ratioAbovePercent);
    }

    if (points.isEmpty) return const SizedBox.shrink();

    return SparklineChart(
      data: points,
      width: 50,
      height: 20,
      referenceValue: 50,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (stocks.isEmpty && !isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无数据',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击刷新按钮获取数据',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    final totalWidth = getTotalWidth(showIndustry: showIndustry);

    // 优先显示突破回踩股票（保持组内相对顺序）
    List<StockMonitorData> displayStocks;
    if (prioritizeBreakout && stocks.any((s) => s.isBreakout)) {
      displayStocks = [...stocks]..sort((a, b) {
        if (a.isBreakout == b.isBreakout) return 0;
        return a.isBreakout ? -1 : 1;
      });
    } else {
      displayStocks = stocks;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            if (showHeader) _buildHeader(context, withIndustry: showIndustry),
            Expanded(
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: bottomPadding),
                itemCount: displayStocks.length,
                itemExtent: _rowHeight,
                itemBuilder: (context, index) => _buildRow(context, displayStocks[index], index, displayStocks),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
