import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/sw_daily_bar.dart';

void main() {
  group('SwDailyBar', () {
    test('parses tushare row with date string and maps to KLine', () {
      final bar = SwDailyBar.fromTushareMap({
        'ts_code': '801010.SI',
        'trade_date': '20250102',
        'open': 100.0,
        'high': 105.0,
        'low': 99.0,
        'close': 103.0,
        'vol': 1000000.0,
        'amount': 10000000.0,
      });

      expect(bar.tsCode, '801010.SI');
      expect(bar.tradeDate, DateTime(2025, 1, 2));

      final kline = bar.toKLine();
      expect(kline.datetime, DateTime(2025, 1, 2));
      expect(kline.open, 100.0);
      expect(kline.high, 105.0);
      expect(kline.low, 99.0);
      expect(kline.close, 103.0);
      expect(kline.volume, 1000000.0);
      expect(kline.amount, 10000000.0);
    });

    test('uses fallback zeros when numeric fields are absent', () {
      final bar = SwDailyBar.fromTushareMap({
        'ts_code': '801010.SI',
        'trade_date': '20250102',
      });

      expect(bar.open, 0.0);
      expect(bar.high, 0.0);
      expect(bar.low, 0.0);
      expect(bar.close, 0.0);
      expect(bar.volume, 0.0);
      expect(bar.amount, 0.0);
    });
  });
}
