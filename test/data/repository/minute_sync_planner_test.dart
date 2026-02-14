import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/minute_sync_state.dart';
import 'package:stock_rtwatcher/data/repository/minute_sync_planner.dart';

void main() {
  group('MinuteSyncPlanner', () {
    test('returns bootstrap when sync state is missing', () {
      final planner = MinuteSyncPlanner();
      final plan = planner.planForStock(
        stockCode: '000001',
        tradingDates: [DateTime(2026, 2, 10), DateTime(2026, 2, 11)],
        syncState: null,
        knownMissingDates: const [],
        knownIncompleteDates: const [],
      );

      expect(plan.mode, MinuteSyncMode.bootstrap);
      expect(plan.datesToFetch, [DateTime(2026, 2, 10), DateTime(2026, 2, 11)]);
    });

    test('returns incremental after last complete trading day', () {
      final planner = MinuteSyncPlanner();
      final plan = planner.planForStock(
        stockCode: '000001',
        tradingDates: [
          DateTime(2026, 2, 10),
          DateTime(2026, 2, 11),
          DateTime(2026, 2, 12),
        ],
        syncState: MinuteSyncState(
          stockCode: '000001',
          lastCompleteTradingDay: DateTime(2026, 2, 11),
          updatedAt: DateTime(2026, 2, 14, 9, 0),
        ),
        knownMissingDates: const [],
        knownIncompleteDates: const [],
      );

      expect(plan.mode, MinuteSyncMode.incremental);
      expect(plan.datesToFetch, [DateTime(2026, 2, 12)]);
    });

    test('backfill merges with incremental dates when both exist', () {
      final planner = MinuteSyncPlanner();
      final plan = planner.planForStock(
        stockCode: '000001',
        tradingDates: [
          DateTime(2026, 2, 10),
          DateTime(2026, 2, 11),
          DateTime(2026, 2, 12),
        ],
        syncState: MinuteSyncState(
          stockCode: '000001',
          lastCompleteTradingDay: DateTime(2026, 2, 10),
          updatedAt: DateTime(2026, 2, 14),
        ),
        knownMissingDates: [DateTime(2026, 2, 11)],
        knownIncompleteDates: const [],
      );

      expect(plan.mode, MinuteSyncMode.backfill);
      expect(plan.datesToFetch, [DateTime(2026, 2, 11), DateTime(2026, 2, 12)]);
    });

    test('returns backfill when missing dates exist', () {
      final planner = MinuteSyncPlanner();
      final plan = planner.planForStock(
        stockCode: '000001',
        tradingDates: [
          DateTime(2026, 2, 10),
          DateTime(2026, 2, 11),
          DateTime(2026, 2, 12),
        ],
        syncState: MinuteSyncState(
          stockCode: '000001',
          lastCompleteTradingDay: DateTime(2026, 2, 12),
          updatedAt: DateTime(2026, 2, 14),
        ),
        knownMissingDates: [DateTime(2026, 2, 10)],
        knownIncompleteDates: [DateTime(2026, 2, 11)],
      );

      expect(plan.mode, MinuteSyncMode.backfill);
      expect(plan.datesToFetch, [DateTime(2026, 2, 10), DateTime(2026, 2, 11)]);
    });

    test('returns skip when no trading dates exist', () {
      final planner = MinuteSyncPlanner();
      final plan = planner.planForStock(
        stockCode: '000001',
        tradingDates: const [],
        syncState: null,
        knownMissingDates: const [],
        knownIncompleteDates: const [],
      );

      expect(plan.mode, MinuteSyncMode.skip);
      expect(plan.datesToFetch, isEmpty);
    });
  });
}
