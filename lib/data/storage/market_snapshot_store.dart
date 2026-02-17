import 'dart:io';

import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

/// Persists minute snapshot payload as a JSON file to avoid large
/// SharedPreferences writes.
class MarketSnapshotStore {
  MarketSnapshotStore({
    KLineFileStorage? storage,
    this.subDirectoryName = 'market_snapshot',
    this.fileName = 'minute_market_snapshot_v1.json',
  }) : _storage = storage ?? KLineFileStorage();

  final KLineFileStorage _storage;
  final String subDirectoryName;
  final String fileName;

  bool _initialized = false;
  String? _directoryPath;

  Future<void> saveJson(String payload) async {
    if (payload.trim().isEmpty) {
      await clear();
      return;
    }

    final file = await _resolveFile();
    final tempFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tempFile.writeAsString(payload, flush: true);

    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  Future<String?> loadJson() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return null;
    }
    return content;
  }

  Future<void> clear() async {
    final file = await _resolveFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _resolveFile() async {
    await _initialize();
    return File('$_directoryPath/$fileName');
  }

  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }

    String basePath;
    try {
      await _storage.initialize();
      basePath = await _storage.getBaseDirectoryPath();
    } catch (_) {
      basePath = '${Directory.systemTemp.path}/stock_rtwatcher_market_data';
      final fallbackDir = Directory(basePath);
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
    }

    final directory = Directory('$basePath/$subDirectoryName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _directoryPath = directory.path;
    _initialized = true;
  }
}
