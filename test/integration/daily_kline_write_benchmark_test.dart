import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

List<KLine> _buildDailyBars(int n) {
  final start = DateTime(2025, 1, 1);
  return List.generate(n, (index) {
    final dt = start.add(Duration(days: index));
    return KLine(
      datetime: dt,
      open: 10,
      close: 10.1 + index * 0.01,
      high: 10.2 + index * 0.01,
      low: 9.9,
      volume: 1000.0 + index,
      amount: 10000.0 + index,
    );
  });
}

Map<String, List<KLine>> _buildPayload({
  required int stocks,
  required int barsPerStock,
}) {
  final bars = _buildDailyBars(barsPerStock);
  return {
    for (var index = 0; index < stocks; index++) '${600000 + index}': bars,
  };
}

Future<({int elapsedMs, double rate})> _runWriteBench(
  Directory tempDir, {
  required Map<String, List<KLine>> payload,
  required int maxConcurrentWrites,
}) async {
  final storage = KLineFileStorage()..setBaseDirPathForTesting(tempDir.path);
  final store = DailyKlineCacheStore(
    storage: storage,
    defaultMaxConcurrentWrites: maxConcurrentWrites,
  );

  final stopwatch = Stopwatch()..start();
  await store.saveAll(payload);
  stopwatch.stop();

  final elapsedMs = stopwatch.elapsedMilliseconds;
  final seconds = elapsedMs <= 0 ? 0.001 : elapsedMs / 1000;
  final rate = payload.length / seconds;
  return (elapsedMs: elapsedMs, rate: rate);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Daily KLine write benchmark', () {
    test('compares sequential vs concurrent file writes', () async {
      if (Platform.environment['RUN_DAILY_KLINE_WRITE_BENCH'] != '1') {
        return;
      }

      final stocks =
          int.tryParse(
            Platform.environment['DAILY_WRITE_BENCH_STOCKS'] ?? '',
          ) ??
          500;
      final barsPerStock =
          int.tryParse(
            Platform.environment['DAILY_WRITE_BENCH_BARS_PER_STOCK'] ?? '',
          ) ??
          260;
      final sequentialConcurrency =
          int.tryParse(
            Platform.environment['DAILY_WRITE_BENCH_SEQ_CONC'] ?? '',
          ) ??
          1;
      final concurrentConcurrency =
          int.tryParse(Platform.environment['DAILY_WRITE_BENCH_CONC'] ?? '') ??
          8;
      final payload = _buildPayload(stocks: stocks, barsPerStock: barsPerStock);

      final seqDir = await Directory.systemTemp.createTemp('daily-write-seq-');
      final conDir = await Directory.systemTemp.createTemp('daily-write-con-');
      addTearDown(() async {
        if (await seqDir.exists()) {
          await seqDir.delete(recursive: true);
        }
        if (await conDir.exists()) {
          await conDir.delete(recursive: true);
        }
      });

      final sequential = await _runWriteBench(
        seqDir,
        payload: payload,
        maxConcurrentWrites: sequentialConcurrency,
      );
      final concurrent = await _runWriteBench(
        conDir,
        payload: payload,
        maxConcurrentWrites: concurrentConcurrency,
      );

      final speedup = concurrent.rate / sequential.rate;
      debugPrint(
        '[daily_write_bench] stocks=$stocks bars=$barsPerStock '
        'seqConc=$sequentialConcurrency conConc=$concurrentConcurrency '
        'seqMs=${sequential.elapsedMs} seqRate=${sequential.rate.toStringAsFixed(2)} '
        'conMs=${concurrent.elapsedMs} conRate=${concurrent.rate.toStringAsFixed(2)} '
        'speedup=${speedup.toStringAsFixed(2)}x',
      );

      expect(sequential.elapsedMs, greaterThan(0));
      expect(concurrent.elapsedMs, greaterThan(0));
      expect(concurrent.rate, greaterThan(0));
    });
  });
}
