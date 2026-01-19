import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// A股风格颜色 - 红涨绿跌
const Color upColor = Color(0xFFFF4444); // 红色 - 上涨
const Color downColor = Color(0xFF00AA00); // 绿色 - 下跌

/// 格式化量比
String formatRatio(double ratio) {
  if (ratio >= 999) return '999+';
  return ratio.toStringAsFixed(2);
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
              '涨跌量比',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            numeric: true,
          ),
        ],
        rows: stocks.asMap().entries.map((entry) {
          final index = entry.key;
          final data = entry.value;
          final ratioColor = data.ratio >= 1 ? upColor : downColor;

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
                  formatRatio(data.ratio),
                  style: TextStyle(
                    color: ratioColor,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
