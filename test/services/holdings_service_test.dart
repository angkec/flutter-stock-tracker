import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/services/holdings_service.dart';

void main() {
  group('HoldingsService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts with empty holdings', () {
      final service = HoldingsService();
      expect(service.holdings, isEmpty);
    });

    test('setHoldings replaces all holdings', () async {
      final service = HoldingsService();
      await service.setHoldings(['600519', '000001']);
      expect(service.holdings, ['600519', '000001']);

      await service.setHoldings(['300750']);
      expect(service.holdings, ['300750']);
    });

    test('load restores holdings from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'holdings': ['600519', '000001'],
      });
      final service = HoldingsService();
      await service.load();
      expect(service.holdings, ['600519', '000001']);
    });

    test('contains returns true for existing stock', () async {
      final service = HoldingsService();
      await service.setHoldings(['600519']);
      expect(service.contains('600519'), isTrue);
      expect(service.contains('000001'), isFalse);
    });

    test('clear removes all holdings', () async {
      final service = HoldingsService();
      await service.setHoldings(['600519', '000001']);
      await service.clear();
      expect(service.holdings, isEmpty);
    });
  });
}
