import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/adaptive_weekly_config.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/industry_buildup_stage.dart';
import 'package:stock_rtwatcher/models/industry_buildup_tag_config.dart';
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
    final tagConfig = service.tagConfig;
    final adaptiveConfig = service.latestWeeklyAdaptiveConfig;

    if (board.isEmpty) {
      return _EmptyState(service: service);
    }

    final rows = fullHeight ? board : board.take(20).toList();

    return Column(
      children: [
        _StatusBar(service: service),
        if (adaptiveConfig != null && adaptiveConfig.candidates.isNotEmpty)
          _WeeklyCandidatesBoard(config: adaptiveConfig),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 94,
                child: Text(
                  '行业/状态',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  'Z值',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '广度',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(
                width: 38,
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
            itemExtent: 56,
            itemBuilder: (context, index) {
              final item = rows[index];
              final record = item.record;
              final interpretation = _interpretRecord(record, tagConfig);
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
                        width: 94,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.industry,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            _StateTagChip(interpretation: interpretation),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          record.zRel.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 12,
                            color: interpretation.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(record.breadth * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 38,
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

class _WeeklyCandidatesBoard extends StatelessWidget {
  final AdaptiveWeeklyConfig config;

  const _WeeklyCandidatesBoard({required this.config});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = config.candidates.take(config.k).toList(growable: false);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本周候选榜 ${config.week}（${_adaptiveStatusLabel(config.status)}）',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _adaptiveStatusColor(context, config.status),
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < candidates.length; i++)
            Text(
              '${i + 1}. ${candidates[i].industry}  ${_formatMonthDay(candidates[i].day)}  '
              'score ${candidates[i].score.toStringAsFixed(2)}  '
              'Z ${candidates[i].z.toStringAsFixed(2)}  '
              'Q ${candidates[i].q.toStringAsFixed(2)}  '
              '广度 ${(candidates[i].breadth * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

String _formatMonthDay(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return '${normalized.month.toString().padLeft(2, '0')}-'
      '${normalized.day.toString().padLeft(2, '0')}';
}

class _EmptyState extends StatelessWidget {
  final IndustryBuildUpService service;

  const _EmptyState({required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = service.isCalculating
        ? '${service.stageLabel} ${service.progressCurrent}/${service.progressTotal}'
        : service.errorMessage;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.radar_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('暂无建仓雷达数据', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('点击“重算”生成行业建仓榜单', style: theme.textTheme.bodySmall),
          if (statusText != null) ...[
            const SizedBox(height: 8),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                color: service.isCalculating
                    ? theme.colorScheme.primary
                    : Colors.orange,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConfigButton(service: service),
              const SizedBox(width: 6),
              _HelpButton(service: service),
              const SizedBox(width: 8),
              _RecalculateButton(service: service),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final IndustryBuildUpService service;

  const _StatusBar({required this.service});

  @override
  Widget build(BuildContext context) {
    final latestDate = service.latestResultDate;
    final adaptiveConfig = service.latestWeeklyAdaptiveConfig;
    final dateText = latestDate == null
        ? '结果基于数据日期 --'
        : '结果基于数据日期 ${latestDate.month.toString().padLeft(2, '0')}-${latestDate.day.toString().padLeft(2, '0')}';
    final canSwitchDate = latestDate != null && !service.isCalculating;

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

    String? adaptiveText;
    Color? adaptiveColor;
    if (adaptiveConfig != null) {
      final thresholds = adaptiveConfig.thresholds;
      adaptiveText =
          '本周候选 ${_adaptiveStatusLabel(adaptiveConfig.status)}  '
          'Top-${adaptiveConfig.k}  '
          'Z≥${thresholds.z.toStringAsFixed(2)}  '
          'Q≥${thresholds.q.toStringAsFixed(2)}  '
          '广度≥${thresholds.breadth.toStringAsFixed(2)}';
      adaptiveColor = _adaptiveStatusColor(context, adaptiveConfig.status);
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _DateSwitchButton(
                      tooltip: '上一日',
                      icon: Icons.chevron_left,
                      enabled: canSwitchDate && service.hasPreviousDate,
                      onPressed: () async {
                        await service.showPreviousDateBoard();
                      },
                    ),
                    Expanded(
                      child: Text(
                        dateText,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _DateSwitchButton(
                      tooltip: '下一日',
                      icon: Icons.chevron_right,
                      enabled: canSwitchDate && service.hasNextDate,
                      onPressed: () async {
                        await service.showNextDateBoard();
                      },
                    ),
                  ],
                ),
                if (statusText != null)
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 10, color: statusColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (adaptiveText != null)
                  Text(
                    adaptiveText,
                    style: TextStyle(fontSize: 10, color: adaptiveColor),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          _ConfigButton(service: service),
          const SizedBox(width: 6),
          _HelpButton(service: service),
          const SizedBox(width: 6),
          _RecalculateButton(service: service),
        ],
      ),
    );
  }
}

String _adaptiveStatusLabel(AdaptiveWeeklyStatus status) {
  switch (status) {
    case AdaptiveWeeklyStatus.strong:
      return '强';
    case AdaptiveWeeklyStatus.weak:
      return '观察';
    case AdaptiveWeeklyStatus.none:
      return '无高亮';
  }
}

Color _adaptiveStatusColor(BuildContext context, AdaptiveWeeklyStatus status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case AdaptiveWeeklyStatus.strong:
      return scheme.primary;
    case AdaptiveWeeklyStatus.weak:
      return Colors.orange;
    case AdaptiveWeeklyStatus.none:
      return scheme.onSurfaceVariant;
  }
}

class _DateSwitchButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final Future<void> Function() onPressed;

  const _DateSwitchButton({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    );
  }
}

class _ConfigButton extends StatelessWidget {
  final IndustryBuildUpService service;

  const _ConfigButton({required this.service});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _showTagConfigDialog(context, service),
      icon: const Icon(Icons.tune, size: 18),
      tooltip: '指标配置',
      visualDensity: VisualDensity.compact,
    );
  }
}

class _HelpButton extends StatelessWidget {
  final IndustryBuildUpService service;

  const _HelpButton({required this.service});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _showInterpretationHelp(context, service.tagConfig),
      icon: const Icon(Icons.help_outline, size: 18),
      tooltip: '解读帮助',
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StateTagChip extends StatelessWidget {
  final _BuildupInterpretation interpretation;

  const _StateTagChip({required this.interpretation});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: interpretation.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        interpretation.label,
        style: TextStyle(
          fontSize: 10,
          color: interpretation.color,
          fontWeight: FontWeight.w600,
        ),
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

class _BuildupInterpretation {
  final String label;
  final Color color;

  const _BuildupInterpretation({required this.label, required this.color});
}

_BuildupInterpretation _interpretRecord(
  IndustryBuildupDailyRecord record,
  IndustryBuildupTagConfig config,
) {
  final stage = resolveIndustryBuildupStage(record, config);
  return _BuildupInterpretation(label: stage.label, color: _stageColor(stage));
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

String _f2(double v) => v.toStringAsFixed(2);

void _showTagConfigDialog(
  BuildContext context,
  IndustryBuildUpService service,
) {
  showDialog<void>(
    context: context,
    builder: (_) => _TagConfigDialog(service: service),
  );
}

class _TagConfigDialog extends StatefulWidget {
  final IndustryBuildUpService service;

  const _TagConfigDialog({required this.service});

  @override
  State<_TagConfigDialog> createState() => _TagConfigDialogState();
}

class _TagConfigDialogState extends State<_TagConfigDialog> {
  late final TextEditingController _emotionMinZ;
  late final TextEditingController _emotionMinBreadth;
  late final TextEditingController _allocationMinZ;
  late final TextEditingController _allocationMinBreadth;
  late final TextEditingController _allocationMaxBreadth;
  late final TextEditingController _allocationMinQ;
  late final TextEditingController _earlyMinZ;
  late final TextEditingController _earlyMaxZ;
  late final TextEditingController _earlyMinBreadth;
  late final TextEditingController _earlyMaxBreadth;
  late final TextEditingController _earlyMinQ;
  late final TextEditingController _noiseMinZ;
  late final TextEditingController _noiseMaxBreadth;
  late final TextEditingController _noiseMaxQ;
  late final TextEditingController _neutralMinZ;
  late final TextEditingController _neutralMaxZ;

  @override
  void initState() {
    super.initState();
    _loadFrom(widget.service.tagConfig);
  }

  @override
  void dispose() {
    _emotionMinZ.dispose();
    _emotionMinBreadth.dispose();
    _allocationMinZ.dispose();
    _allocationMinBreadth.dispose();
    _allocationMaxBreadth.dispose();
    _allocationMinQ.dispose();
    _earlyMinZ.dispose();
    _earlyMaxZ.dispose();
    _earlyMinBreadth.dispose();
    _earlyMaxBreadth.dispose();
    _earlyMinQ.dispose();
    _noiseMinZ.dispose();
    _noiseMaxBreadth.dispose();
    _noiseMaxQ.dispose();
    _neutralMinZ.dispose();
    _neutralMaxZ.dispose();
    super.dispose();
  }

  void _loadFrom(IndustryBuildupTagConfig c) {
    _emotionMinZ = TextEditingController(text: _f2(c.emotionMinZ));
    _emotionMinBreadth = TextEditingController(text: _f2(c.emotionMinBreadth));
    _allocationMinZ = TextEditingController(text: _f2(c.allocationMinZ));
    _allocationMinBreadth = TextEditingController(
      text: _f2(c.allocationMinBreadth),
    );
    _allocationMaxBreadth = TextEditingController(
      text: _f2(c.allocationMaxBreadth),
    );
    _allocationMinQ = TextEditingController(text: _f2(c.allocationMinQ));
    _earlyMinZ = TextEditingController(text: _f2(c.earlyMinZ));
    _earlyMaxZ = TextEditingController(text: _f2(c.earlyMaxZ));
    _earlyMinBreadth = TextEditingController(text: _f2(c.earlyMinBreadth));
    _earlyMaxBreadth = TextEditingController(text: _f2(c.earlyMaxBreadth));
    _earlyMinQ = TextEditingController(text: _f2(c.earlyMinQ));
    _noiseMinZ = TextEditingController(text: _f2(c.noiseMinZ));
    _noiseMaxBreadth = TextEditingController(text: _f2(c.noiseMaxBreadth));
    _noiseMaxQ = TextEditingController(text: _f2(c.noiseMaxQ));
    _neutralMinZ = TextEditingController(text: _f2(c.neutralMinZ));
    _neutralMaxZ = TextEditingController(text: _f2(c.neutralMaxZ));
  }

  double _parse(TextEditingController c, double fallback) {
    return double.tryParse(c.text) ?? fallback;
  }

  void _reset() {
    const d = IndustryBuildupTagConfig.defaults;
    _emotionMinZ.text = _f2(d.emotionMinZ);
    _emotionMinBreadth.text = _f2(d.emotionMinBreadth);
    _allocationMinZ.text = _f2(d.allocationMinZ);
    _allocationMinBreadth.text = _f2(d.allocationMinBreadth);
    _allocationMaxBreadth.text = _f2(d.allocationMaxBreadth);
    _allocationMinQ.text = _f2(d.allocationMinQ);
    _earlyMinZ.text = _f2(d.earlyMinZ);
    _earlyMaxZ.text = _f2(d.earlyMaxZ);
    _earlyMinBreadth.text = _f2(d.earlyMinBreadth);
    _earlyMaxBreadth.text = _f2(d.earlyMaxBreadth);
    _earlyMinQ.text = _f2(d.earlyMinQ);
    _noiseMinZ.text = _f2(d.noiseMinZ);
    _noiseMaxBreadth.text = _f2(d.noiseMaxBreadth);
    _noiseMaxQ.text = _f2(d.noiseMaxQ);
    _neutralMinZ.text = _f2(d.neutralMinZ);
    _neutralMaxZ.text = _f2(d.neutralMaxZ);
  }

  void _save() {
    final current = widget.service.tagConfig;
    widget.service.updateTagConfig(
      current.copyWith(
        emotionMinZ: _parse(_emotionMinZ, current.emotionMinZ),
        emotionMinBreadth: _parse(
          _emotionMinBreadth,
          current.emotionMinBreadth,
        ),
        allocationMinZ: _parse(_allocationMinZ, current.allocationMinZ),
        allocationMinBreadth: _parse(
          _allocationMinBreadth,
          current.allocationMinBreadth,
        ),
        allocationMaxBreadth: _parse(
          _allocationMaxBreadth,
          current.allocationMaxBreadth,
        ),
        allocationMinQ: _parse(_allocationMinQ, current.allocationMinQ),
        earlyMinZ: _parse(_earlyMinZ, current.earlyMinZ),
        earlyMaxZ: _parse(_earlyMaxZ, current.earlyMaxZ),
        earlyMinBreadth: _parse(_earlyMinBreadth, current.earlyMinBreadth),
        earlyMaxBreadth: _parse(_earlyMaxBreadth, current.earlyMaxBreadth),
        earlyMinQ: _parse(_earlyMinQ, current.earlyMinQ),
        noiseMinZ: _parse(_noiseMinZ, current.noiseMinZ),
        noiseMaxBreadth: _parse(_noiseMaxBreadth, current.noiseMaxBreadth),
        noiseMaxQ: _parse(_noiseMaxQ, current.noiseMaxQ),
        neutralMinZ: _parse(_neutralMinZ, current.neutralMinZ),
        neutralMaxZ: _parse(_neutralMaxZ, current.neutralMaxZ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('建仓雷达阈值配置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildField(_allocationMinZ, '行业配置期最小Z'),
              _buildField(_allocationMinBreadth, '行业配置期最小广度'),
              _buildField(_allocationMaxBreadth, '行业配置期最大广度'),
              _buildField(_allocationMinQ, '行业配置期最小Q'),
              const Divider(height: 20),
              _buildField(_earlyMinZ, '早期建仓最小Z'),
              _buildField(_earlyMaxZ, '早期建仓最大Z'),
              _buildField(_earlyMinBreadth, '早期建仓最小广度'),
              _buildField(_earlyMaxBreadth, '早期建仓最大广度'),
              _buildField(_earlyMinQ, '早期建仓最小Q'),
              const Divider(height: 20),
              _buildField(_emotionMinZ, '情绪驱动最小Z'),
              _buildField(_emotionMinBreadth, '情绪驱动最小广度'),
              _buildField(_noiseMinZ, '噪音信号最小Z'),
              _buildField(_noiseMaxBreadth, '噪音信号最大广度'),
              _buildField(_noiseMaxQ, '噪音信号最大Q'),
              const Divider(height: 20),
              _buildField(_neutralMinZ, '无异常最小Z'),
              _buildField(_neutralMaxZ, '无异常最大Z'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('恢复默认')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _buildField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

void _showInterpretationHelp(
  BuildContext context,
  IndustryBuildupTagConfig config,
) {
  showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('建仓雷达解读指南'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '指标定义',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text('Z 值：行业资金买入是否异常（高不等于马上上涨）。'),
                const Text('广度：是否是行业整体行为，而非少数个股。'),
                const Text('Q 值：当前信号的可信度，越高越可靠。'),
                const SizedBox(height: 12),
                const Text(
                  '状态标签（颜色+Tag）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '情绪驱动：Z > ${_f2(config.emotionMinZ)} 且 广度 > ${_f2(config.emotionMinBreadth)}；全行业一致性很强，注意波动风险。',
                ),
                Text(
                  '行业配置期：Z > ${_f2(config.allocationMinZ)} 且 广度 ${_f2(config.allocationMinBreadth)}~${_f2(config.allocationMaxBreadth)} 且 Q > ${_f2(config.allocationMinQ)}；行业级资金配置特征。',
                ),
                Text(
                  '早期建仓：Z ${_f2(config.earlyMinZ)}~${_f2(config.earlyMaxZ)} 且 广度 ${_f2(config.earlyMinBreadth)}~${_f2(config.earlyMaxBreadth)} 且 Q > ${_f2(config.earlyMinQ)}；集中但有持续性。',
                ),
                Text(
                  '噪音信号：Z >= ${_f2(config.noiseMinZ)} 且 广度 < ${_f2(config.noiseMaxBreadth)} 且 Q < ${_f2(config.noiseMaxQ)}；可能被少数个股劫持。',
                ),
                Text(
                  '无异常：Z 在 ${_f2(config.neutralMinZ)}~${_f2(config.neutralMaxZ)}；与历史相比无显著异常买入行为。',
                ),
                const Text('观察中：其余不满足以上条件；有一定变化但未达到明确标签阈值。'),
                const SizedBox(height: 6),
                const Text('判定顺序：情绪驱动 → 行业配置期 → 早期建仓 → 噪音信号 → 无异常 → 观察中。'),
                const SizedBox(height: 12),
                const Text(
                  '使用建议',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text('优先看“行业配置期 / 早期建仓”，再看 20 日趋势是否延续。'),
                const Text('若是“情绪驱动”，重点控制追高风险。'),
                const Text('若是“噪音信号”，建议等待更高 Q 或更高广度再确认。'),
                const SizedBox(height: 10),
                const Text(
                  '免责声明：本指标用于行为刻画，不构成投资建议。',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
