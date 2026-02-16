import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';
import 'package:stock_rtwatcher/data/sync/final_override_coordinator.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';

void main() {
  test('promotes partial to final and marks dirty range', () {
    const coordinator = FinalOverrideCoordinator(warmupDays: 62);
    final tradeDate = DateTime(2026, 2, 16);

    final decision = coordinator.decide(
      stockCode: '600000',
      tradeDate: tradeDate,
      session: TradingDaySession.postClosePendingFinal,
      incoming: DailyCandleCompleteness.finalized,
      previous: DailyCandleCompleteness.partial,
    );

    expect(decision.action, OverrideAction.promoteFinal);
    expect(decision.requiresFullRecompute, isFalse);
    expect(decision.dirtyRangeStart, DateTime(2025, 12, 16));
    expect(decision.dirtyRangeEnd, tradeDate);
  });

  test('accepts partial without final promotion', () {
    const coordinator = FinalOverrideCoordinator();
    final decision = coordinator.decide(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
      session: TradingDaySession.intraday,
      incoming: DailyCandleCompleteness.partial,
      previous: null,
    );

    expect(decision.action, OverrideAction.acceptPartial);
    expect(decision.dirtyRangeStart, isNull);
  });

  test('marks unknown as retry path', () {
    const coordinator = FinalOverrideCoordinator();
    final decision = coordinator.decide(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
      session: TradingDaySession.postClosePendingFinal,
      incoming: DailyCandleCompleteness.unknown,
      previous: DailyCandleCompleteness.partial,
    );

    expect(decision.action, OverrideAction.markUnknownRetry);
  });

  test('skips when already finalized and incoming is finalized', () {
    const coordinator = FinalOverrideCoordinator();
    final decision = coordinator.decide(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
      session: TradingDaySession.finalized,
      incoming: DailyCandleCompleteness.finalized,
      previous: DailyCandleCompleteness.finalized,
    );

    expect(decision.action, OverrideAction.skip);
  });
}
