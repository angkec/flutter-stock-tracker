import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';

const double _minOkRate = 0.90;
const int _sampleLimit = 10;
const int _weeklyMacdFetchBatchSize = 120;
const int _weeklyMacdPersistConcurrency = 8;
const int _weeklyAdxFetchBatchSize = 120;
const int _weeklyAdxPersistConcurrency = 8;

class _Manifest {
  final String path;
  final Map<String, dynamic> data;

  const _Manifest({required this.path, required this.data});
}

DateTime _dateOnly(DateTime input) {
  return DateTime(input.year, input.month, input.day);
}

String _formatDate(DateTime input) {
  return '${input.year.toString().padLeft(4, '0')}-'
      '${input.month.toString().padLeft(2, '0')}-'
      '${input.day.toString().padLeft(2, '0')}';
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '${minutes}m${seconds.toString().padLeft(2, '0')}s';
}

bool _failsOkRate({
  required int failedCount,
  required int total,
  double minOkRate = _minOkRate,
}) {
  if (total <= 0) return false;
  final okRate = (total - failedCount) / total;
  return okRate < minOkRate;
}

String _formatValidationSummary({
  required String label,
  required int failedCount,
  required int stageTotal,
  required List<String> order,
  int sampleLimit = _sampleLimit,
}) {
  final percent =
      stageTotal <= 0 ? 0.0 : (failedCount * 100 / stageTotal.toDouble());
  final ids = order.isEmpty ? 'none' : order.take(sampleLimit).join(', ');
  return '$label: $failedCount (${percent.toStringAsFixed(1)}%) ids: $ids';
}

List<KLine> _normalizeBarsOrder(List<KLine> bars) {
  if (bars.length < 2) {
    return bars;
  }

  for (var i = 1; i < bars.length; i++) {
    if (bars[i - 1].datetime.isAfter(bars[i].datetime)) {
      final sorted = List<KLine>.from(bars);
      sorted.sort((a, b) => a.datetime.compareTo(b.datetime));
      return sorted;
    }
  }

  return bars;
}

