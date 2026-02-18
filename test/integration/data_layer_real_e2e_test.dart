import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/config/minute_sync_config.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/daily_kline_sync_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

const int _dailyTargetBars = 260;
const int _weeklyTargetBars = 100;
const int _weeklyRangeDays = 760;
const int _minuteRangeDays = 30;
const int _minuteMinCompleteBars = 220;
const int _minuteReadConcurrency = 6;
const int _poolSize = 12;

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

bool _isAllowedNoDataError(String message) {
  return message == 'empty_fetch_result' || message == 'No minute bars returned';
}

String _formatTopCounts(Map<String, int> values, {int limit = 12}) {
  if (values.isEmpty) return 'none';
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = entries.take(limit).map((e) => '${e.key}: ${e.value}');
  return top.join(', ');
}

List<DateTime> _weekdayDates(DateTime startDay, DateTime endDay) {
  if (startDay.isAfter(endDay)) return const [];
  final days = <DateTime>[];
  var cursor = _dateOnly(startDay);
  final normalizedEnd = _dateOnly(endDay);
  while (!cursor.isAfter(normalizedEnd)) {
    if (cursor.weekday >= DateTime.monday &&
        cursor.weekday <= DateTime.friday) {
      days.add(cursor);
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return days;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'data layer real e2e (full stock, real network)',
    () async {
      SharedPreferences.setMockInitialValues({});

      final startedAt = DateTime.now();
      final dateKey = _formatDate(startedAt);

      final stageDurations = <String, Duration>{};
      final stageTotals = <String, int>{};
      final stageSuccess = <String, int>{};
      final stageRecords = <String, int>{};
      final allowedErrors = <String, Map<String, String>>{};
      final fatalErrors = <String, Map<String, String>>{};

      final dailyShort = <String, int>{};
      final weeklyShort = <String, int>{};
      final minuteMissingDays = <String, int>{};
      final minuteIncompleteDays = <String, int>{};

      final minuteTradingDates = <DateTime>{};

      Object? caughtError;
      StackTrace? caughtStack;
      String? failureSummary;

      Directory? rootDir;
      Directory? fileRoot;
      Directory? dbRoot;
      MarketDatabase? database;
      MarketDataRepository? repository;
      TdxPool? pool;

      DateRange? weeklyRange;
      DateRange? minuteRange;

      try {
        rootDir = await Directory.systemTemp.createTemp(
          'data_layer_real_e2e_',
        );
        fileRoot = Directory(p.join(rootDir.path, 'files'));
        dbRoot = Directory(p.join(rootDir.path, 'db'));
        await fileRoot.create(recursive: true);
        await dbRoot.create(recursive: true);
        await databaseFactory.setDatabasesPath(dbRoot.path);

        final fileStorage = KLineFileStorage();
        fileStorage.setBaseDirPathForTesting(fileRoot.path);
        await fileStorage.initialize();

        database = MarketDatabase();
        await database.database;

        final metadataManager = KLineMetadataManager(
          database: database,
          fileStorage: fileStorage,
        );

        pool = TdxPool(poolSize: _poolSize);
        final activePool = pool!;
        final poolAdapter = TdxPoolFetchAdapter(pool: activePool);

        final dailyCacheStore = DailyKlineCacheStore(storage: fileStorage);
        final dailyCheckpointStore = DailyKlineCheckpointStore(
          storage: fileStorage,
        );
        final dailySyncService = DailyKlineSyncService(
          checkpointStore: dailyCheckpointStore,
          cacheStore: dailyCacheStore,
          fetcher: ({
            required stocks,
            required count,
            required mode,
            onProgress,
          }) async {
            final barsByCode = <String, List<KLine>>{};
            var completed = 0;
            await activePool.batchGetSecurityBarsStreaming(
              stocks: stocks,
              category: klineTypeDaily,
              start: 0,
              count: count,
              onStockBars: (index, bars) {
                barsByCode[stocks[index].code] = bars;
                completed++;
                onProgress?.call(completed, stocks.length);
              },
            );
            return barsByCode;
          },
        );

        repository = MarketDataRepository(
          metadataManager: metadataManager,
          minuteFetchAdapter: poolAdapter,
          klineFetchAdapter: poolAdapter,
          minuteSyncConfig: const MinuteSyncConfig(
            enablePoolMinutePipeline: true,
            enableMinutePipelineLogs: false,
            minutePipelineFallbackToLegacyOnError: true,
            poolBatchCount: 800,
            poolMaxBatches: 10,
            minuteWriteConcurrency: 6,
          ),
        );
        final activeRepo = repository!;

        final connected = await activePool.ensureConnected();
        expect(connected, isTrue);

        final stockService = StockService(activePool);
        final stocks = await stockService.getAllStocks();
        expect(stocks, isNotEmpty);
        final stockCodes =
            stocks.map((stock) => stock.code).toList(growable: false);

        stageTotals['daily'] = stockCodes.length;
        stageTotals['weekly'] = stockCodes.length;
        stageTotals['minute'] = stockCodes.length;

        final anchorDay = _dateOnly(DateTime.now());
        final anchorDate = DateTime(
          anchorDay.year,
          anchorDay.month,
          anchorDay.day,
          23,
          59,
          59,
          999,
          999,
        );

        // Stage 1: Daily sync (force full)
        final dailyStopwatch = Stopwatch()..start();
        final dailyResult = await dailySyncService.sync(
          mode: DailyKlineSyncMode.forceFull,
          stocks: stocks,
          targetBars: _dailyTargetBars,
        );
        dailyStopwatch.stop();
        stageDurations['daily_fetch'] = dailyStopwatch.elapsed;
        stageSuccess['daily'] = dailyResult.successStockCodes.length;

        final dailyAllowed = <String, String>{};
        final dailyFatal = <String, String>{};
        for (final entry in dailyResult.failureReasons.entries) {
          if (_isAllowedNoDataError(entry.value)) {
            dailyAllowed[entry.key] = entry.value;
          } else {
            dailyFatal[entry.key] = entry.value;
          }
        }
        allowedErrors['daily'] = dailyAllowed;
        fatalErrors['daily'] = dailyFatal;

        final dailyValidateStopwatch = Stopwatch()..start();
        var dailyTotalRecords = 0;
        final minuteStartDay = anchorDay.subtract(
          const Duration(days: _minuteRangeDays),
        );

        for (final stockCode in stockCodes) {
          final loaded = await dailyCacheStore.loadForStocksWithStatus(
            [stockCode],
            anchorDate: anchorDate,
            targetBars: _dailyTargetBars,
          );
          final bars = loaded[stockCode]?.bars ?? const <KLine>[];
          dailyTotalRecords += bars.length;

          if (bars.length < _dailyTargetBars) {
            dailyShort[stockCode] = bars.length;
          }

          for (final bar in bars) {
            final day = _dateOnly(bar.datetime);
            if (!day.isBefore(minuteStartDay) && !day.isAfter(anchorDay)) {
              minuteTradingDates.add(day);
            }
          }
        }

        dailyValidateStopwatch.stop();
        stageDurations['daily_validate'] = dailyValidateStopwatch.elapsed;
        stageRecords['daily'] = dailyTotalRecords;

        // Stage 2: Weekly refetch
        final now = DateTime.now();
        weeklyRange = DateRange(
          now.subtract(const Duration(days: _weeklyRangeDays)),
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999),
        );
        final weeklyStopwatch = Stopwatch()..start();
        final activeWeeklyRange = weeklyRange!;
        final weeklyResult = await activeRepo.refetchData(
          stockCodes: stockCodes,
          dateRange: activeWeeklyRange,
          dataType: KLineDataType.weekly,
        );
        weeklyStopwatch.stop();
        stageDurations['weekly_fetch'] = weeklyStopwatch.elapsed;
        stageSuccess['weekly'] = weeklyResult.successCount;
        stageRecords['weekly'] = weeklyResult.totalRecords;

        final weeklyAllowed = <String, String>{};
        final weeklyFatal = <String, String>{};
        for (final entry in weeklyResult.errors.entries) {
          if (_isAllowedNoDataError(entry.value)) {
            weeklyAllowed[entry.key] = entry.value;
          } else {
            weeklyFatal[entry.key] = entry.value;
          }
        }
        allowedErrors['weekly'] = weeklyAllowed;
        fatalErrors['weekly'] = weeklyFatal;

        final weeklyValidateStopwatch = Stopwatch()..start();
        final weeklyBarsByStock = await activeRepo.getKlines(
          stockCodes: stockCodes,
          dateRange: activeWeeklyRange,
          dataType: KLineDataType.weekly,
        );
        for (final stockCode in stockCodes) {
          final bars = weeklyBarsByStock[stockCode] ?? const <KLine>[];
          if (bars.length < _weeklyTargetBars) {
            weeklyShort[stockCode] = bars.length;
          }
        }
        weeklyValidateStopwatch.stop();
        stageDurations['weekly_validate'] = weeklyValidateStopwatch.elapsed;

        // Stage 3: Minute refetch
        minuteRange = DateRange(
          now.subtract(const Duration(days: _minuteRangeDays)),
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999),
        );
        final minuteStopwatch = Stopwatch()..start();
        final activeMinuteRange = minuteRange!;
        final minuteResult = await activeRepo.refetchData(
          stockCodes: stockCodes,
          dateRange: activeMinuteRange,
          dataType: KLineDataType.oneMinute,
        );
        minuteStopwatch.stop();
        stageDurations['minute_fetch'] = minuteStopwatch.elapsed;
        stageSuccess['minute'] = minuteResult.successCount;
        stageRecords['minute'] = minuteResult.totalRecords;

        final minuteAllowed = <String, String>{};
        final minuteFatal = <String, String>{};
        for (final entry in minuteResult.errors.entries) {
          if (_isAllowedNoDataError(entry.value)) {
            minuteAllowed[entry.key] = entry.value;
          } else {
            minuteFatal[entry.key] = entry.value;
          }
        }
        allowedErrors['minute'] = minuteAllowed;
        fatalErrors['minute'] = minuteFatal;

        final minuteValidateStopwatch = Stopwatch()..start();
        final today = anchorDay;
        var tradingDates = minuteTradingDates.toList()..sort();
        tradingDates = tradingDates.where((date) => date != today).toList();
        if (tradingDates.isEmpty) {
          tradingDates = _weekdayDates(
            _dateOnly(activeMinuteRange.start),
            _dateOnly(activeMinuteRange.end),
          ).where((date) => date != today).toList();
        }

        final workerCount = min(_minuteReadConcurrency, stockCodes.length);
        var nextIndex = 0;

        Future<void> runWorker() async {
          while (true) {
            final index = nextIndex;
            if (index >= stockCodes.length) {
              return;
            }
            nextIndex++;

            final stockCode = stockCodes[index];
            final klinesByStock = await activeRepo.getKlines(
              stockCodes: [stockCode],
              dateRange: activeMinuteRange,
              dataType: KLineDataType.oneMinute,
            );
            final bars = klinesByStock[stockCode] ?? const <KLine>[];

            final countsByDate = <DateTime, int>{};
            for (final bar in bars) {
              final day = _dateOnly(bar.datetime);
              countsByDate[day] = (countsByDate[day] ?? 0) + 1;
            }

            var missing = 0;
            var incomplete = 0;
            for (final date in tradingDates) {
              final count = countsByDate[date] ?? 0;
              if (count == 0) {
                missing++;
              } else if (count < _minuteMinCompleteBars) {
                incomplete++;
              }
            }

            if (missing > 0) {
              minuteMissingDays[stockCode] = missing;
            }
            if (incomplete > 0) {
              minuteIncompleteDays[stockCode] = incomplete;
            }
          }
        }

        await Future.wait(
          List.generate(workerCount, (_) => runWorker(), growable: false),
        );
        minuteValidateStopwatch.stop();
        stageDurations['minute_validate'] = minuteValidateStopwatch.elapsed;

        final failures = <String>[];
        if (dailyFatal.isNotEmpty) {
          failures.add('daily fetch fatal=${dailyFatal.length}');
        }
        if (weeklyFatal.isNotEmpty) {
          failures.add('weekly fetch fatal=${weeklyFatal.length}');
        }
        if (minuteFatal.isNotEmpty) {
          failures.add('minute fetch fatal=${minuteFatal.length}');
        }
        if (dailyShort.isNotEmpty) {
          failures.add('daily bars short=${dailyShort.length}');
        }
        if (weeklyShort.isNotEmpty) {
          failures.add('weekly bars short=${weeklyShort.length}');
        }
        if (minuteMissingDays.isNotEmpty || minuteIncompleteDays.isNotEmpty) {
          failures.add(
            'minute missing=${minuteMissingDays.length} incomplete=${minuteIncompleteDays.length}',
          );
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
          p.join(reportDir.path, '${dateKey}-data-layer-real-e2e.md'),
        );

        final buffer = StringBuffer();
        buffer.writeln('# Data Layer Real E2E Report');
        buffer.writeln('');
        buffer.writeln('- Date: $dateKey');
        buffer.writeln('- Started: $startedAt');
        buffer.writeln('- Ended: $endedAt');
        buffer.writeln(
          '- Duration: ${_formatDuration(endedAt.difference(startedAt))}',
        );
        buffer.writeln('');
        buffer.writeln('## Config');
        buffer.writeln('- poolSize: $_poolSize');
        buffer.writeln('- minutePipeline: enablePoolMinutePipeline=true');
        buffer.writeln('- poolBatchCount: 800');
        buffer.writeln('- poolMaxBatches: 10');
        buffer.writeln('- minuteWriteConcurrency: 6');
        buffer.writeln('');
        buffer.writeln('## Validation Rules');
        buffer.writeln('- daily target bars: $_dailyTargetBars');
        buffer.writeln('- weekly target bars: $_weeklyTargetBars');
        buffer.writeln('- weekly range days: $_weeklyRangeDays');
        buffer.writeln('- minute range days: $_minuteRangeDays');
        buffer.writeln('- minute min complete bars/day: $_minuteMinCompleteBars');
        buffer.writeln('- minute today excluded: true');
        buffer.writeln('');
        buffer.writeln('## Stages');

        void writeStage(String name) {
          final total = stageTotals[name] ?? 0;
          final success = stageSuccess[name] ?? 0;
          final records = stageRecords[name] ?? 0;
          final allowed = allowedErrors[name] ?? const {};
          final fatal = fatalErrors[name] ?? const {};
          buffer.writeln('### ${name[0].toUpperCase()}${name.substring(1)}');
          buffer.writeln('- totalStocks: $total');
          buffer.writeln('- successCount: $success');
          buffer.writeln('- totalRecords: $records');
          buffer.writeln(
            '- fetchDuration: ${_formatDuration(stageDurations['${name}_fetch'] ?? Duration.zero)}',
          );
          buffer.writeln(
            '- validateDuration: ${_formatDuration(stageDurations['${name}_validate'] ?? Duration.zero)}',
          );
          buffer.writeln('- allowedNoData: ${allowed.length}');
          buffer.writeln('- fatalErrors: ${fatal.length}');
          if (allowed.isNotEmpty) {
            buffer.writeln(
              '- allowed sample: ${_formatTopCounts(allowed.map((k, v) => MapEntry(k, 1)))}',
            );
          }
          if (fatal.isNotEmpty) {
            buffer.writeln(
              '- fatal sample: ${_formatTopCounts(fatal.map((k, v) => MapEntry(k, 1)))}',
            );
          }
          buffer.writeln('');
        }

        writeStage('daily');
        writeStage('weekly');
        writeStage('minute');

        buffer.writeln('## Validation Results');
        buffer.writeln(
          '- daily short: ${dailyShort.length} (sample: ${_formatTopCounts(dailyShort)})',
        );
        buffer.writeln(
          '- weekly short: ${weeklyShort.length} (sample: ${_formatTopCounts(weeklyShort)})',
        );
        buffer.writeln(
          '- minute missing: ${minuteMissingDays.length} (sample: ${_formatTopCounts(minuteMissingDays)})',
        );
        buffer.writeln(
          '- minute incomplete: ${minuteIncompleteDays.length} (sample: ${_formatTopCounts(minuteIncompleteDays)})',
        );

        if (weeklyRange != null) {
          buffer.writeln('');
          buffer.writeln(
            '- weekly range: ${_formatDate(weeklyRange!.start)} ~ ${_formatDate(weeklyRange!.end)}',
          );
        }
        if (minuteRange != null) {
          buffer.writeln(
            '- minute range: ${_formatDate(minuteRange!.start)} ~ ${_formatDate(minuteRange!.end)}',
          );
        }

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
        if (pool != null) {
          await pool.disconnect();
        }
        if (database != null) {
          try {
            await database.close();
          } catch (_) {}
          MarketDatabase.resetInstance();
        }
        if (rootDir != null && await rootDir.exists()) {
          await rootDir.delete(recursive: true);
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
