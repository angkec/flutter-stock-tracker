import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// A股风格颜色 - 红涨绿跌
const Color upColor = Color(0xFFFF4444);
const Color downColor = Color(0xFF00AA00);

// 列宽定义
const double _codeWidth = 80;
const double _nameWidth = 100;
const double _changeWidth = 75;
const double _ratioWidth = 65;
const double _industryWidth = 80;
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
  final void Function(StockMonitorData data)? onTap;
  final void Function(String industry)? onIndustryTap;

  const StockTable({
    super.key,
    required this.stocks,
    this.isLoading = false,
    this.highlightCodes = const {},
    this.onLongPress,
    this.onTap,
    this.onIndustryTap,
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

  Widget _buildHeader(BuildContext context) {
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
          _buildHeaderCell('行业', _industryWidth),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, StockMonitorData data, int index) {
    final ratioColor = data.ratio >= 1 ? upColor : downColor;
    final changeColor = data.changePercent >= 0 ? upColor : downColor;
    final isHighlighted = highlightCodes.contains(data.stock.code);

    return GestureDetector(
      onLongPress: onLongPress != null ? () => onLongPress!(data) : null,
      onTap: onTap != null ? () => onTap!(data) : null,
      child: Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: isHighlighted
            ? Colors.amber.withValues(alpha: 0.15)
            : (index.isOdd
                ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                : null),
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
                    Text(
                      data.stock.code,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
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
              child: Text(
                data.stock.name,
                style: TextStyle(
                  color: data.stock.isST ? Colors.orange : null,
                  fontSize: 13,
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
          // 行业列
          SizedBox(
            width: _industryWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: data.industry != null
                  ? GestureDetector(
                      onTap: onIndustryTap != null
                          ? () => onIndustryTap!(data.industry!)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          data.industry!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
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

    const totalWidth = _codeWidth + _nameWidth + _changeWidth + _ratioWidth + _industryWidth;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView.builder(
                itemCount: stocks.length,
                itemExtent: _rowHeight,
                itemBuilder: (context, index) => _buildRow(context, stocks[index], index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
