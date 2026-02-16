import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/market_calendar_provider.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session_resolver.dart';

class _FakeMarketCalendarProvider implements MarketCalendarProvider {
  _FakeMarketCalendarProvider(this.snapshot);

  final MarketDaySnapshot snapshot;

  @override
  Future<MarketDaySnapshot> getMarketDaySnapshot({
    required String stockCode,
    required DateTime tradeDate,
  }) async {
    return snapshot;
  }
}

void main() {
  test('resolves intraday when market day is open', () async {
    final provider = _FakeMarketCalendarProvider(
      const MarketDaySnapshot(isTradingDay: true, isClosed: false),
    );
    final resolver = TradingDaySessionResolver(provider: provider);
    final session = await resolver.resolve(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
    );
    expect(session, TradingDaySession.intraday);
  });

  test('resolves post-close pending-final when closed but no final snapshot', () async {
    final provider = _FakeMarketCalendarProvider(
      const MarketDaySnapshot(isTradingDay: true, isClosed: true),
    );
    final resolver = TradingDaySessionResolver(provider: provider);
    final session = await resolver.resolve(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
      hasFinalSnapshot: false,
    );
    expect(session, TradingDaySession.postClosePendingFinal);
  });

  test('resolves finalized when closed and final snapshot exists', () async {
    final provider = _FakeMarketCalendarProvider(
      const MarketDaySnapshot(isTradingDay: true, isClosed: true),
    );
    final resolver = TradingDaySessionResolver(provider: provider);
    final session = await resolver.resolve(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
      hasFinalSnapshot: true,
    );
    expect(session, TradingDaySession.finalized);
  });

  test('resolves non-trading when market day is holiday', () async {
    final provider = _FakeMarketCalendarProvider(
      const MarketDaySnapshot(isTradingDay: false, isClosed: false),
    );
    final resolver = TradingDaySessionResolver(provider: provider);
    final session = await resolver.resolve(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
    );
    expect(session, TradingDaySession.nonTrading);
  });
}
