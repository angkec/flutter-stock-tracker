import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/ema_config.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';

class EmaCacheSeries {
  final String stockCode;
  final KLineDataType dataType;
  final EmaConfig config;
  final String sourceSignature;
  final List<EmaPoint> points;
  final DateTime updatedAt;

  EmaCacheSeries({
    required this.stockCode,
    required this.dataType,
    required this.config,
    required this.sourceSignature,
    required this.points,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'stockCode': stockCode,
    'dataType': dataType.name,
    'config': config.toJson(),
    'sourceSignature': sourceSignature,
    'updatedAt': updatedAt.toIso8601String(),
    'points': points.map((point) => point.toJson()).toList(growable: false),
  };

  factory EmaCacheSeries.fromJson(Map<String, dynamic> json) {
    final points = ((json['points'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(EmaPoint.fromJson)
        .toList(growable: false);

    return EmaCacheSeries(
      stockCode: json['stockCode'] as String,
      dataType: KLineDataType.fromName(json['dataType'] as String),
      config: EmaConfig.fromJson(
        (json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{}),
      ),
      sourceSignature: json['sourceSignature'] as String? ?? '',
      points: points,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class EmaCacheStore {
  EmaCacheStore({
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

  static const String _cacheSubDir = 'ema_cache';

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

  Future<void> saveSeries({
    required String stockCode,
    required KLineDataType dataType,
    required EmaConfig config,
    required String sourceSignature,
    required List<EmaPoint> points,
  }) async {
    await saveAll([
      EmaCacheSeries(
        stockCode: stockCode,
        dataType: dataType,
        config: config,
        sourceSignature: sourceSignature,
        points: points,
      ),
    ]);
  }

  Future<void> saveAll(
    List<EmaCacheSeries> items, {
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
      List.generate(workerCount, (_) => runWorker(), growable: false),
    );
  }

  Future<EmaCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    await initialize();
    final file = File(await _cacheFilePath(stockCode, dataType));
    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return EmaCacheSeries.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, EmaCacheSeries>> loadAllSeries(
    Iterable<String> stockCodes, {
    required KLineDataType dataType,
    int maxConcurrentLoads = 8,
  }) async {
    final codes = stockCodes.toSet().toList(growable: false);
    if (codes.isEmpty) {
      return <String, EmaCacheSeries>{};
    }

    final workerCount = min(max(1, maxConcurrentLoads), codes.length);
    final results = <String, EmaCacheSeries>{};
    var nextIndex = 0;

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        if (index >= codes.length) {
          return;
        }
        nextIndex++;

        final stockCode = codes[index];
        final series = await loadSeries(
          stockCode: stockCode,
          dataType: dataType,
        );
        if (series != null) {
          results[stockCode] = series;
        }
      }
    }

    await Future.wait(
      List.generate(workerCount, (_) => runWorker(), growable: false),
    );
    return results;
  }

  Future<void> clearForStocks(List<String> stockCodes) async {
    if (stockCodes.isEmpty) return;
    await initialize();

    for (final stockCode in stockCodes) {
      for (final type in [KLineDataType.daily, KLineDataType.weekly]) {
        final file = File(await _cacheFilePath(stockCode, type));
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  /// Returns the number of cached series for [dataType].
  Future<int> countSeries(KLineDataType dataType) async {
    final codes = await listStockCodes(dataType: dataType);
    return codes.length;
  }

  /// Returns the most recent [updatedAt] timestamp across all cached series
  /// for [dataType], or null if no cache entries exist.
  Future<DateTime?> latestUpdatedAt(KLineDataType dataType) async {
    await initialize();
    final dir = Directory(_cacheDirectoryPath!);
    if (!await dir.exists()) return null;

    final suffix = '_${dataType.name}_ema_cache.json';
    DateTime? latest;

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = entity.path.split(Platform.pathSeparator).last;
      if (!fileName.endsWith(suffix)) continue;

      try {
        final content = await entity.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final updatedAt = DateTime.tryParse(
          (json['updatedAt'] as String? ?? ''),
        );
        if (updatedAt != null) {
          if (latest == null || updatedAt.isAfter(latest)) {
            latest = updatedAt;
          }
        }
      } catch (_) {}
    }

    return latest;
  }

  Future<Set<String>> listStockCodes({required KLineDataType dataType}) async {
    await initialize();
    final dir = Directory(_cacheDirectoryPath!);
    if (!await dir.exists()) {
      return <String>{};
    }

    final suffix = '_${dataType.name}_ema_cache.json';
    final result = <String>{};

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final fileName = entity.path.split(Platform.pathSeparator).last;
      if (!fileName.endsWith(suffix)) {
        continue;
      }
      final stockCode = fileName.substring(0, fileName.length - suffix.length);
      if (stockCode.isNotEmpty) {
        result.add(stockCode);
      }
    }

    return result;
  }

  Future<void> _saveSingle(EmaCacheSeries series) async {
    final file = File(await _cacheFilePath(series.stockCode, series.dataType));
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(jsonEncode(series.toJson())),
    );
  }

  Future<String> cacheFilePath(String stockCode, KLineDataType dataType) async {
    return _cacheFilePath(stockCode, dataType);
  }

  Future<String> _cacheFilePath(
    String stockCode,
    KLineDataType dataType,
  ) async {
    await initialize();
    return '$_cacheDirectoryPath/${stockCode}_${dataType.name}_ema_cache.json';
  }
}
