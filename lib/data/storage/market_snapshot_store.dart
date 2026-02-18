import 'dart:convert';
import 'dart:io';

import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

/// Persists minute snapshot payload as a JSON file to avoid large
/// SharedPreferences writes.
class MarketSnapshotStore {
  MarketSnapshotStore({
    KLineFileStorage? storage,
    AtomicFileWriter? atomicWriter,
    this.subDirectoryName = 'market_snapshot',
    this.fileName = 'minute_market_snapshot_v1.json',
  }) : _storage = storage ?? KLineFileStorage(),
       _atomicWriter = atomicWriter ?? const AtomicFileWriter();

  final KLineFileStorage _storage;
  final AtomicFileWriter _atomicWriter;
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
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(payload),
    );
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
