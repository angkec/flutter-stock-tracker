import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/services/audit_export_service.dart';

void main() {
  test('export latest run creates zip artifact', () async {
    final temp = await Directory.systemTemp.createTemp('audit-export');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    await File('${temp.path}/audit-2026-02-15.jsonl').writeAsString(
      '{"ts":"2026-02-15T12:00:00.000","run_id":"run-2","operation":"daily_force_refetch","event_type":"runStarted","payload":{}}\n',
    );
    await File('${temp.path}/audit-2026-02-16.jsonl').writeAsString(
      '{"ts":"2026-02-16T12:00:00.000","run_id":"run-1","operation":"daily_force_refetch","event_type":"runStarted","payload":{}}\n'
      '{"ts":"2026-02-16T12:00:01.000","run_id":"run-2","operation":"daily_force_refetch","event_type":"runCompleted","payload":{}}\n',
    );
    await File('${temp.path}/latest_run_index.json').writeAsString(
      '{"run_id":"run-1","operation":"daily_force_refetch","started_at":"2026-02-16T12:00:00.000","completed_at":"2026-02-16T12:00:01.000","verdict":"pass","reason_codes":[],"error_count":0,"missing_count":0,"incomplete_count":0,"unknown_state_count":0,"updated_stock_count":1,"total_records":20,"elapsed_ms":1000,"stage_durations_ms":{}}',
    );

    final service = AuditExportService(
      auditRootProvider: () async => temp,
      outputDirectoryProvider: () async => temp,
      nowProvider: () => DateTime(2026, 2, 16, 12),
    );

    final file = await service.exportLatestRun(runId: 'run-1');
    expect(await file.exists(), isTrue);
    expect(file.path.endsWith('.zip'), isTrue);

    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    expect(
      archive.files.map((entry) => entry.name),
      contains('run-summary.json'),
    );
    expect(
      archive.files.map((entry) => entry.name),
      contains('run-events.jsonl'),
    );

    final summaryEntry = archive.files.firstWhere(
      (entry) => entry.name == 'run-summary.json',
    );
    final summary =
        jsonDecode(utf8.decode(summaryEntry.content as List<int>))
            as Map<String, Object?>;
    expect(summary['run_id'], 'run-1');

    final eventsEntry = archive.files.firstWhere(
      (entry) => entry.name == 'run-events.jsonl',
    );
    final eventsText = utf8.decode(eventsEntry.content as List<int>);
    expect(eventsText, contains('"run_id":"run-1"'));
    expect(eventsText, isNot(contains('"run_id":"run-2"')));
  });

  test('export recent days creates zip artifact', () async {
    final temp = await Directory.systemTemp.createTemp('audit-export');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    await File('${temp.path}/audit-2026-02-16.jsonl').writeAsString('{}\n');

    final service = AuditExportService(
      auditRootProvider: () async => temp,
      outputDirectoryProvider: () async => temp,
      nowProvider: () => DateTime(2026, 2, 16, 12),
    );

    final file = await service.exportRecentDays(days: 7);
    expect(await file.exists(), isTrue);
    expect(file.path.endsWith('.zip'), isTrue);
  });
}
