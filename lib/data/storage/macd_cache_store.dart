import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';

class MacdCacheSeries {
  final String stockCode;
  final KLineDataType dataType;
  final MacdConfig config;
  final String sourceSignature;
  final List<MacdPoint> points;
  final DateTime updatedAt;

  MacdCacheSeries({
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

  factory MacdCacheSeries.fromJson(Map<String, dynamic> json) {
    final points = ((json['points'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(MacdPoint.fromJson)
        .toList(growable: false);

    return MacdCacheSeries(
      stockCode: json['stockCode'] as String,
      dataType: KLineDataType.fromName(json['dataType'] as String),
      config: MacdConfig.fromJson(
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

class MacdCacheStore {
  MacdCacheStore({
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

  static const String _cacheSubDir = 'macd_cache';

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
    required MacdConfig config,
    required String sourceSignature,
    required List<MacdPoint> points,
  }) async {
    await saveAll([
      MacdCacheSeries(
        stockCode: stockCode,
        dataType: dataType,
        config: config,
        sourceSignature: sourceSignature,
        points: points,
      ),
    ]);
  }

  Future<void> saveAll(
    List<MacdCacheSeries> items, {
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

  Future<MacdCacheSeries?> loadSeries({
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
      return MacdCacheSeries.fromJson(json);
    } catch (_) {
      return null;
    }
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

  Future<Set<String>> listStockCodes({required KLineDataType dataType}) async {
    await initialize();
    final dir = Directory(_cacheDirectoryPath!);
    if (!await dir.exists()) {
      return <String>{};
    }

    final suffix = '_${dataType.name}_macd_cache.json';
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

  Future<void> _saveSingle(MacdCacheSeries series) async {
    final file = File(await _cacheFilePath(series.stockCode, series.dataType));
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(jsonEncode(series.toJson())),
    );
  }

  Future<String> _cacheFilePath(
    String stockCode,
    KLineDataType dataType,
  ) async {
    await initialize();
    return '$_cacheDirectoryPath/${stockCode}_${dataType.name}_macd_cache.json';
  }
}
