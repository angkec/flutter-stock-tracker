enum TradingDaySession {
  nonTrading,
  intraday,
  postClosePendingFinal,
  finalized,
}

extension TradingDaySessionX on TradingDaySession {
  bool get isClosed =>
      this == TradingDaySession.postClosePendingFinal ||
      this == TradingDaySession.finalized;
}
