import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/services/audit_verdict_engine.dart';

void main() {
  final engine = AuditVerdictEngine();

  test('fails on unknown completeness state', () {
    final verdict = engine.evaluate(
      runId: 'run-unknown',
      operation: AuditOperationType.dailyForceRefetch,
      startedAt: DateTime(2026, 2, 16, 9),
      completedAt: DateTime(2026, 2, 16, 9, 0, 3),
      events: [
        AuditEvent(
          ts: DateTime(2026, 2, 16, 9, 0, 1),
          runId: 'run-unknown',
          operation: AuditOperationType.dailyForceRefetch,
          eventType: AuditEventType.completenessState,
          payload: const {'state': 'unknown'},
        ),
      ],
    );

    expect(verdict.verdict.name, 'fail');
    expect(verdict.reasonCodes, contains('unknown_state'));
  });

  test('fails on unknown_retry completeness state', () {
    final verdict = engine.evaluate(
      runId: 'run-unknown-retry',
      operation: AuditOperationType.dailyForceRefetch,
      startedAt: DateTime(2026, 2, 16, 9),
      completedAt: DateTime(2026, 2, 16, 9, 0, 3),
      events: [
        AuditEvent(
          ts: DateTime(2026, 2, 16, 9, 0, 1),
          runId: 'run-unknown-retry',
          operation: AuditOperationType.dailyForceRefetch,
          eventType: AuditEventType.completenessState,
          payload: const {'state': 'unknown_retry'},
        ),
      ],
    );

    expect(verdict.verdict.name, 'fail');
    expect(verdict.reasonCodes, contains('unknown_state'));
  });

  test('does not fail on high latency alone', () {
    final verdict = engine.evaluate(
      runId: 'run-latency',
      operation: AuditOperationType.weeklyFetchMissing,
      startedAt: DateTime(2026, 2, 16, 9),
      completedAt: DateTime(2026, 2, 16, 9, 0, 20),
      events: const [],
      elapsedMs: 20000,
    );

    expect(verdict.verdict.name, 'pass');
  });
}
