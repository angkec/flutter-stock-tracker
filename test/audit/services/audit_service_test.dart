import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';
import 'package:stock_rtwatcher/audit/services/audit_export_service.dart';
import 'package:stock_rtwatcher/audit/services/audit_operation_runner.dart';
import 'package:stock_rtwatcher/audit/services/audit_service.dart';

class _FakeAuditSink implements AuditSink {
  AuditRunSummary? latest;

  @override
  Future<void> append(AuditEvent event) async {}

  @override
  Future<void> appendAll(List<AuditEvent> events) async {}

  @override
  Future<void> saveLatest(AuditRunSummary summary) async {
    latest = summary;
  }
}

void main() {
  test('audit service should expose latest summary stream', () async {
    final sink = _FakeAuditSink();
    final summary = AuditRunSummary(
      runId: 'run-1',
      operation: AuditOperationType.dailyForceRefetch,
      startedAt: DateTime(2026, 2, 16, 12),
      completedAt: DateTime(2026, 2, 16, 12, 0, 1),
      verdict: AuditVerdict.pass,
      reasonCodes: const [],
      errorCount: 0,
      missingCount: 0,
      incompleteCount: 0,
      unknownStateCount: 0,
      updatedStockCount: 0,
      totalRecords: 0,
      elapsedMs: 1000,
      stageDurationsMs: const {},
    );

    final service = AuditService.forTest(
      runner: AuditOperationRunner(
        sink: sink,
        nowProvider: () => DateTime(2026, 2, 16, 12),
      ),
      readLatest: () async => summary,
      exporter: AuditExportService(
        auditRootProvider: () async => throw UnimplementedError(),
        outputDirectoryProvider: () async => throw UnimplementedError(),
      ),
    );

    final nextSummary = service.latestSummaryStream
        .where((value) => value != null)
        .cast<AuditRunSummary>()
        .first;

    await service.refreshLatest();
    final emitted = await nextSummary;

    expect(emitted.runId, 'run-1');
    expect(service.latest?.runId, 'run-1');
  });

  test('audit service should tolerate latest summary read errors', () async {
    final sink = _FakeAuditSink();
    final summary = AuditRunSummary(
      runId: 'run-1',
      operation: AuditOperationType.dailyForceRefetch,
      startedAt: DateTime(2026, 2, 16, 12),
      completedAt: DateTime(2026, 2, 16, 12, 0, 1),
      verdict: AuditVerdict.pass,
      reasonCodes: const [],
      errorCount: 0,
      missingCount: 0,
      incompleteCount: 0,
      unknownStateCount: 0,
      updatedStockCount: 0,
      totalRecords: 0,
      elapsedMs: 1000,
      stageDurationsMs: const {},
    );

    var reads = 0;
    final service = AuditService.forTest(
      runner: AuditOperationRunner(
        sink: sink,
        nowProvider: () => DateTime(2026, 2, 16, 12),
      ),
      readLatest: () async {
        reads += 1;
        if (reads == 1) {
          return summary;
        }
        throw StateError('index decode failed');
      },
      exporter: AuditExportService(
        auditRootProvider: () async => throw UnimplementedError(),
        outputDirectoryProvider: () async => throw UnimplementedError(),
      ),
    );

    await service.refreshLatest();
    expect(service.latest?.runId, 'run-1');

    await service.refreshLatest();
    expect(service.latest?.runId, 'run-1');
  });
}
