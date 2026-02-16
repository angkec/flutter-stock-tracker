import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';
import 'package:stock_rtwatcher/audit/storage/latest_audit_index_store.dart';

void main() {
  test('save and read latest summary', () async {
    final tempDir = await Directory.systemTemp.createTemp('audit-index-store');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = LatestAuditIndexStore(
      rootDirectoryProvider: () async => tempDir,
    );

    final summary = AuditRunSummary(
      runId: 'run-latest',
      operation: AuditOperationType.dailyForceRefetch,
      startedAt: DateTime(2026, 2, 16, 10),
      completedAt: DateTime(2026, 2, 16, 10, 0, 5),
      verdict: AuditVerdict.pass,
      reasonCodes: const [],
      errorCount: 0,
      missingCount: 0,
      incompleteCount: 0,
      unknownStateCount: 0,
      updatedStockCount: 10,
      totalRecords: 100,
      elapsedMs: 5000,
      stageDurationsMs: const {'fetch': 3300},
    );

    await store.save(summary);

    final loaded = await store.readLatest();
    expect(loaded, isNotNull);
    expect(loaded!.runId, 'run-latest');
    expect(loaded.verdict, AuditVerdict.pass);
  });

  test('read latest should tolerate malformed index json', () async {
    final tempDir = await Directory.systemTemp.createTemp('audit-index-store');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = LatestAuditIndexStore(
      rootDirectoryProvider: () async => tempDir,
    );
    final indexFile = await store.indexFile();
    await indexFile.writeAsString('{broken-json');

    final loaded = await store.readLatest();
    expect(loaded, isNull);
  });
}
