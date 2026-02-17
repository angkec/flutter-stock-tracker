import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/services/audit_operation_runner.dart';

class InMemoryAuditSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];
  AuditRunSummary? latest;
  int appendCalls = 0;
  int appendAllCalls = 0;

  @override
  Future<void> append(AuditEvent event) async {
    appendCalls++;
    events.add(event);
  }

  @override
  Future<void> appendAll(List<AuditEvent> input) async {
    appendAllCalls++;
    events.addAll(input);
  }

  @override
  Future<void> saveLatest(AuditRunSummary summary) async {
    latest = summary;
  }
}

class FailingAppendAuditSink implements AuditSink {
  AuditRunSummary? latest;

  @override
  Future<void> append(AuditEvent event) async {
    throw StateError('append failed');
  }

  @override
  Future<void> appendAll(List<AuditEvent> input) async {
    throw StateError('append failed');
  }

  @override
  Future<void> saveLatest(AuditRunSummary summary) async {
    latest = summary;
  }
}

class FailingSaveAuditSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> append(AuditEvent event) async {
    events.add(event);
  }

  @override
  Future<void> appendAll(List<AuditEvent> input) async {
    events.addAll(input);
  }

  @override
  Future<void> saveLatest(AuditRunSummary summary) async {
    throw StateError('save latest failed');
  }
}

void main() {
  test('runner should create run and emit completed summary', () async {
    final memory = InMemoryAuditSink();
    final runner = AuditOperationRunner(
      sink: memory,
      nowProvider: () => DateTime(2026, 2, 16, 11),
    );

    final summary = await runner.run(
      operation: AuditOperationType.dailyForceRefetch,
      body: (ctx) async {
        ctx.stageStarted('fetch');
        ctx.stageProgress('fetch', current: 1, total: 2);
        ctx.stageCompleted('fetch', durationMs: 1200);
      },
    );

    expect(summary.runId, isNotEmpty);
    expect(
      memory.events.any((e) => e.eventType == AuditEventType.runStarted),
      isTrue,
    );
    expect(
      memory.events.any((e) => e.eventType == AuditEventType.runCompleted),
      isTrue,
    );
    expect(memory.latest?.runId, summary.runId);
  });

  test('runner should persist events through batched appendAll', () async {
    final memory = InMemoryAuditSink();
    final runner = AuditOperationRunner(
      sink: memory,
      nowProvider: () => DateTime(2026, 2, 16, 11),
    );

    await runner.run(
      operation: AuditOperationType.dailyForceRefetch,
      body: (ctx) async {
        for (var i = 1; i <= 5; i++) {
          ctx.stageProgress('fetch', current: i, total: 5);
        }
      },
    );

    expect(memory.appendAllCalls, 1);
    expect(memory.appendCalls, 0);
    expect(memory.events.length, greaterThanOrEqualTo(7));
  });

  test('runner should mark error event and rethrow', () async {
    final memory = InMemoryAuditSink();
    final runner = AuditOperationRunner(
      sink: memory,
      nowProvider: () => DateTime(2026, 2, 16, 11),
    );

    await expectLater(
      () => runner.run(
        operation: AuditOperationType.historicalFetchMissing,
        body: (_) async {
          throw StateError('boom');
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(
      memory.events.any((e) => e.eventType == AuditEventType.errorRaised),
      isTrue,
    );
    expect(memory.latest?.verdict.name, 'fail');
  });

  test('runner should not fail operation when append persist fails', () async {
    final sink = FailingAppendAuditSink();
    final runner = AuditOperationRunner(
      sink: sink,
      nowProvider: () => DateTime(2026, 2, 16, 11),
    );

    final summary = await runner.run(
      operation: AuditOperationType.dailyForceRefetch,
      body: (ctx) async {
        ctx.stageStarted('fetch');
        ctx.stageCompleted('fetch');
      },
    );

    expect(summary.reasonCodes, contains('audit_write_warning'));
    expect(summary.verdict.name, 'fail');
    expect(sink.latest?.reasonCodes, contains('audit_write_warning'));
  });

  test(
    'runner should not fail operation when latest index save fails',
    () async {
      final sink = FailingSaveAuditSink();
      final runner = AuditOperationRunner(
        sink: sink,
        nowProvider: () => DateTime(2026, 2, 16, 11),
      );

      final summary = await runner.run(
        operation: AuditOperationType.dailyForceRefetch,
        body: (ctx) async {
          ctx.stageStarted('fetch');
          ctx.stageCompleted('fetch');
        },
      );

      expect(summary.reasonCodes, contains('audit_write_warning'));
      expect(summary.verdict.name, 'fail');
      expect(sink.events, isNotEmpty);
    },
  );
}
