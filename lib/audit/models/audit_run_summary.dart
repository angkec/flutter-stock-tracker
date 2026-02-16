import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';

class AuditRunSummary {
  const AuditRunSummary({
    required this.runId,
    required this.operation,
    required this.startedAt,
    required this.completedAt,
    required this.verdict,
    required this.reasonCodes,
    required this.errorCount,
    required this.missingCount,
    required this.incompleteCount,
    required this.unknownStateCount,
    required this.updatedStockCount,
    required this.totalRecords,
    required this.elapsedMs,
    required this.stageDurationsMs,
  });

  final String runId;
  final AuditOperationType operation;
  final DateTime startedAt;
  final DateTime completedAt;
  final AuditVerdict verdict;
  final List<String> reasonCodes;
  final int errorCount;
  final int missingCount;
  final int incompleteCount;
  final int unknownStateCount;
  final int updatedStockCount;
  final int totalRecords;
  final int elapsedMs;
  final Map<String, int> stageDurationsMs;

  bool get isPass => verdict == AuditVerdict.pass;

  String? get primaryReasonCode {
    if (reasonCodes.isEmpty) {
      return null;
    }
    return reasonCodes.first;
  }

  Map<String, Object?> toJson() {
    return {
      'run_id': runId,
      'operation': operation.wireName,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt.toIso8601String(),
      'verdict': verdict.name,
      'reason_codes': reasonCodes,
      'error_count': errorCount,
      'missing_count': missingCount,
      'incomplete_count': incompleteCount,
      'unknown_state_count': unknownStateCount,
      'updated_stock_count': updatedStockCount,
      'total_records': totalRecords,
      'elapsed_ms': elapsedMs,
      'stage_durations_ms': stageDurationsMs,
    };
  }

  static AuditRunSummary fromJson(Map<String, Object?> json) {
    final verdict = AuditVerdict.values.firstWhere(
      (candidate) => candidate.name == json['verdict'],
    );
    return AuditRunSummary(
      runId: json['run_id']! as String,
      operation: AuditOperationTypeX.fromWireName(json['operation']! as String),
      startedAt: DateTime.parse(json['started_at']! as String),
      completedAt: DateTime.parse(json['completed_at']! as String),
      verdict: verdict,
      reasonCodes: List<String>.from((json['reason_codes'] as List?) ?? const []),
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
      missingCount: (json['missing_count'] as num?)?.toInt() ?? 0,
      incompleteCount: (json['incomplete_count'] as num?)?.toInt() ?? 0,
      unknownStateCount: (json['unknown_state_count'] as num?)?.toInt() ?? 0,
      updatedStockCount: (json['updated_stock_count'] as num?)?.toInt() ?? 0,
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      stageDurationsMs: Map<String, int>.from(
        (json['stage_durations_ms'] as Map?) ?? const <String, int>{},
      ),
    );
  }
}
