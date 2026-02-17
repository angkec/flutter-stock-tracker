import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';

class AuditLogStore {
  AuditLogStore({
    Future<Directory> Function()? rootDirectoryProvider,
    DateTime Function()? nowProvider,
    this.retentionDays = 14,
    this.maxBytesPerFile = 2 * 1024 * 1024,
  }) : _rootDirectoryProvider =
           rootDirectoryProvider ?? _defaultRootDirectoryProvider,
       _nowProvider = nowProvider ?? DateTime.now;

  final Future<Directory> Function() _rootDirectoryProvider;
  final DateTime Function() _nowProvider;
  final int retentionDays;
  final int maxBytesPerFile;

  static Future<Directory> _defaultRootDirectoryProvider() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'audit'));
    await root.create(recursive: true);
    return root;
  }

  Future<void> append(AuditEvent event) async {
    await appendAll(<AuditEvent>[event]);
  }

  Future<void> appendAll(List<AuditEvent> events) async {
    if (events.isEmpty) {
      return;
    }

    final file = await _resolveDailyFile();
    final buffer = StringBuffer();
    for (final event in events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    await file.writeAsString(
      buffer.toString(),
      mode: FileMode.append,
      flush: true,
    );
    await _cleanupOldFiles();
  }

  Future<List<AuditEvent>> readEvents({required String runId}) async {
    final files = await listLogFiles();
    final events = <AuditEvent>[];

    for (final file in files) {
      final lines = await file.readAsLines();
      for (final line in lines) {
        final text = line.trim();
        if (text.isEmpty) {
          continue;
        }

        try {
          final json = jsonDecode(text) as Map<String, Object?>;
          final event = AuditEvent.fromJson(json);
          if (event.runId == runId) {
            events.add(event);
          }
        } catch (_) {
          // Ignore malformed lines to keep audit parsing resilient.
        }
      }
    }

    events.sort((a, b) => a.ts.compareTo(b.ts));
    return events;
  }

  Future<List<File>> listLogFiles() async {
    final root = await _rootDirectoryProvider();
    if (!await root.exists()) {
      return const <File>[];
    }

    final files = <File>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<File> _resolveDailyFile() async {
    final root = await _rootDirectoryProvider();
    await root.create(recursive: true);

    final now = _nowProvider();
    final baseName =
        'audit-${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    final primary = File(p.join(root.path, '$baseName.jsonl'));
    if (!await primary.exists()) {
      await primary.create(recursive: true);
      return primary;
    }

    final size = await primary.length();
    if (size < maxBytesPerFile) {
      return primary;
    }

    final rolledName = '$baseName-${now.millisecondsSinceEpoch}.jsonl';
    final rolled = File(p.join(root.path, rolledName));
    await rolled.create(recursive: true);
    return rolled;
  }

  Future<void> _cleanupOldFiles() async {
    if (retentionDays <= 0) {
      return;
    }

    final root = await _rootDirectoryProvider();
    if (!await root.exists()) {
      return;
    }

    final cutoff = _nowProvider().subtract(Duration(days: retentionDays));

    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) {
        continue;
      }

      try {
        final modified = (await entity.stat()).modified;
        if (modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // Audit cleanup is best effort and must not block main flow.
      }
    }
  }
}
