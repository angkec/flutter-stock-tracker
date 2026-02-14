import 'package:stock_rtwatcher/data/models/minute_sync_state.dart';

enum MinuteSyncMode { skip, bootstrap, incremental, backfill }

class MinuteFetchPlan {
  final String stockCode;
  final MinuteSyncMode mode;
  final List<DateTime> datesToFetch;

  const MinuteFetchPlan({
    required this.stockCode,
    required this.mode,
    required this.datesToFetch,
  });
}

class MinuteSyncPlanner {
  MinuteFetchPlan planForStock({
    required String stockCode,
    required List<DateTime> tradingDates,
    required MinuteSyncState? syncState,
    required List<DateTime> knownMissingDates,
    required List<DateTime> knownIncompleteDates,
  }) {
    final normalizedTradingDates = _normalizeDates(tradingDates);
    if (normalizedTradingDates.isEmpty) {
      return MinuteFetchPlan(
        stockCode: stockCode,
        mode: MinuteSyncMode.skip,
        datesToFetch: const [],
      );
    }

    final basePlan = _basePlan(
      stockCode: stockCode,
      normalizedTradingDates: normalizedTradingDates,
      syncState: syncState,
    );

    final backfillDates = _normalizeDates([
      ...knownMissingDates,
      ...knownIncompleteDates,
    ]);

    if (backfillDates.isNotEmpty) {
      final mergedDates = _normalizeDates([
        ...basePlan.datesToFetch,
        ...backfillDates,
      ]);

      return MinuteFetchPlan(
        stockCode: stockCode,
        mode: MinuteSyncMode.backfill,
        datesToFetch: mergedDates,
      );
    }

    return basePlan;
  }

  MinuteFetchPlan _basePlan({
    required String stockCode,
    required List<DateTime> normalizedTradingDates,
    required MinuteSyncState? syncState,
  }) {
    final lastCompleteTradingDay = syncState?.lastCompleteTradingDay;
    if (lastCompleteTradingDay == null) {
      return MinuteFetchPlan(
        stockCode: stockCode,
        mode: MinuteSyncMode.bootstrap,
        datesToFetch: normalizedTradingDates,
      );
    }

    final normalizedLastDay = DateTime(
      lastCompleteTradingDay.year,
      lastCompleteTradingDay.month,
      lastCompleteTradingDay.day,
    );

    final incrementalDates = normalizedTradingDates
        .where((day) => day.isAfter(normalizedLastDay))
        .toList();

    if (incrementalDates.isEmpty) {
      return MinuteFetchPlan(
        stockCode: stockCode,
        mode: MinuteSyncMode.skip,
        datesToFetch: const [],
      );
    }

    return MinuteFetchPlan(
      stockCode: stockCode,
      mode: MinuteSyncMode.incremental,
      datesToFetch: incrementalDates,
    );
  }

  List<DateTime> _normalizeDates(List<DateTime> dates) {
    final normalized =
        dates
            .map((day) => DateTime(day.year, day.month, day.day))
            .toSet()
            .toList()
          ..sort();
    return normalized;
  }
}
