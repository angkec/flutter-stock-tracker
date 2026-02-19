import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

void main() {
  final runRealFetch = Platform.environment['RUN_REAL_TDX_TEST'] == '1';

  test(
    'fetchBars pulls index bars with valid dates',
    () async {
      final pool = TdxPool(poolSize: 2);
      final adapter = TdxPoolFetchAdapter(pool: pool);
      addTearDown(() async {
        await pool.disconnect();
      });

      const indexCodes = <String>['999999', '399001', '899050'];
      final barsByCode = await adapter.fetchBars(
        stockCodes: indexCodes,
        category: klineTypeDaily,
        start: 0,
        count: 10,
      );

      for (final code in indexCodes) {
        final bars = barsByCode[code] ?? const [];
        expect(bars, isNotEmpty, reason: 'No daily bars for $code');
        final hasValidDate = bars.any((bar) => bar.datetime.year > 2000);
        expect(
          hasValidDate,
          isTrue,
          reason: 'No valid daily bar date for $code',
        );
      }

      final weeklyBarsByCode = await adapter.fetchBars(
        stockCodes: indexCodes,
        category: klineTypeWeekly,
        start: 0,
        count: 10,
      );

      for (final code in indexCodes) {
        final bars = weeklyBarsByCode[code] ?? const [];
        expect(bars, isNotEmpty, reason: 'No weekly bars for $code');
        final hasValidDate = bars.any((bar) => bar.datetime.year > 2000);
        expect(
          hasValidDate,
          isTrue,
          reason: 'No valid weekly bar date for $code',
        );
      }
    },
    skip: runRealFetch ? false : 'Set RUN_REAL_TDX_TEST=1 to run real TDX test',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
