import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class DailyKlineCacheStats {
  final int stockCount;
  final int totalBytes;

  const DailyKlineCacheStats({
    required this.stockCount,
    required this.totalBytes,
  });
}

class DailyKlineCacheStore {
  DailyKlineCacheStore({
    KLineFileStorage? storage,
    this.defaultTargetBars = 260,
    this.defaultLookbackMonths = 18,
    this.defaultMaxConcurrentWrites = 8,
  }) : _storage = storage ?? KLineFileStorage();

  final KLineFileStorage _storage;
  final int defaultTargetBars;
  final int defaultLookbackMonths;
  final int defaultMaxConcurrentWrites;
  bool _initialized = false;
  String? _cacheDirectoryPath;

  static const String _dailyCacheSubDir = 'daily_cache';

  Future<void> initialize() async {
    if (_initialized) return;
    await _storage.initialize();

    final baseDir = await _storage.getBaseDirectoryPath();
    final cacheDir = Directory('$baseDir/$_dailyCacheSubDir');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirectoryPath = cacheDir.path;
    _initialized = true;
  }

  Future<void> saveAll(
    Map<String, List<KLine>> barsByStockCode, {
    void Function(int current, int total)? onProgress,
    int? maxConcurrentWrites,
  }) async {
    if (barsByStockCode.isEmpty) return;
    await initialize();

    final entries = barsByStockCode.entries.toList(growable: false);
    var completed = 0;
    final total = entries.length;

    final workerCount = min(
      max(1, maxConcurrentWrites ?? defaultMaxConcurrentWrites),
      total,
    );
    var nextIndex = 0;

    Future<void> runWorker() async {
      while (true) {
        final currentIndex = nextIndex;
        if (currentIndex >= entries.length) {
          return;
        }
        nextIndex++;

        final entry = entries[currentIndex];
        await _saveSingleStock(entry.key, entry.value);

        completed++;
        onProgress?.call(completed, total);
      }
    }

    await Future.wait(
      List.generate(workerCount, (_) => runWorker(), growable: false),
    );
  }

  Future<void> _saveSingleStock(String stockCode, List<KLine> bars) async {
    if (bars.isEmpty) {
      return;
    }

    final deduped = _deduplicateAndSort(bars);
    if (deduped.isEmpty) {
      return;
    }

    final file = File(await _cacheFilePath(stockCode));
    final tempFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );

    final payload = jsonEncode(
      deduped.map((bar) => bar.toJson()).toList(growable: false),
    );
    await tempFile.writeAsString(payload, flush: true);

    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  Future<Map<String, List<KLine>>> loadForStocks(
    List<String> stockCodes, {
    required DateTime anchorDate,
    int? targetBars,
    int? lookbackMonths,
  }) async {
    if (stockCodes.isEmpty) return const <String, List<KLine>>{};
    await initialize();

    final result = <String, List<KLine>>{};
    final target = targetBars ?? defaultTargetBars;
    final lookback = lookbackMonths ?? defaultLookbackMonths;

    final months = _recentMonths(anchorDate, lookback);
    for (final stockCode in stockCodes) {
      var allBars = await _loadSnapshotFile(stockCode);

      if (allBars.isEmpty) {
        allBars = await _loadFromLegacyMonthlyFiles(stockCode, months);
      }

      final deduped = _deduplicateAndSort(allBars);
      if (deduped.isEmpty) continue;

      final normalizedAnchor = DateTime(
        anchorDate.year,
        anchorDate.month,
        anchorDate.day,
        23,
        59,
        59,
        999,
        999,
      );
      final capped = deduped
          .where((bar) => !bar.datetime.isAfter(normalizedAnchor))
          .toList(growable: false);
      if (capped.isEmpty) continue;

      if (capped.length > target) {
        result[stockCode] = capped.sublist(capped.length - target);
      } else {
        result[stockCode] = capped;
      }
    }

    return result;
  }

  Future<void> clearForStocks(
    List<String> stockCodes, {
    required DateTime anchorDate,
    int? lookbackMonths,
  }) async {
    if (stockCodes.isEmpty) return;
    await initialize();

    final lookback = lookbackMonths ?? defaultLookbackMonths;
    final months = _recentMonths(anchorDate, lookback);
    for (final stockCode in stockCodes) {
      final snapshotFile = File(await _cacheFilePath(stockCode));
      if (await snapshotFile.exists()) {
        await snapshotFile.delete();
      }

      for (final month in months) {
        await _storage.deleteMonthlyFile(
          stockCode,
          KLineDataType.daily,
          month.$1,
          month.$2,
        );
      }
    }
  }

  Future<DailyKlineCacheStats> getSnapshotStats() async {
    await initialize();

    final cacheDirPath = _cacheDirectoryPath;
    if (cacheDirPath == null || cacheDirPath.isEmpty) {
      return const DailyKlineCacheStats(stockCount: 0, totalBytes: 0);
    }

    final cacheDir = Directory(cacheDirPath);
    if (!await cacheDir.exists()) {
      return const DailyKlineCacheStats(stockCount: 0, totalBytes: 0);
    }

    var stockCount = 0;
    var totalBytes = 0;

    await for (final entity in cacheDir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('_daily_cache.json')) continue;

      stockCount++;
      try {
        totalBytes += await entity.length();
      } catch (_) {
        // Ignore transient file errors while collecting stats.
      }
    }

    return DailyKlineCacheStats(stockCount: stockCount, totalBytes: totalBytes);
  }

  Future<List<KLine>> _loadSnapshotFile(String stockCode) async {
    final file = File(await _cacheFilePath(stockCode));
    if (!await file.exists()) {
      return const <KLine>[];
    }

    try {
      final content = await file.readAsString();
      final jsonList = jsonDecode(content) as List<dynamic>;
      return jsonList
          .whereType<Map<String, dynamic>>()
          .map((json) => KLine.fromJson(json))
          .toList(growable: false);
    } catch (_) {
      return const <KLine>[];
    }
  }

  Future<List<KLine>> _loadFromLegacyMonthlyFiles(
    String stockCode,
    List<(int, int)> months,
  ) async {
    final allBars = <KLine>[];
    for (final month in months) {
      final monthly = await _storage.loadMonthlyKlineFile(
        stockCode,
        KLineDataType.daily,
        month.$1,
        month.$2,
      );
      if (monthly.isNotEmpty) {
        allBars.addAll(monthly);
      }
    }
    return allBars;
  }

  Future<String> _cacheFilePath(String stockCode) async {
    await initialize();
    return '$_cacheDirectoryPath/${stockCode}_daily_cache.json';
  }

  List<KLine> _deduplicateAndSort(List<KLine> source) {
    if (source.isEmpty) return const <KLine>[];

    final byDatetime = <DateTime, KLine>{
      for (final bar in source) bar.datetime: bar,
    };

    final deduped = byDatetime.values.toList(growable: false)
      ..sort((a, b) => a.datetime.compareTo(b.datetime));
    return deduped;
  }

  List<(int, int)> _recentMonths(DateTime anchorDate, int lookbackMonths) {
    final months = <(int, int)>[];
    final normalized = DateTime(anchorDate.year, anchorDate.month, 1);
    for (var index = 0; index < max(1, lookbackMonths); index++) {
      final monthDate = DateTime(normalized.year, normalized.month - index, 1);
      months.add((monthDate.year, monthDate.month));
    }
    return months;
  }
}
