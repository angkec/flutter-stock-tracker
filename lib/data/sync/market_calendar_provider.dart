class MarketDaySnapshot {
  final bool isTradingDay;
  final bool isClosed;

  const MarketDaySnapshot({
    required this.isTradingDay,
    required this.isClosed,
  });
}

abstract class MarketCalendarProvider {
  Future<MarketDaySnapshot> getMarketDaySnapshot({
    required String stockCode,
    required DateTime tradeDate,
  });
}
