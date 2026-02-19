import 'dart:convert';
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
const int _minuteTradingDays = 7;
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

String _formatValidationSummary({
  required String label,
  required int failedCount,
  required int stageTotal,
  required List<String> order,
  int sampleLimit = 10,
}) {
  final percent =
      stageTotal <= 0 ? 0.0 : (failedCount * 100 / stageTotal.toDouble());
  final ids = order.isEmpty ? 'none' : order.take(sampleLimit).join(', ');
  return '$label: $failedCount (${percent.toStringAsFixed(1)}%) ids: $ids';
}

const double _minOkRate = 0.90;

bool _failsOkRate({
  required int failedCount,
  required int total,
  double minOkRate = _minOkRate,
}) {
  if (total <= 0) return false;
  final okRate = (total - failedCount) / total;
  return okRate < minOkRate;
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

List<DateTime> _selectRecentTradingDates(
  Iterable<DateTime> dates,
  int count, {
  required DateTime fallbackEnd,
}) {
  final normalized = dates.map(_dateOnly).toSet().toList()..sort();
  if (normalized.isNotEmpty) {
    final startIndex = max(0, normalized.length - count);
    return normalized.sublist(startIndex);
  }
  final fallbackStart = fallbackEnd.subtract(Duration(days: count + 7));
  final weekdays =
      _weekdayDates(_dateOnly(fallbackStart), _dateOnly(fallbackEnd));
  if (weekdays.length <= count) return weekdays;
  return weekdays.sublist(weekdays.length - count);
}

List<String> _deriveEligibleStocks({
  required List<String> allStocks,
  required Map<String, int> dailyShort,
  required Map<String, int> weeklyShort,
  required Map<String, String> dailyErrors,
  required Map<String, String> weeklyErrors,
}) {
  final blocked = <String>{
    ...dailyShort.keys,
    ...weeklyShort.keys,
    ...dailyErrors.keys,
    ...weeklyErrors.keys,
  };
  return allStocks.where((code) => !blocked.contains(code)).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('formatValidationSummary returns percent and first-seen ids', () {
    final order = <String>[
      '000001',
      '000002',
      '000003',
      '000004',
      '000005',
      '000006',
      '000007',
      '000008',
      '000009',
      '000010',
      '000011',
      '000012',
    ];

    final line = _formatValidationSummary(
      label: 'daily short',
      failedCount: 12,
      stageTotal: 120,
      order: order,
      sampleLimit: 10,
    );

    expect(
      line,
      'daily short: 12 (10.0%) ids: '
      '000001, 000002, 000003, 000004, 000005, '
      '000006, 000007, 000008, 000009, 000010',
    );
  });

  test('formatValidationSummary returns none when empty', () {
    final line = _formatValidationSummary(
      label: 'minute incomplete',
      failedCount: 0,
      stageTotal: 2500,
      order: const <String>[],
      sampleLimit: 10,
    );

    expect(line, 'minute incomplete: 0 (0.0%) ids: none');
  });

  test('failsOkRate flags when ok rate below 90%', () {
    expect(_failsOkRate(failedCount: 11, total: 100), isTrue);
    expect(_failsOkRate(failedCount: 10, total: 100), isFalse);
    expect(_failsOkRate(failedCount: 0, total: 0), isFalse);
  });

  test('deriveEligibleStocks excludes short or errored stocks', () {
    final all = ['000001', '000002', '000003', '000004'];
    final dailyShort = {'000002': 200};
    final weeklyShort = {'000003': 80};
    final dailyErrors = {'000004': 'empty_fetch_result'};
    final weeklyErrors = <String, String>{};

    final eligible = _deriveEligibleStocks(
      allStocks: all,
      dailyShort: dailyShort,
      weeklyShort: weeklyShort,
      dailyErrors: dailyErrors,
      weeklyErrors: weeklyErrors,
    );

    expect(eligible, ['000001']);
  });

  test('selectRecentTradingDates returns last N sorted dates', () {
    final dates = <DateTime>[
      DateTime(2024, 1, 2),
      DateTime(2024, 1, 1),
      DateTime(2024, 1, 5),
      DateTime(2024, 1, 4),
      DateTime(2024, 1, 3),
      DateTime(2024, 1, 8),
      DateTime(2024, 1, 7),
      DateTime(2024, 1, 6),
    ];

    final picked = _selectRecentTradingDates(
      dates,
      7,
      fallbackEnd: DateTime(2024, 1, 8),
    );

    expect(picked, [
      DateTime(2024, 1, 2),
      DateTime(2024, 1, 3),
      DateTime(2024, 1, 4),
      DateTime(2024, 1, 5),
      DateTime(2024, 1, 6),
      DateTime(2024, 1, 7),
      DateTime(2024, 1, 8),
    ]);
  });

  test('selectRecentTradingDates falls back to weekdays', () {
    final picked = _selectRecentTradingDates(
      const [],
      3,
      fallbackEnd: DateTime(2024, 1, 8),
    );

    expect(picked, [
      DateTime(2024, 1, 4),
      DateTime(2024, 1, 5),
      DateTime(2024, 1, 8),
    ]);
  });

  test(
    'data layer real e2e (full stock, real network)',
    () async {
      SharedPreferences.setMockInitialValues({});

      final startedAt = DateTime.now();
      final dateKey = _formatDate(startedAt);

      final anchorDay = _dateOnly(startedAt);
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
      final now = DateTime.now();

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

      final dailyShortOrder = <String>[];
      final weeklyShortOrder = <String>[];
      final minuteMissingOrder = <String>[];
      final minuteIncompleteOrder = <String>[];

      final minuteTradingDates = <DateTime>{};
      List<DateTime> minuteTradingDatesRecent = const [];

      Object? caughtError;
      StackTrace? caughtStack;
      String? failureSummary;

      List<String> stockCodes = const [];
      List<String> eligibleStocks = const [];

      Directory? rootDir;
      Directory? fileRoot;
      Directory? dbRoot;
      MarketDatabase? database;
      MarketDataRepository? repository;
      TdxPool? pool;

      DateRange? weeklyRange;
      DateRange? minuteRange;

      weeklyRange = DateRange(
        now.subtract(const Duration(days: _weeklyRangeDays)),
        DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 999),
      );

      try {
        final cacheRoot = Directory(
          p.join(Directory.current.path, 'build', 'real_e2e_cache', dateKey),
        );
        if (await cacheRoot.exists()) {
          await cacheRoot.delete(recursive: true);
        }
        await cacheRoot.create(recursive: true);
        rootDir = cacheRoot;
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
        stockCodes = stocks.map((stock) => stock.code).toList(growable: false);

        stageTotals['daily'] = stockCodes.length;
        stageTotals['weekly'] = stockCodes.length;
        stageTotals['minute'] = stockCodes.length;

        // Stage 1: Daily sync (force full)
        print('[E2E] Stage daily start');
        final dailyStageStopwatch = Stopwatch()..start();
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

        for (final stockCode in stockCodes) {
          final loaded = await dailyCacheStore.loadForStocksWithStatus(
            [stockCode],
            anchorDate: anchorDate,
            targetBars: _dailyTargetBars,
          );
          final bars = loaded[stockCode]?.bars ?? const <KLine>[];
          dailyTotalRecords += bars.length;

          if (bars.length < _dailyTargetBars) {
            if (!dailyShort.containsKey(stockCode)) {
              dailyShort[stockCode] = bars.length;
              dailyShortOrder.add(stockCode);
            }
          }

          for (final bar in bars) {
            final day = _dateOnly(bar.datetime);
            if (!day.isAfter(anchorDay)) {
              minuteTradingDates.add(day);
            }
          }
        }

        dailyValidateStopwatch.stop();
        stageDurations['daily_validate'] = dailyValidateStopwatch.elapsed;
        stageRecords['daily'] = dailyTotalRecords;
        dailyStageStopwatch.stop();
        minuteTradingDatesRecent = _selectRecentTradingDates(
          minuteTradingDates,
          _minuteTradingDays,
          fallbackEnd: anchorDay,
        );
        print(
          '[E2E] Stage daily done, duration=${_formatDuration(dailyStageStopwatch.elapsed)}',
        );

        // Stage 2: Weekly refetch
        print('[E2E] Stage weekly start');
        final weeklyStageStopwatch = Stopwatch()..start();
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
            if (!weeklyShort.containsKey(stockCode)) {
              weeklyShort[stockCode] = bars.length;
              weeklyShortOrder.add(stockCode);
            }
          }
        }
        weeklyValidateStopwatch.stop();
        stageDurations['weekly_validate'] = weeklyValidateStopwatch.elapsed;
        weeklyStageStopwatch.stop();
        print(
          '[E2E] Stage weekly done, duration=${_formatDuration(weeklyStageStopwatch.elapsed)}',
        );

        // Stage 3: Minute refetch
        print('[E2E] Stage minute start');
        final minuteStageStopwatch = Stopwatch()..start();
        final minuteRangeStart = minuteTradingDatesRecent.first;
        minuteRange = DateRange(
          minuteRangeStart,
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
        final tradingDates =
            minuteTradingDatesRecent.where((date) => date != today).toList();

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
              if (!minuteMissingDays.containsKey(stockCode)) {
                minuteMissingDays[stockCode] = missing;
                minuteMissingOrder.add(stockCode);
              }
            }
            if (incomplete > 0) {
              if (!minuteIncompleteDays.containsKey(stockCode)) {
                minuteIncompleteDays[stockCode] = incomplete;
                minuteIncompleteOrder.add(stockCode);
              }
            }
          }
        }

        await Future.wait(
          List.generate(workerCount, (_) => runWorker(), growable: false),
        );
        minuteValidateStopwatch.stop();
        stageDurations['minute_validate'] = minuteValidateStopwatch.elapsed;
        minuteStageStopwatch.stop();
        print(
          '[E2E] Stage minute done, duration=${_formatDuration(minuteStageStopwatch.elapsed)}',
        );

        eligibleStocks = _deriveEligibleStocks(
          allStocks: stockCodes,
          dailyShort: dailyShort,
          weeklyShort: weeklyShort,
          dailyErrors: {
            ...?allowedErrors['daily'],
            ...?fatalErrors['daily'],
          },
          weeklyErrors: {
            ...?allowedErrors['weekly'],
            ...?fatalErrors['weekly'],
          },
        );

        final dailyTotal = stageTotals['daily'] ?? 0;
        final weeklyTotal = stageTotals['weekly'] ?? 0;
        final minuteTotal = stageTotals['minute'] ?? 0;

        final dailyFatalCount = fatalErrors['daily']?.length ?? 0;
        final weeklyFatalCount = fatalErrors['weekly']?.length ?? 0;
        final minuteFatalCount = fatalErrors['minute']?.length ?? 0;

        final failures = <String>[];
        if (_failsOkRate(failedCount: dailyShort.length, total: dailyTotal)) {
          failures.add('daily short < 90% ok');
        }
        if (_failsOkRate(failedCount: weeklyShort.length, total: weeklyTotal)) {
          failures.add('weekly short < 90% ok');
        }
        if (_failsOkRate(
          failedCount: minuteMissingDays.length,
          total: minuteTotal,
        )) {
          failures.add('minute missing < 90% ok');
        }
        if (_failsOkRate(
          failedCount: minuteIncompleteDays.length,
          total: minuteTotal,
        )) {
          failures.add('minute incomplete < 90% ok');
        }
        if (_failsOkRate(failedCount: dailyFatalCount, total: dailyTotal)) {
          failures.add('daily fetch fatal < 90% ok');
        }
        if (_failsOkRate(failedCount: weeklyFatalCount, total: weeklyTotal)) {
          failures.add('weekly fetch fatal < 90% ok');
        }
        if (_failsOkRate(failedCount: minuteFatalCount, total: minuteTotal)) {
          failures.add('minute fetch fatal < 90% ok');
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
        final manifestFile = File(
          p.join(reportDir.path, '${dateKey}-data-layer-real-e2e.json'),
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
        buffer.writeln('- minute trading days: $_minuteTradingDays');
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

        final dailyTotal = stageTotals['daily'] ?? 0;
        final weeklyTotal = stageTotals['weekly'] ?? 0;
        final minuteTotal = stageTotals['minute'] ?? 0;

        buffer.writeln('## Validation Results');
        buffer.writeln(
          _formatValidationSummary(
            label: 'daily short',
            failedCount: dailyShort.length,
            stageTotal: dailyTotal,
            order: dailyShortOrder,
          ),
        );
        buffer.writeln(
          _formatValidationSummary(
            label: 'weekly short',
            failedCount: weeklyShort.length,
            stageTotal: weeklyTotal,
            order: weeklyShortOrder,
          ),
        );
        buffer.writeln(
          _formatValidationSummary(
            label: 'minute missing',
            failedCount: minuteMissingDays.length,
            stageTotal: minuteTotal,
            order: minuteMissingOrder,
          ),
        );
        buffer.writeln(
          _formatValidationSummary(
            label: 'minute incomplete',
            failedCount: minuteIncompleteDays.length,
            stageTotal: minuteTotal,
            order: minuteIncompleteOrder,
          ),
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

        final manifest = {
          'date': dateKey,
          'generatedAt': endedAt.toIso8601String(),
          'result': failureSummary == null ? 'PASS' : 'FAIL',
          'failureSummary': failureSummary,
          'cacheRoot': rootDir?.path ?? '',
          'fileRoot': fileRoot?.path ?? '',
          'dbRoot': dbRoot?.path ?? '',
          'daily': {
            'anchorDate': _formatDate(anchorDay),
            'targetBars': _dailyTargetBars,
          },
          'weekly': {
            'rangeDays': _weeklyRangeDays,
            'rangeStart': _formatDate(weeklyRange!.start),
            'rangeEnd': _formatDate(weeklyRange!.end),
            'targetBars': _weeklyTargetBars,
          },
          'eligibleStocks': eligibleStocks,
        };
        await manifestFile.writeAsString(jsonEncode(manifest), flush: true);

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
