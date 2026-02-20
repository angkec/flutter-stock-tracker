import 'dart:convert';
import 'dart:io';

import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';

class IndustryEmaBreadthConfigStore {
  IndustryEmaBreadthConfigStore({
    KLineFileStorage? storage,
    AtomicFileWriter? atomicWriter,
    this.subDirectoryName = 'industry_ema_breadth_config',
    this.fileName = 'industry_ema_breadth_config_v1.json',
  }) : _storage = storage ?? KLineFileStorage(),
       _atomicWriter = atomicWriter ?? const AtomicFileWriter();

  final KLineFileStorage _storage;
  final AtomicFileWriter _atomicWriter;
  final String subDirectoryName;
  final String fileName;

  bool _initialized = false;
  String? _directoryPath;

  Future<void> initialize() async {
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

  Future<void> save(IndustryEmaBreadthConfig config) async {
    final file = await _resolveFile();
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(jsonEncode(config.toJson())),
    );
  }

  Future<IndustryEmaBreadthConfig> load({
    IndustryEmaBreadthConfig? defaults,
  }) async {
    final fallback = defaults ?? IndustryEmaBreadthConfig.defaultConfig;
    final file = await _resolveFile();
    if (!await file.exists()) {
      return fallback;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return fallback;
      }

      final json = jsonDecode(content) as Map<String, dynamic>;
      return IndustryEmaBreadthConfig.fromJson(json, defaults: fallback);
    } catch (_) {
      return fallback;
    }
  }

  Future<String> configFilePath() async {
    final file = await _resolveFile();
    return file.path;
  }

  Future<File> _resolveFile() async {
    await initialize();
    return File('$_directoryPath/$fileName');
  }
}
