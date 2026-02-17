import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/storage/audit_log_store.dart';

void main() {
  test('appends and reads events by run id', () async {
    final tempDir = await Directory.systemTemp.createTemp('audit-log-store');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = AuditLogStore(
      rootDirectoryProvider: () async => tempDir,
      nowProvider: () => DateTime(2026, 2, 16, 10),
      retentionDays: 14,
      maxBytesPerFile: 1 << 20,
    );

    final event = AuditEvent(
      ts: DateTime(2026, 2, 16, 10, 1),
      runId: 'run-1',
      operation: AuditOperationType.dailyForceRefetch,
      eventType: AuditEventType.runStarted,
      payload: const {'stock_count': 20},
    );
    await store.append(event);

    final loaded = await store.readEvents(runId: 'run-1');
    expect(loaded, hasLength(1));
    expect(loaded.first.eventType, AuditEventType.runStarted);
  });

  test('ignores malformed tail lines', () async {
    final tempDir = await Directory.systemTemp.createTemp('audit-log-store');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = AuditLogStore(
      rootDirectoryProvider: () async => tempDir,
      nowProvider: () => DateTime(2026, 2, 16, 10),
    );

    final file = File('${tempDir.path}/audit-2026-02-16.jsonl');
    await file.writeAsString(
      '{"ts":"2026-02-16T10:01:00.000","run_id":"run-2","operation":"daily_force_refetch","event_type":"runStarted","payload":{}}\n{broken-json',
    );

    final loaded = await store.readEvents(runId: 'run-2');
    expect(loaded, hasLength(1));
  });

  test('appendAll writes a batch in one call and remains readable', () async {
    final tempDir = await Directory.systemTemp.createTemp('audit-log-store');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = AuditLogStore(
      rootDirectoryProvider: () async => tempDir,
      nowProvider: () => DateTime(2026, 2, 16, 10),
      retentionDays: 14,
      maxBytesPerFile: 1 << 20,
    );

    final events = <AuditEvent>[
      AuditEvent(
        ts: DateTime(2026, 2, 16, 10, 1),
        runId: 'run-batch',
        operation: AuditOperationType.dailyForceRefetch,
        eventType: AuditEventType.runStarted,
        payload: const {'stock_count': 20},
      ),
      AuditEvent(
        ts: DateTime(2026, 2, 16, 10, 2),
        runId: 'run-batch',
        operation: AuditOperationType.dailyForceRefetch,
        eventType: AuditEventType.stageCompleted,
        payload: const {'stage': 'fetch'},
      ),
    ];

    await store.appendAll(events);

    final loaded = await store.readEvents(runId: 'run-batch');
    expect(loaded, hasLength(2));
    expect(loaded.first.eventType, AuditEventType.runStarted);
    expect(loaded.last.eventType, AuditEventType.stageCompleted);
  });
}
