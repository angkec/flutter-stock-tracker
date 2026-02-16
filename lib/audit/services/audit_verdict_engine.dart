import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';

class AuditVerdictEngine {
  AuditRunSummary evaluate({
    required String runId,
    required AuditOperationType operation,
    required DateTime startedAt,
    required DateTime completedAt,
    required List<AuditEvent> events,
    int? elapsedMs,
  }) {
    final reasonCodes = <String>{};
    final stageDurationsMs = <String, int>{};

    var errorCount = 0;
    var missingCount = 0;
    var incompleteCount = 0;
    var unknownStateCount = 0;
    var updatedStockCount = 0;
    var totalRecords = 0;

    for (final event in events) {
      switch (event.eventType) {
        case AuditEventType.errorRaised:
          errorCount += 1;
          reasonCodes.add('runtime_error');
          break;
        case AuditEventType.fetchResult:
          updatedStockCount += _asInt(event.payload['updated_stock_count']);
          totalRecords += _asInt(event.payload['total_records']);
          if (_asInt(event.payload['failure_count']) > 0) {
            reasonCodes.add('fetch_failure');
          }
          break;
        case AuditEventType.verificationResult:
          final missing = _asInt(event.payload['missing_count']);
          final incomplete = _asInt(event.payload['incomplete_count']);
          missingCount += missing;
          incompleteCount += incomplete;
          if (missing > 0) {
            reasonCodes.add('missing_after_fetch');
          }
          if (incomplete > 0) {
            reasonCodes.add('incomplete_after_fetch');
          }
          break;
        case AuditEventType.completenessState:
          final state = event.payload['state']?.toString();
          if (state == 'unknown') {
            unknownStateCount += 1;
            reasonCodes.add('unknown_state');
          }
          break;
        case AuditEventType.indicatorRecomputeResult:
          final dataChanged = event.payload['data_changed'] == true;
          final scopeCount = _asInt(event.payload['scope_count']);
          if (dataChanged && scopeCount <= 0) {
            reasonCodes.add('recompute_scope_empty');
          }
          break;
        case AuditEventType.stageCompleted:
          final stageName = event.payload['stage']?.toString();
          if (stageName != null && stageName.isNotEmpty) {
            stageDurationsMs[stageName] =
                _asInt(event.payload['duration_ms']);
          }
          break;
        case AuditEventType.runStarted:
        case AuditEventType.stageStarted:
        case AuditEventType.stageProgress:
        case AuditEventType.runCompleted:
          break;
      }
    }

    final durationMs =
        elapsedMs ?? completedAt.difference(startedAt).inMilliseconds;

    return AuditRunSummary(
      runId: runId,
      operation: operation,
      startedAt: startedAt,
      completedAt: completedAt,
      verdict: reasonCodes.isEmpty ? AuditVerdict.pass : AuditVerdict.fail,
      reasonCodes: reasonCodes.toList()..sort(),
      errorCount: errorCount,
      missingCount: missingCount,
      incompleteCount: incompleteCount,
      unknownStateCount: unknownStateCount,
      updatedStockCount: updatedStockCount,
      totalRecords: totalRecords,
      elapsedMs: durationMs,
      stageDurationsMs: stageDurationsMs,
    );
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}
