import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// A股风格颜色 - 红涨绿跌
const Color upColor = Color(0xFFFF4444); // 红色 - 上涨
const Color downColor = Color(0xFF00AA00); // 绿色 - 下跌
const Color flatColor = Colors.grey; // 灰色 - 平盘

/// 根据数值获取颜色
Color getChangeColor(double value) {
  if (value > 0) return upColor;
  if (value < 0) return downColor;
  return flatColor;
}

/// 格式化涨跌幅
String formatChangePercent(double percent) {
  final sign = percent > 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(2)}%';
}

/// 格式化量比
String formatRatio(double ratio) {
  if (ratio >= 999) return '999+';
  return ratio.toStringAsFixed(2);
}

/// 格式化价格
String formatPrice(double price) {
  return price.toStringAsFixed(2);
}

/// 股票表格组件
class StockTable extends StatelessWidget {
  final List<StockMonitorData> stocks;
  final bool isLoading;

  const StockTable({
    super.key,
    required this.stocks,
    this.isLoading = false,
  });

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
              '正在连接服务器...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 24,
          horizontalMargin: 16,
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          columns: const [
            DataColumn(
              label: Text(
                '代码',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                '名称',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                '现价',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Text(
                '涨跌%',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Text(
                '日涨跌比',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Text(
                '30m涨跌比',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
          ],
          rows: stocks.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final changePercent = data.quote.changePercent;
            final changeColor = getChangeColor(changePercent);

            return DataRow(
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (index.isOdd) {
                  return Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.3);
                }
                return null;
              }),
              cells: [
                DataCell(
                  Text(
                    data.stock.code,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                DataCell(
                  Text(
                    data.stock.name,
                    style: TextStyle(
                      color: data.stock.isST ? Colors.orange : null,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    formatPrice(data.quote.price),
                    style: TextStyle(
                      color: changeColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: changeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      formatChangePercent(changePercent),
                      style: TextStyle(
                        color: changeColor,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                DataCell(
                  _buildRatioCell(data.ratioDay, false),
                ),
                DataCell(
                  _buildRatioCell(data.ratio30m, data.is30mPartial),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 构建量比单元格
  Widget _buildRatioCell(double ratio, bool isPartial) {
    final color = ratio >= 1 ? upColor : downColor;
    final text = formatRatio(ratio);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w500,
            fontFamily: 'monospace',
          ),
        ),
        if (isPartial) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: '30分钟K线尚未收盘',
            child: Icon(
              Icons.schedule,
              size: 14,
              color: Colors.orange.withValues(alpha: 0.8),
            ),
          ),
        ],
      ],
    );
  }
}