DateTime _subtractMonths(DateTime date, int months) {
  final totalMonths = date.year * 12 + date.month - 1 - months;
  final targetYear = totalMonths ~/ 12;
  final targetMonth = totalMonths % 12 + 1;
  final targetDay = min(date.day, _daysInMonth(targetYear, targetMonth));
  return DateTime(
    targetYear,
    targetMonth,
    targetDay,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
}

int _daysInMonth(int year, int month) {
  if (month == 12) {
    return DateTime(year + 1, 1, 0).day;
  }
  return DateTime(year, month + 1, 0).day;
}

int _expectedAdxPoints(int barsLength, int period) {
  if (barsLength < period + 1) return 0;
  return (barsLength - (2 * period - 1)).clamp(0, barsLength);
}

int _expectedMacdPoints(List<KLine> bars, int windowMonths) {
  if (bars.isEmpty) return 0;
  final normalized = _normalizeBarsOrder(bars);
  final latest = normalized.last.datetime;
  final cutoff = _subtractMonths(latest, windowMonths);
  return normalized.where((bar) => !bar.datetime.isBefore(cutoff)).length;
}

void _recordFailure({
  required Map<String, int> bucket,
  required List<String> order,
  required String stockCode,
  int count = 1,
}) {
  if (!bucket.containsKey(stockCode)) {
    bucket[stockCode] = count;
    order.add(stockCode);
  }
}

Future<_Manifest> _loadLatestManifest() async {
  final reportDir = Directory(p.join(Directory.current.path, 'docs', 'reports'));
  if (!await reportDir.exists()) {
    throw StateError('Missing docs/reports; run data_layer_real_e2e first.');
  }

  final manifests = <File>[];
  await for (final entity in reportDir.list()) {
    if (entity is File &&
        entity.path.endsWith('-data-layer-real-e2e.json')) {
      manifests.add(entity);
    }
  }

  if (manifests.isEmpty) {
    throw StateError('No data-layer manifest found; run data_layer_real_e2e first.');
  }

  manifests.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  final latest = manifests.first;
  final content = await latest.readAsString();
  final data = jsonDecode(content) as Map<String, dynamic>;

  final result = data['result'] as String? ?? 'UNKNOWN';
  if (result != 'PASS') {
    final failureSummary = data['failureSummary'];
    throw StateError(
      'Latest manifest is not PASS (result=$result, failure=$failureSummary).',
    );
  }

  return _Manifest(path: latest.path, data: data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('expectedAdxPoints matches algorithm length', () {
    expect(_expectedAdxPoints(27, 14), 0);
    expect(_expectedAdxPoints(28, 14), 1);
    expect(_expectedAdxPoints(29, 14), 2);
  });

  test(
    'indicator layer real e2e (full stock, real network)',
    () async {
      SharedPreferences.setMockInitialValues({});

      final startedAt = DateTime.now();
      final dateKey = _formatDate(startedAt);

      final stageDurations = <String, Duration>{};
      final stageTotals = <String, int>{};

      final dailyMacdFailures = <String, int>{};
      final weeklyMacdFailures = <String, int>{};
      final dailyAdxFailures = <String, int>{};
      final weeklyAdxFailures = <String, int>{};

      final dailyMacdOrder = <String>[];
      final weeklyMacdOrder = <String>[];
      final dailyAdxOrder = <String>[];
      final weeklyAdxOrder = <String>[];

      Object? caughtError;
      StackTrace? caughtStack;
      String? failureSummary;
      String? originalDbPath;

      MarketDatabase? database;
      MarketDataRepository? repository;

      try {
        final manifest = await _loadLatestManifest();
        final data = manifest.data;

        final fileRoot = data['fileRoot'] as String? ?? '';
        final dbRoot = data['dbRoot'] as String? ?? '';
        if (fileRoot.isEmpty || dbRoot.isEmpty) {
          throw StateError('Manifest missing fileRoot/dbRoot: ${manifest.path}');
        }
        if (!Directory(fileRoot).existsSync()) {
          throw StateError('Manifest fileRoot not found: $fileRoot');
        }
        if (!Directory(dbRoot).existsSync()) {
          throw StateError('Manifest dbRoot not found: $dbRoot');
        }

        final eligibleStocks =
            (data['eligibleStocks'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false);
        if (eligibleStocks.isEmpty) {
          throw StateError('Manifest has no eligible stocks: ${manifest.path}');
        }

        final dailyBlock =
            Map<String, dynamic>.from(data['daily'] as Map<String, dynamic>);
        final weeklyBlock =
            Map<String, dynamic>.from(data['weekly'] as Map<String, dynamic>);
        final anchorDate = DateTime.parse(dailyBlock['anchorDate'] as String);
        final dailyTargetBars = dailyBlock['targetBars'] as int? ?? 0;
        final weeklyRangeStart =
            DateTime.parse(weeklyBlock['rangeStart'] as String);
        final weeklyRangeEnd =
            DateTime.parse(weeklyBlock['rangeEnd'] as String);
        final weeklyTargetBars = weeklyBlock['targetBars'] as int? ?? 0;

        stageTotals['daily'] = eligibleStocks.length;
        stageTotals['weekly'] = eligibleStocks.length;

        final fileStorage = KLineFileStorage();
        fileStorage.setBaseDirPathForTesting(fileRoot);
        await fileStorage.initialize();
        final dailyFileStorage = KLineFileStorageV2();
        dailyFileStorage.setBaseDirPathForTesting(fileRoot);
        await dailyFileStorage.initialize();
        originalDbPath = await databaseFactory.getDatabasesPath();
        await databaseFactory.setDatabasesPath(dbRoot);

        database = MarketDatabase();
        await database.database;

        final metadataManager = KLineMetadataManager(
          database: database,
          fileStorage: fileStorage,
          dailyFileStorage: dailyFileStorage,
        );

        repository = MarketDataRepository(metadataManager: metadataManager);
        final activeRepo = repository!;

        final macdCacheStore = MacdCacheStore(storage: fileStorage);
        final adxCacheStore = AdxCacheStore(storage: fileStorage);

        final macdService = MacdIndicatorService(
          repository: activeRepo,
          cacheStore: macdCacheStore,
        );
        final adxService = AdxIndicatorService(
          repository: activeRepo,
          cacheStore: adxCacheStore,
        );

        await Future.wait([macdService.load(), adxService.load()]);

        final dailyCacheStore = DailyKlineCacheStore(storage: fileStorage);
        final dailyLoadStopwatch = Stopwatch()..start();
        final dailyLoaded = await dailyCacheStore.loadForStocksWithStatus(
          eligibleStocks,
          anchorDate: _dateOnly(anchorDate),
          targetBars: dailyTargetBars,
        );
        dailyLoadStopwatch.stop();

        final dailyBarsByStock = <String, List<KLine>>{};
        for (final entry in dailyLoaded.entries) {
          if (entry.value.status == DailyKlineCacheLoadStatus.ok &&
              entry.value.bars.isNotEmpty) {
            dailyBarsByStock[entry.key] = entry.value.bars;
          }
        }

        final dailyPrewarmStopwatch = Stopwatch()..start();
        await Future.wait([
          macdService.prewarmFromBars(
            dataType: KLineDataType.daily,
            barsByStockCode: dailyBarsByStock,
          ),
          adxService.prewarmFromBars(
            dataType: KLineDataType.daily,
            barsByStockCode: dailyBarsByStock,
          ),
        ]);
        dailyPrewarmStopwatch.stop();
        stageDurations['daily_prewarm'] = dailyPrewarmStopwatch.elapsed;
        stageDurations['daily_load'] = dailyLoadStopwatch.elapsed;

        final weeklyRange = DateRange(weeklyRangeStart, weeklyRangeEnd);
        final weeklyPrewarmStopwatch = Stopwatch()..start();
        await macdService.prewarmFromRepository(
          stockCodes: eligibleStocks,
          dataType: KLineDataType.weekly,
          dateRange: weeklyRange,
          fetchBatchSize: _weeklyMacdFetchBatchSize,
          maxConcurrentPersistWrites: _weeklyMacdPersistConcurrency,
          forceRecompute: true,
        );
        await adxService.prewarmFromRepository(
          stockCodes: eligibleStocks,
          dataType: KLineDataType.weekly,
          dateRange: weeklyRange,
          fetchBatchSize: _weeklyAdxFetchBatchSize,
          maxConcurrentPersistWrites: _weeklyAdxPersistConcurrency,
          forceRecompute: true,
        );
        weeklyPrewarmStopwatch.stop();
        stageDurations['weekly_prewarm'] = weeklyPrewarmStopwatch.elapsed;

        final dailyValidateStopwatch = Stopwatch()..start();
        final dailyMacdWindow = macdService.configFor(KLineDataType.daily);
        final dailyAdxConfig = adxService.configFor(KLineDataType.daily);

        for (final stockCode in eligibleStocks) {
          final dailyBars = dailyLoaded[stockCode]?.bars ?? const <KLine>[];
          if (dailyBars.isEmpty) {
            _recordFailure(
              bucket: dailyMacdFailures,
              order: dailyMacdOrder,
              stockCode: stockCode,
            );
            _recordFailure(
              bucket: dailyAdxFailures,
              order: dailyAdxOrder,
              stockCode: stockCode,
            );
            continue;
          }

          final expectedMacd =
              _expectedMacdPoints(dailyBars, dailyMacdWindow.windowMonths);
          final macdSeries = await macdCacheStore.loadSeries(
            stockCode: stockCode,
            dataType: KLineDataType.daily,
          );
          final actualMacd = macdSeries?.points.length ?? 0;
          if (actualMacd != expectedMacd) {
            _recordFailure(
              bucket: dailyMacdFailures,
              order: dailyMacdOrder,
              stockCode: stockCode,
            );
          }

          final expectedAdx = _expectedAdxPoints(
            dailyBars.length,
            dailyAdxConfig.period,
          );
          final adxSeries = await adxCacheStore.loadSeries(
            stockCode: stockCode,
            dataType: KLineDataType.daily,
          );
          final actualAdx = adxSeries?.points.length ?? 0;
          if (actualAdx != expectedAdx) {
            _recordFailure(
              bucket: dailyAdxFailures,
              order: dailyAdxOrder,
              stockCode: stockCode,
            );
          }
        }
        dailyValidateStopwatch.stop();
        stageDurations['daily_validate'] = dailyValidateStopwatch.elapsed;

        final weeklyValidateStopwatch = Stopwatch()..start();
        final weeklyBarsByStock = await activeRepo.getKlines(
          stockCodes: eligibleStocks,
          dateRange: weeklyRange,
          dataType: KLineDataType.weekly,
        );

        final weeklyMacdWindow = macdService.configFor(KLineDataType.weekly);
        final weeklyAdxConfig = adxService.configFor(KLineDataType.weekly);

        for (final stockCode in eligibleStocks) {
          final weeklyBars = weeklyBarsByStock[stockCode] ?? const <KLine>[];
          if (weeklyBars.length < weeklyTargetBars) {
            _recordFailure(
              bucket: weeklyMacdFailures,
              order: weeklyMacdOrder,
              stockCode: stockCode,
            );
            _recordFailure(
              bucket: weeklyAdxFailures,
              order: weeklyAdxOrder,
              stockCode: stockCode,
            );
            continue;
          }

          final expectedMacd =
              _expectedMacdPoints(weeklyBars, weeklyMacdWindow.windowMonths);
          final macdSeries = await macdCacheStore.loadSeries(
            stockCode: stockCode,
            dataType: KLineDataType.weekly,
          );
          final actualMacd = macdSeries?.points.length ?? 0;
          if (actualMacd != expectedMacd) {
            _recordFailure(
              bucket: weeklyMacdFailures,
              order: weeklyMacdOrder,
              stockCode: stockCode,
            );
          }

          final expectedAdx = _expectedAdxPoints(
            weeklyBars.length,
            weeklyAdxConfig.period,
          );
          final adxSeries = await adxCacheStore.loadSeries(
            stockCode: stockCode,
            dataType: KLineDataType.weekly,
          );
          final actualAdx = adxSeries?.points.length ?? 0;
          if (actualAdx != expectedAdx) {
            _recordFailure(
              bucket: weeklyAdxFailures,
              order: weeklyAdxOrder,
              stockCode: stockCode,
            );
          }
        }
        weeklyValidateStopwatch.stop();
        stageDurations['weekly_validate'] = weeklyValidateStopwatch.elapsed;

        final total = eligibleStocks.length;
        final failures = <String>[];
        if (_failsOkRate(failedCount: dailyMacdFailures.length, total: total)) {
          failures.add('daily macd < 90% ok');
        }
        if (_failsOkRate(failedCount: weeklyMacdFailures.length, total: total)) {
          failures.add('weekly macd < 90% ok');
        }
        if (_failsOkRate(failedCount: dailyAdxFailures.length, total: total)) {
          failures.add('daily adx < 90% ok');
        }
        if (_failsOkRate(failedCount: weeklyAdxFailures.length, total: total)) {
          failures.add('weekly adx < 90% ok');
        }

        if (failures.isNotEmpty) {
          failureSummary = failures.join('; ');
        }
      } catch (error, stackTrace) {
        caughtError = error;
        caughtStack = stackTrace;
        failureSummary ??= 'exception: $error';
      } finally {
        final endedAt = DateTime.now();
        final reportDir = Directory(
          p.join(Directory.current.path, 'docs', 'reports'),
        );
        await reportDir.create(recursive: true);
        final reportFile = File(
          p.join(reportDir.path, '${dateKey}-indicator-layer-real-e2e.md'),
        );

        final total = stageTotals['daily'] ?? 0;
        final buffer = StringBuffer();
        buffer.writeln('# Indicator Layer Real E2E Report');
        buffer.writeln('');
        buffer.writeln('- Date: $dateKey');
        buffer.writeln('- Started: $startedAt');
        buffer.writeln('- Ended: $endedAt');
        buffer.writeln(
          '- Duration: ${_formatDuration(endedAt.difference(startedAt))}',
        );
        buffer.writeln('');
        buffer.writeln('## Config');
        buffer.writeln('- eligibleStocks: $total');
        buffer.writeln('- weeklyMacdFetchBatchSize: $_weeklyMacdFetchBatchSize');
        buffer.writeln(
          '- weeklyMacdPersistConcurrency: $_weeklyMacdPersistConcurrency',
        );
        buffer.writeln('- weeklyAdxFetchBatchSize: $_weeklyAdxFetchBatchSize');
        buffer.writeln(
          '- weeklyAdxPersistConcurrency: $_weeklyAdxPersistConcurrency',
        );
        buffer.writeln('');
        buffer.writeln('## Stages');
        buffer.writeln(
          '- daily load: ${_formatDuration(stageDurations['daily_load'] ?? Duration.zero)}',
        );
        buffer.writeln(
          '- daily prewarm: ${_formatDuration(stageDurations['daily_prewarm'] ?? Duration.zero)}',
        );
        buffer.writeln(
          '- weekly prewarm: ${_formatDuration(stageDurations['weekly_prewarm'] ?? Duration.zero)}',
        );
        buffer.writeln(
          '- daily validate: ${_formatDuration(stageDurations['daily_validate'] ?? Duration.zero)}',
        );
        buffer.writeln(
          '- weekly validate: ${_formatDuration(stageDurations['weekly_validate'] ?? Duration.zero)}',
        );
        buffer.writeln('');
        buffer.writeln('## Validation Results');
        buffer.writeln(
          _formatValidationSummary(
            label: 'daily macd',
            failedCount: dailyMacdFailures.length,
            stageTotal: total,
            order: dailyMacdOrder,
          ),
        );
        buffer.writeln(
          _formatValidationSummary(
            label: 'weekly macd',
            failedCount: weeklyMacdFailures.length,
            stageTotal: total,
            order: weeklyMacdOrder,
          ),
        );
        buffer.writeln(
          _formatValidationSummary(
            label: 'daily adx',
            failedCount: dailyAdxFailures.length,
            stageTotal: total,
            order: dailyAdxOrder,
          ),
        );
        buffer.writeln(
          _formatValidationSummary(
            label: 'weekly adx',
            failedCount: weeklyAdxFailures.length,
            stageTotal: total,
            order: weeklyAdxOrder,
          ),
        );
        buffer.writeln('');
        buffer.writeln('## Summary');
        buffer.writeln('- result: ${failureSummary == null ? 'PASS' : 'FAIL'}');
        if (failureSummary != null) {
          buffer.writeln('- failures: $failureSummary');
        }
        if (caughtError != null) {
          buffer.writeln('- exception: $caughtError');
        }

        await reportFile.writeAsString(buffer.toString(), flush: true);

        if (repository != null) {
          await repository.dispose();
        }
        if (database != null) {
          try {
            await database.close();
          } catch (_) {}
          MarketDatabase.resetInstance();
        }
        if (originalDbPath != null) {
          await databaseFactory.setDatabasesPath(originalDbPath!);
        }
      }

      if (caughtError != null) {
        Error.throwWithStackTrace(caughtError!, caughtStack!);
      }
      if (failureSummary != null) {
        fail(failureSummary!);
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
