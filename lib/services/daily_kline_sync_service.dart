import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';

typedef DailyKlineFetcher =
    Future<Map<String, List<KLine>>> Function({
      required List<Stock> stocks,
      required int count,
      required DailyKlineSyncMode mode,
      void Function(int current, int total)? onProgress,
    });

class DailyKlineSyncResult {
  const DailyKlineSyncResult({
    required this.successStockCodes,
    required this.failureStockCodes,
    required this.failureReasons,
  });

  final List<String> successStockCodes;
  final List<String> failureStockCodes;
  final Map<String, String> failureReasons;
}

class DailyKlineSyncService {
  DailyKlineSyncService({
    required DailyKlineCheckpointStore checkpointStore,
    required DailyKlineCacheStore cacheStore,
    required DailyKlineFetcher fetcher,
    DateTime Function()? nowProvider,
  }) : _checkpointStore = checkpointStore,
       _cacheStore = cacheStore,
       _fetcher = fetcher,
       _nowProvider = nowProvider ?? DateTime.now;

  final DailyKlineCheckpointStore _checkpointStore;
  final DailyKlineCacheStore _cacheStore;
  final DailyKlineFetcher _fetcher;
  final DateTime Function() _nowProvider;

  Future<DailyKlineSyncResult> sync({
    required DailyKlineSyncMode mode,
    required List<Stock> stocks,
    required int targetBars,
    void Function(String stage, int current, int total)? onProgress,
  }) async {
    final now = _nowProvider();
    final targets = await _resolveTargets(mode: mode, stocks: stocks, now: now);
    final safeTotal = targets.isEmpty ? 1 : targets.length;

    if (targets.isNotEmpty) {
      onProgress?.call('1/4 拉取日K数据...', 0, safeTotal);
    }

    final barsByStock = targets.isEmpty
        ? const <String, List<KLine>>{}
        : await _fetcher(
            stocks: targets,
            count: targetBars,
            mode: mode,
            onProgress: (current, total) {
              final boundedTotal = total <= 0 ? safeTotal : total;
              final boundedCurrent = current.clamp(0, boundedTotal);
              onProgress?.call('1/4 拉取日K数据...', boundedCurrent, boundedTotal);
            },
          );

    final successCodes = <String>[];
    final failureCodes = <String>[];
    final failureReasons = <String, String>{};
    final persistPayload = <String, List<KLine>>{};

    for (final stock in targets) {
      final bars = barsByStock[stock.code] ?? const <KLine>[];
      if (bars.isEmpty) {
        failureCodes.add(stock.code);
        failureReasons[stock.code] = 'empty_fetch_result';
        continue;
      }
      successCodes.add(stock.code);
      persistPayload[stock.code] = bars;
    }

    if (persistPayload.isNotEmpty) {
      onProgress?.call('2/4 写入日K文件...', 0, successCodes.length);
      await _cacheStore.saveAll(
        persistPayload,
        onProgress: (current, total) {
          final boundedTotal = total <= 0 ? successCodes.length : total;
          final boundedCurrent = current.clamp(0, boundedTotal);
          onProgress?.call('2/4 写入日K文件...', boundedCurrent, boundedTotal);
        },
      );
    }

    final nowMs = now.millisecondsSinceEpoch;
    final perStock = Map<String, int>.from(
      await _checkpointStore.loadPerStockSuccessAtMs(),
    );
    for (final code in successCodes) {
      perStock[code] = nowMs;
    }
    await _checkpointStore.savePerStockSuccessAtMs(perStock);

    final dateKey =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await _checkpointStore.saveGlobal(
      dateKey: dateKey,
      mode: mode,
      successAtMs: nowMs,
    );

    onProgress?.call('4/4 保存缓存检查点...', 1, 1);

    return DailyKlineSyncResult(
      successStockCodes: successCodes,
      failureStockCodes: failureCodes,
      failureReasons: failureReasons,
    );
  }

  Future<List<Stock>> _resolveTargets({
    required DailyKlineSyncMode mode,
    required List<Stock> stocks,
    required DateTime now,
  }) async {
    if (mode == DailyKlineSyncMode.forceFull) {
      return List<Stock>.from(stocks, growable: false);
    }

    final checkpoints = await _checkpointStore.loadPerStockSuccessAtMs();
    final nowDay = DateTime(now.year, now.month, now.day);

    final targets = <Stock>[];
    for (final stock in stocks) {
      final successMs = checkpoints[stock.code];
      if (successMs == null) {
        targets.add(stock);
        continue;
      }

      final successDate = DateTime.fromMillisecondsSinceEpoch(successMs);
      final successDay = DateTime(
        successDate.year,
        successDate.month,
        successDate.day,
      );
      if (successDay != nowDay) {
        targets.add(stock);
      }
    }

    return targets;
  }
}
