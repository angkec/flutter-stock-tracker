import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
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

enum DailyKlineCacheLoadStatus { ok, missing, corrupted }

class DailyKlineCacheLoadResult {
  const DailyKlineCacheLoadResult({required this.status, required this.bars});

  final DailyKlineCacheLoadStatus status;
  final List<KLine> bars;
}

class DailyKlineCacheStore {
  DailyKlineCacheStore({
    KLineFileStorage? storage,
    AtomicFileWriter? atomicWriter,
    this.defaultTargetBars = 260,
    this.defaultLookbackMonths = 18,
    this.defaultMaxConcurrentWrites = 8,
  }) : _storage = storage ?? KLineFileStorage(),
       _atomicWriter = atomicWriter ?? const AtomicFileWriter();

  final KLineFileStorage _storage;
  final AtomicFileWriter _atomicWriter;
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
    final payload = jsonEncode(
      deduped.map((bar) => bar.toJson()).toList(growable: false),
    );
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(payload),
    );
  }

  Future<Map<String, List<KLine>>> loadForStocks(
    List<String> stockCodes, {
    required DateTime anchorDate,
    int? targetBars,
    int? lookbackMonths,
  }) async {
    final loadedWithStatus = await _loadForStocksWithStatus(
      stockCodes,
      anchorDate: anchorDate,
      targetBars: targetBars,
      lookbackMonths: lookbackMonths,
    );
    final result = <String, List<KLine>>{};
    for (final entry in loadedWithStatus.entries) {
      if (entry.value.status == DailyKlineCacheLoadStatus.ok &&
          entry.value.bars.isNotEmpty) {
        result[entry.key] = entry.value.bars;
      }
    }
    return result;
  }

  Future<Map<String, DailyKlineCacheLoadResult>> loadForStocksWithStatus(
    List<String> stockCodes, {
    required DateTime anchorDate,
    int? targetBars,
    int? lookbackMonths,
  }) async {
    return _loadForStocksWithStatus(
      stockCodes,
      anchorDate: anchorDate,
      targetBars: targetBars,
      lookbackMonths: lookbackMonths,
    );
  }

  Future<Map<String, DailyKlineCacheLoadResult>> _loadForStocksWithStatus(
    List<String> stockCodes, {
    required DateTime anchorDate,
    int? targetBars,
    int? lookbackMonths,
  }) async {
    if (stockCodes.isEmpty) {
      return const <String, DailyKlineCacheLoadResult>{};
    }
    await initialize();

    final result = <String, DailyKlineCacheLoadResult>{};
    final target = targetBars ?? defaultTargetBars;
    final lookback = lookbackMonths ?? defaultLookbackMonths;

    final months = _recentMonths(anchorDate, lookback);
    for (final stockCode in stockCodes) {
      final snapshot = await _loadSnapshotFileWithStatus(stockCode);
      if (snapshot.$1 == DailyKlineCacheLoadStatus.corrupted) {
        result[stockCode] = const DailyKlineCacheLoadResult(
          status: DailyKlineCacheLoadStatus.corrupted,
          bars: <KLine>[],
        );
        continue;
      }

      var allBars = snapshot.$2;
      if (allBars.isEmpty) {
        allBars = await _loadFromLegacyMonthlyFiles(stockCode, months);
      }

      final normalizedBars = _normalizeBarsForRead(
        allBars,
        anchorDate: anchorDate,
        targetBars: target,
      );
      if (normalizedBars.isEmpty) {
        result[stockCode] = const DailyKlineCacheLoadResult(
          status: DailyKlineCacheLoadStatus.missing,
          bars: <KLine>[],
        );
        continue;
      }

      result[stockCode] = DailyKlineCacheLoadResult(
        status: DailyKlineCacheLoadStatus.ok,
        bars: normalizedBars,
      );
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

  Future<(DailyKlineCacheLoadStatus, List<KLine>)> _loadSnapshotFileWithStatus(
    String stockCode,
  ) async {
    final file = File(await _cacheFilePath(stockCode));
    if (!await file.exists()) {
      return (DailyKlineCacheLoadStatus.missing, const <KLine>[]);
    }

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! List<dynamic>) {
        return (DailyKlineCacheLoadStatus.corrupted, const <KLine>[]);
      }

      final bars = <KLine>[];
      for (final item in decoded) {
        if (item is! Map) {
          return (DailyKlineCacheLoadStatus.corrupted, const <KLine>[]);
        }
        final json = Map<String, dynamic>.from(item);
        bars.add(KLine.fromJson(json));
      }
      return (DailyKlineCacheLoadStatus.ok, bars);
    } catch (_) {
      return (DailyKlineCacheLoadStatus.corrupted, const <KLine>[]);
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

  List<KLine> _normalizeBarsForRead(
    List<KLine> source, {
    required DateTime anchorDate,
    required int targetBars,
  }) {
    final deduped = _deduplicateAndSort(source);
    if (deduped.isEmpty) return const <KLine>[];

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
    final cappedByAnchor = deduped
        .where((bar) => !bar.datetime.isAfter(normalizedAnchor))
        .toList(growable: false);
    if (cappedByAnchor.isEmpty) return const <KLine>[];

    if (cappedByAnchor.length > targetBars) {
      return cappedByAnchor.sublist(cappedByAnchor.length - targetBars);
    }
    return cappedByAnchor;
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
