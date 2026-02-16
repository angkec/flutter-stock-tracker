import 'package:stock_rtwatcher/data/sync/market_calendar_provider.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';

class TradingDaySessionResolver {
  const TradingDaySessionResolver({required this.provider});

  final MarketCalendarProvider provider;

  Future<TradingDaySession> resolve({
    required String stockCode,
    required DateTime tradeDate,
    bool hasFinalSnapshot = false,
  }) async {
    final snapshot = await provider.getMarketDaySnapshot(
      stockCode: stockCode,
      tradeDate: tradeDate,
    );

    if (!snapshot.isTradingDay) {
      return TradingDaySession.nonTrading;
    }
    if (!snapshot.isClosed) {
      return TradingDaySession.intraday;
    }

    return hasFinalSnapshot
        ? TradingDaySession.finalized
        : TradingDaySession.postClosePendingFinal;
  }
}
