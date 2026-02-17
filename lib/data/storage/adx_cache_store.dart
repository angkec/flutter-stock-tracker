import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/adx_config.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';

class AdxCacheSeries {
  final String stockCode;
  final KLineDataType dataType;
  final AdxConfig config;
  final String sourceSignature;
  final List<AdxPoint> points;
  final DateTime updatedAt;

  AdxCacheSeries({
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

  factory AdxCacheSeries.fromJson(Map<String, dynamic> json) {
    final points = ((json['points'] as List<dynamic>?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(AdxPoint.fromJson)
        .toList(growable: false);

    return AdxCacheSeries(
      stockCode: json['stockCode'] as String,
      dataType: KLineDataType.fromName(json['dataType'] as String),
      config: AdxConfig.fromJson(
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

class AdxCacheStore {
  AdxCacheStore({KLineFileStorage? storage, this.defaultMaxConcurrentWrites = 6})
    : _storage = storage ?? KLineFileStorage();

  final KLineFileStorage _storage;
  final int defaultMaxConcurrentWrites;
  bool _initialized = false;
  String? _cacheDirectoryPath;

  static const String _cacheSubDir = 'adx_cache';

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
    required AdxConfig config,
    required String sourceSignature,
    required List<AdxPoint> points,
  }) async {
    await saveAll([
      AdxCacheSeries(
        stockCode: stockCode,
        dataType: dataType,
        config: config,
        sourceSignature: sourceSignature,
        points: points,
      ),
    ]);
  }

  Future<void> saveAll(
    List<AdxCacheSeries> items, {
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

  Future<AdxCacheSeries?> loadSeries({
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
      return AdxCacheSeries.fromJson(json);
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

    final suffix = '_${dataType.name}_adx_cache.json';
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

  Future<void> _saveSingle(AdxCacheSeries series) async {
    final file = File(await _cacheFilePath(series.stockCode, series.dataType));
    final tmpFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );

    await tmpFile.writeAsString(jsonEncode(series.toJson()), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }

  Future<String> _cacheFilePath(
    String stockCode,
    KLineDataType dataType,
  ) async {
    await initialize();
    return '$_cacheDirectoryPath/${stockCode}_${dataType.name}_adx_cache.json';
  }
}
