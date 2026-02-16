import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';

enum OverrideAction {
  skip,
  acceptPartial,
  promoteFinal,
  markUnknownRetry,
}

class OverrideDecision {
  const OverrideDecision({
    required this.action,
    this.dirtyRangeStart,
    this.dirtyRangeEnd,
    this.requiresFullRecompute = false,
  });

  final OverrideAction action;
  final DateTime? dirtyRangeStart;
  final DateTime? dirtyRangeEnd;
  final bool requiresFullRecompute;
}

class FinalOverrideCoordinator {
  const FinalOverrideCoordinator({this.warmupDays = 45});

  final int warmupDays;

  OverrideDecision decide({
    required String stockCode,
    required DateTime tradeDate,
    required TradingDaySession session,
    required DailyCandleCompleteness incoming,
    required DailyCandleCompleteness? previous,
  }) {
    final normalizedTradeDate = DateTime(
      tradeDate.year,
      tradeDate.month,
      tradeDate.day,
    );

    if (incoming == DailyCandleCompleteness.unknown) {
      return const OverrideDecision(action: OverrideAction.markUnknownRetry);
    }

    if (incoming == DailyCandleCompleteness.partial) {
      return const OverrideDecision(action: OverrideAction.acceptPartial);
    }

    if (incoming == DailyCandleCompleteness.finalized &&
        previous != DailyCandleCompleteness.finalized &&
        session.isClosed) {
      return OverrideDecision(
        action: OverrideAction.promoteFinal,
        dirtyRangeStart: normalizedTradeDate.subtract(
          Duration(days: warmupDays),
        ),
        dirtyRangeEnd: normalizedTradeDate,
      );
    }

    return const OverrideDecision(action: OverrideAction.skip);
  }
}
