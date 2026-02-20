import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

void main() {
  group('TushareClient', () {
    test('buildRequestEnvelope contains api_name token params fields', () {
      final client = TushareClient(token: 'token_123');
      final payload = client.buildRequestEnvelope(
        apiName: 'sw_daily',
        params: {'ts_code': '801010.SI'},
        fields: 'ts_code,trade_date,open,high,low,close,vol,amount',
      );

      expect(payload['api_name'], 'sw_daily');
      expect(payload['token'], 'token_123');
      expect(payload['params'], {'ts_code': '801010.SI'});
      expect(
        payload['fields'],
        'ts_code,trade_date,open,high,low,close,vol,amount',
      );
    });

    test('parseSwDailyResponse maps fields+items to bars', () {
      final client = TushareClient(token: 'token_123');
      final data = {
        'code': 0,
        'msg': '',
        'data': {
          'fields': [
            'ts_code',
            'trade_date',
            'open',
            'high',
            'low',
            'close',
            'vol',
            'amount',
          ],
          'items': [
            [
              '801010.SI',
              '20250102',
              100.0,
              105.0,
              99.0,
              103.0,
              1000000.0,
              10000000.0,
            ],
          ],
        },
      };

      final bars = client.parseSwDailyResponse(data);
      expect(bars, hasLength(1));
      expect(bars.first.tsCode, '801010.SI');
      expect(bars.first.close, 103.0);
    });

    test('fetchSwDaily throws when API returns code != 0', () async {
      final client = TushareClient(
        token: 'token_123',
        postJson: (_) async => {'code': -2001, 'msg': 'invalid token'},
      );

      await expectLater(
        client.fetchSwDaily(
          tsCode: '801010.SI',
          startDate: '20250101',
          endDate: '20250131',
        ),
        throwsA(isA<TushareApiException>()),
      );
    });

    test('fetchSwDaily returns parsed bars on success', () async {
      final client = TushareClient(
        token: 'token_123',
        postJson: (_) async {
          return jsonDecode('''
{
  "code": 0,
  "msg": "",
  "data": {
    "fields": ["ts_code", "trade_date", "open", "high", "low", "close", "vol", "amount"],
    "items": [["801010.SI", "20250102", 100.0, 105.0, 99.0, 103.0, 1000000.0, 10000000.0]]
  }
}
''')
              as Map<String, dynamic>;
        },
      );

      final bars = await client.fetchSwDaily(
        tsCode: '801010.SI',
        startDate: '20250101',
        endDate: '20250131',
      );

      expect(bars, hasLength(1));
      expect(bars.first.tradeDate, DateTime(2025, 1, 2));
    });
  });
}
