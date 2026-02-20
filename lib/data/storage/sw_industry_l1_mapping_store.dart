import 'dart:convert';
import 'dart:io';

import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

class SwIndustryL1MappingStore {
  SwIndustryL1MappingStore({
    KLineFileStorage? storage,
    AtomicFileWriter? atomicWriter,
    this.subDirectoryName = 'sw_industry_mapping',
    this.fileName = 'sw_industry_l1_mapping_v1.json',
  }) : _storage = storage ?? KLineFileStorage(),
       _atomicWriter = atomicWriter ?? const AtomicFileWriter();

  final KLineFileStorage _storage;
  final AtomicFileWriter _atomicWriter;
  final String subDirectoryName;
  final String fileName;

  bool _initialized = false;
  String? _directoryPath;

  Future<void> saveAll(Map<String, String> mapping) async {
    final file = await _resolveFile();
    final payload = jsonEncode(mapping);
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(payload),
    );
  }

  Future<Map<String, String>> loadAll() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return const <String, String>{};
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return const <String, String>{};
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      return const <String, String>{};
    }

    return decoded.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
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
