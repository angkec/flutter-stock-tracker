import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AuditExportService {
  AuditExportService({
    Future<Directory> Function()? auditRootProvider,
    Future<Directory> Function()? outputDirectoryProvider,
    DateTime Function()? nowProvider,
  }) : _auditRootProvider = auditRootProvider ?? _defaultAuditRootProvider,
       _outputDirectoryProvider =
           outputDirectoryProvider ?? _defaultAuditRootProvider,
       _nowProvider = nowProvider ?? DateTime.now;

  final Future<Directory> Function() _auditRootProvider;
  final Future<Directory> Function() _outputDirectoryProvider;
  final DateTime Function() _nowProvider;

  static Future<Directory> _defaultAuditRootProvider() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'audit'));
    await root.create(recursive: true);
    return root;
  }

  Future<File> exportLatestRun({required String runId}) async {
    final root = await _auditRootProvider();
    final output = await _outputDirectoryProvider();
    await output.create(recursive: true);

    final now = _nowProvider();
    final file = File(
      p.join(
        output.path,
        'audit-latest-${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.zip',
      ),
    );

    final encoder = ZipFileEncoder();
    encoder.create(file.path);

    final tempDir = await Directory.systemTemp.createTemp(
      'audit-export-latest-$runId',
    );
    try {
      final summaryFile = File(p.join(tempDir.path, 'run-summary.json'));
      final eventsFile = File(p.join(tempDir.path, 'run-events.jsonl'));

      final summary = await _buildRunSummary(root: root, runId: runId);
      final events = await _collectRunEvents(root: root, runId: runId);
      await summaryFile.writeAsString(
        jsonEncode(summary),
        mode: FileMode.writeOnly,
        flush: true,
      );
      await eventsFile.writeAsString(
        events.isEmpty ? '' : '${events.join('\n')}\n',
        mode: FileMode.writeOnly,
        flush: true,
      );

      encoder.addFile(summaryFile, p.basename(summaryFile.path));
      encoder.addFile(eventsFile, p.basename(eventsFile.path));
    } finally {
      encoder.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
    return file;
  }

  Future<File> exportRecentDays({int days = 7}) async {
    final root = await _auditRootProvider();
    final output = await _outputDirectoryProvider();
    await output.create(recursive: true);

    final now = _nowProvider();
    final cutoff = now.subtract(Duration(days: days));
    final file = File(
      p.join(
        output.path,
        'audit-last-${days}d-${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.zip',
      ),
    );

    final encoder = ZipFileEncoder();
    encoder.create(file.path);

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (entity.path == file.path || entity.path.endsWith('.zip')) {
        continue;
      }

      final name = p.basename(entity.path);
      if (name == 'latest_run_index.json') {
        encoder.addFile(entity, name);
        continue;
      }
      if (!name.endsWith('.jsonl')) {
        continue;
      }

      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        continue;
      }
      encoder.addFile(entity, name);
    }

    encoder.close();
    return file;
  }

  Future<Map<String, Object?>> _buildRunSummary({
    required Directory root,
    required String runId,
  }) async {
    final latestIndex = File(p.join(root.path, 'latest_run_index.json'));
    if (await latestIndex.exists()) {
      try {
        final decoded =
            jsonDecode(await latestIndex.readAsString())
                as Map<String, Object?>;
        if (decoded['run_id'] == runId) {
          return decoded;
        }
      } catch (_) {
        // Fallback to minimal summary when index is malformed.
      }
    }

    return <String, Object?>{
      'run_id': runId,
      'note': 'latest index mismatch or unavailable',
      'exported_at': _nowProvider().toIso8601String(),
    };
  }

  Future<List<String>> _collectRunEvents({
    required Directory root,
    required String runId,
  }) async {
    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && p.basename(entity.path).endsWith('.jsonl')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));

    final lines = <String>[];
    for (final file in files) {
      final sourceLines = await file.readAsLines();
      for (final line in sourceLines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        try {
          final decoded = jsonDecode(trimmed) as Map<String, Object?>;
          if (decoded['run_id'] == runId) {
            lines.add(trimmed);
          }
        } catch (_) {
          // Ignore malformed lines to keep export best effort.
        }
      }
    }
    return lines;
  }
}
