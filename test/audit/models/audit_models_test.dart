import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';

void main() {
  test('audit event should roundtrip json', () {
    final event = AuditEvent(
      ts: DateTime(2026, 2, 16, 10, 30),
      runId: 'run-1',
      operation: AuditOperationType.dailyForceRefetch,
      eventType: AuditEventType.fetchResult,
      payload: const {'errors': 0, 'updated_stocks': 12},
    );

    final decoded = AuditEvent.fromJson(event.toJson());
    expect(decoded, event);
  });

  test('run summary should expose fail state', () {
    final summary = AuditRunSummary(
      runId: 'run-2',
      operation: AuditOperationType.weeklyFetchMissing,
      startedAt: DateTime(2026, 2, 16, 9),
      completedAt: DateTime(2026, 2, 16, 9, 0, 2),
      verdict: AuditVerdict.fail,
      reasonCodes: const ['unknown_state'],
      errorCount: 1,
      missingCount: 0,
      incompleteCount: 0,
      unknownStateCount: 1,
      updatedStockCount: 8,
      totalRecords: 320,
      elapsedMs: 2000,
      stageDurationsMs: const {'fetch': 1400, 'write': 600},
    );

    expect(summary.isPass, isFalse);
    expect(summary.primaryReasonCode, 'unknown_state');
  });
}
