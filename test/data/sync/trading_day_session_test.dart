import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';

void main() {
  test('trading session should expose close state', () {
    expect(TradingDaySession.intraday.isClosed, isFalse);
    expect(TradingDaySession.postClosePendingFinal.isClosed, isTrue);
    expect(TradingDaySession.finalized.isClosed, isTrue);
  });
}
