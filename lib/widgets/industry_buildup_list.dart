import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/screens/industry_detail_screen.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/widgets/sparkline_chart.dart';

class IndustryBuildupList extends StatelessWidget {
  final bool fullHeight;

  const IndustryBuildupList({super.key, this.fullHeight = false});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<IndustryBuildUpService>();
    final board = service.latestBoard;

    if (board.isEmpty && !service.isCalculating) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.radar_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('暂无建仓雷达数据', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '点击“重算”生成行业建仓榜单',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _RecalculateButton(service: service),
          ],
        ),
      );
    }

    final rows = fullHeight ? board : board.take(20).toList();

    return Column(
      children: [
        _StatusBar(service: service),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  '行业',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  'Z值',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '广度',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  'Q',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '20日趋势',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 42,
            itemBuilder: (context, index) {
              final item = rows[index];
              final record = item.record;
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          IndustryDetailScreen(industry: record.industry),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: index.isOdd
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.25)
                        : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: Text(
                          record.industry,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: Text(
                          record.zRel.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 12,
                            color: record.zRel >= 0
                                ? const Color(0xFFFF4444)
                                : const Color(0xFF00AA00),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${(record.breadth * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          record.q.toStringAsFixed(2),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: item.zRelTrend.length >= 2
                              ? SparklineChart(
                                  data: item.zRelTrend,
                                  width: 72,
                                  height: 20,
                                )
                              : Text(
                                  '-',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  final IndustryBuildUpService service;

  const _StatusBar({required this.service});

  @override
  Widget build(BuildContext context) {
    final latestDate = service.latestResultDate;
    final dateText = latestDate == null
        ? '数据日期 --'
        : '数据日期 ${latestDate.month.toString().padLeft(2, '0')}-${latestDate.day.toString().padLeft(2, '0')}';

    String? statusText;
    Color? statusColor;
    if (service.errorMessage != null) {
      statusText = service.errorMessage;
      statusColor = Colors.orange;
    } else if (service.isStale) {
      statusText = '结果可能过期';
      statusColor = Colors.orange;
    } else if (service.isCalculating) {
      statusText =
          '${service.stageLabel} ${service.progressCurrent}/${service.progressTotal}';
      statusColor = Theme.of(context).colorScheme.primary;
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dateText, style: const TextStyle(fontSize: 11)),
                if (statusText != null)
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 10, color: statusColor),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          _RecalculateButton(service: service),
        ],
      ),
    );
  }
}

class _RecalculateButton extends StatelessWidget {
  final IndustryBuildUpService service;

  const _RecalculateButton({required this.service});

  @override
  Widget build(BuildContext context) {
    final isRunning = service.isCalculating;
    final text = isRunning
        ? '${service.stageLabel} ${service.progressCurrent}/${service.progressTotal}'
        : '重算';

    return FilledButton(
      onPressed: isRunning ? null : () => service.recalculate(force: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRunning) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
          ],
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
