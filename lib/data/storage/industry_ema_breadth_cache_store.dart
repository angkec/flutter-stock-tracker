import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';

class IndustryEmaBreadthCacheStore {
  IndustryEmaBreadthCacheStore({
    KLineFileStorage? storage,
    AtomicFileWriter? atomicWriter,
    this.defaultMaxConcurrentWrites = 6,
  }) : _storage = storage ?? KLineFileStorage(),
       _atomicWriter = atomicWriter ?? const AtomicFileWriter();

  final KLineFileStorage _storage;
  final AtomicFileWriter _atomicWriter;
  final int defaultMaxConcurrentWrites;
  bool _initialized = false;
  String? _cacheDirectoryPath;

  static const String _cacheSubDir = 'industry_ema_breadth_cache';

  Future<void> initialize() async {
    if (_initialized) return;
    await _storage.initialize();
    final basePath = await _storage.getBaseDirectoryPath();
    final dir = Directory('$basePath/$_cacheSubDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDirectoryPath = dir.path;
    _initialized = true;
  }

  Future<void> saveSeries(IndustryEmaBreadthSeries series) async {
    await saveAll([series]);
  }

  Future<void> saveAll(
    List<IndustryEmaBreadthSeries> items, {
    int? maxConcurrentWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    if (items.isEmpty) return;
    await initialize();

    final total = items.length;
    final workerCount = min(
      max(1, maxConcurrentWrites ?? defaultMaxConcurrentWrites),
      total,
    );
    var nextIndex = 0;
    var completed = 0;

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        if (index >= total) {
          return;
        }
        nextIndex++;

        await _saveSingle(items[index]);

        completed++;
        onProgress?.call(completed, total);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => runWorker()),
    );
  }

  Future<IndustryEmaBreadthSeries?> loadSeries(String industry) async {
    await initialize();
    final file = File(await _cacheFilePath(industry));
    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return IndustryEmaBreadthSeries.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSingle(IndustryEmaBreadthSeries series) async {
    final file = File(await _cacheFilePath(series.industry));
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(jsonEncode(series.toJson())),
    );
  }

  Future<String> cacheFilePath(String industry) async {
    return _cacheFilePath(industry);
  }

  Future<String> _cacheFilePath(String industry) async {
    await initialize();
    final encoded = Uri.encodeComponent(industry);
    return '$_cacheDirectoryPath/${encoded}_industry_ema_breadth_cache.json';
  }
}
