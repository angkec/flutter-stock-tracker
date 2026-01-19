import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

void main() {
  group('TdxClient', () {
    late TdxClient client;

    setUp(() {
      client = TdxClient();
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('connects to server successfully', () async {
      final result = await client.connect('115.238.56.198', 7709);
      expect(result, isTrue);
      expect(client.isConnected, isTrue);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('disconnects properly', () async {
      await client.connect('115.238.56.198', 7709);
      await client.disconnect();
      expect(client.isConnected, isFalse);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('gets security count', () async {
      await client.connect('115.238.56.198', 7709);
      final count = await client.getSecurityCount(0); // 深市
      expect(count, greaterThan(10000));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('gets security list', () async {
      await client.connect('115.238.56.198', 7709);
      final stocks = await client.getSecurityList(0, 0); // 深市, 从0开始
      expect(stocks.length, greaterThan(0));
      expect(stocks.first.code, isNotEmpty);
      expect(stocks.first.name, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('gets security quotes', () async {
      await client.connect('115.238.56.198', 7709);
      final quotes = await client.getSecurityQuotes([
        (0, '000001'),
        (1, '600519'),
      ]);
      expect(quotes.length, 2);
      expect(quotes[0].code, '000001');
      expect(quotes[0].price, greaterThan(0));
    }, skip: 'Server not responding to quotes - may need trading hours',
       timeout: const Timeout(Duration(seconds: 15)));

    test('gets security bars (1min kline)', () async {
      await client.connect('115.238.56.198', 7709);
      final bars = await client.getSecurityBars(
        market: 0,
        code: '000001',
        category: 8, // 1分钟K线
        start: 0,
        count: 10,
      );
      expect(bars.length, 10);
      expect(bars.first.open, greaterThan(0));
      expect(bars.first.close, greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
