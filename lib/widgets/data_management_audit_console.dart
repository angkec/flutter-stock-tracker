import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/theme/app_colors.dart';
import 'package:stock_rtwatcher/theme/app_text_styles.dart';

class DataManagementAuditConsole extends StatelessWidget {
  const DataManagementAuditConsole({
    super.key,
    required this.title,
    required this.verdictLabel,
    required this.operationLabel,
    required this.completedAtLabel,
    required this.reasonCodes,
    required this.metricsLabel,
    this.onViewDetails,
    this.onExportLatest,
    this.onExportRecent,
  });

  final String title;
  final String verdictLabel;
  final String operationLabel;
  final String completedAtLabel;
  final List<String> reasonCodes;
  final String metricsLabel;
  final VoidCallback? onViewDetails;
  final VoidCallback? onExportLatest;
  final VoidCallback? onExportRecent;

  @override
  Widget build(BuildContext context) {
    final upperVerdict = verdictLabel.toUpperCase();
    final isPass = upperVerdict == 'PASS';
    final railColor = isPass ? AppColors.auditPass : AppColors.auditFail;
    final railTextColor = isPass
        ? AppColors.auditPassOnColor
        : AppColors.auditFailOnColor;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.auditFrame),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 78,
              decoration: BoxDecoration(
                color: railColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.auditRailCaption.copyWith(
                      color: railTextColor.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    upperVerdict,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.auditRailVerdict.copyWith(
                      color: railTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      operationLabel,
                      style: AppTextStyles.auditOperation.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      completedAtLabel,
                      style: AppTextStyles.auditTimestamp.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: reasonCodes.isEmpty
                          ? [
                              _AuditChip(
                                label: isPass
                                    ? 'reliability_ok'
                                    : 'no_reason_code',
                                color: isPass
                                    ? AppColors.auditPass.withValues(
                                        alpha: 0.14,
                                      )
                                    : AppColors.auditFail.withValues(
                                        alpha: 0.14,
                                      ),
                                borderColor: isPass
                                    ? AppColors.auditPass.withValues(alpha: 0.4)
                                    : AppColors.auditFail.withValues(
                                        alpha: 0.4,
                                      ),
                                textColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                              ),
                            ]
                          : reasonCodes
                                .take(4)
                                .map(
                                  (code) => _AuditChip(
                                    label: code,
                                    color: AppColors.auditReasonBackground,
                                    borderColor: AppColors.auditFrame,
                                    textColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                )
                                .toList(growable: false),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      metricsLabel,
                      style: AppTextStyles.auditMetrics.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 120,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.auditFrame)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onViewDetails,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('详情'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onExportLatest,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('导出最新'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: onExportRecent,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('导出7天'),
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
}

class _AuditChip extends StatelessWidget {
  const _AuditChip({
    required this.label,
    required this.color,
    required this.borderColor,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.auditChip.copyWith(color: textColor),
      ),
    );
  }
}
