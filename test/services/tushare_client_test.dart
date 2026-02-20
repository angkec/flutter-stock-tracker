import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/sw_industry_l1_member.dart';
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

    test('fetchSwIndustryMembers sends index_member_all request', () async {
      late Map<String, dynamic> captured;
      final client = TushareClient(
        token: 'token_123',
        postJson: (payload) async {
          captured = payload;
          return {
            'code': 0,
            'msg': '',
            'data': {
              'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
              'items': [
                ['801010.SI', '农林牧渔', '000001.SZ', '平安银行', 'Y'],
              ],
            },
          };
        },
      );

      await client.fetchSwIndustryMembers();

      expect(captured['api_name'], 'index_member_all');
      expect((captured['params'] as Map<String, dynamic>)['is_new'], 'Y');
    });

    test('fetchSwIndustryMembers omits is_new when null is passed', () async {
      late Map<String, dynamic> captured;
      final client = TushareClient(
        token: 'token_123',
        postJson: (payload) async {
          captured = payload;
          return {
            'code': 0,
            'msg': '',
            'data': {
              'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
              'items': <List<dynamic>>[],
            },
          };
        },
      );

      await client.fetchSwIndustryMembers(isNew: null);

      expect(captured['api_name'], 'index_member_all');
      final params = captured['params'] as Map<String, dynamic>;
      expect(params.containsKey('is_new'), isFalse);
    });

    test('parseSwIndustryMembersResponse maps fields+items to rows', () {
      final client = TushareClient(token: 'token_123');
      final data = {
        'code': 0,
        'msg': '',
        'data': {
          'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
          'items': [
            ['801010.SI', '农林牧渔', '000001.SZ', '平安银行', 'Y'],
          ],
        },
      };

      final rows = client.parseSwIndustryMembersResponse(data);
      expect(rows, hasLength(1));
      expect(rows.first, isA<SwIndustryL1Member>());
      expect(rows.first.l1Code, '801010.SI');
      expect(rows.first.l1Name, '农林牧渔');
      expect(rows.first.tsCode, '000001.SZ');
      expect(rows.first.stockName, '平安银行');
      expect(rows.first.isNew, 'Y');
    });

    test('fetchSwIndustryMembers throws when API returns code != 0', () async {
      final client = TushareClient(
        token: 'token_123',
        postJson: (_) async => {'code': -2001, 'msg': 'invalid token'},
      );

      await expectLater(
        client.fetchSwIndustryMembers(),
        throwsA(isA<TushareApiException>()),
      );
    });
  });
}
