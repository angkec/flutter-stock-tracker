import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';

class LatestAuditIndexStore {
  LatestAuditIndexStore({Future<Directory> Function()? rootDirectoryProvider})
    : _rootDirectoryProvider =
          rootDirectoryProvider ?? _defaultRootDirectoryProvider;

  final Future<Directory> Function() _rootDirectoryProvider;

  static Future<Directory> _defaultRootDirectoryProvider() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'audit'));
    await root.create(recursive: true);
    return root;
  }

  Future<void> save(AuditRunSummary summary) async {
    final file = await _indexFile();
    await file.writeAsString(jsonEncode(summary.toJson()), flush: true);
  }

  Future<AuditRunSummary?> readLatest() async {
    final file = await _indexFile();
    if (!await file.exists()) {
      return null;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return AuditRunSummary.fromJson(decoded);
    } catch (_) {
      // Tolerate malformed index file and fall back to no latest summary.
      return null;
    }
  }

  Future<File> indexFile() async {
    return _indexFile();
  }

  Future<File> _indexFile() async {
    final root = await _rootDirectoryProvider();
    await root.create(recursive: true);
    return File(p.join(root.path, 'latest_run_index.json'));
  }
}
