// test/services/industry_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

void main() {
  group('IndustryService', () {
    test('getIndustry returns correct industry for known code', () {
      final service = IndustryService();
      // 手动设置测试数据
      service.setTestData({'000001': '银行', '600519': '食品饮料'});

      expect(service.getIndustry('000001'), equals('银行'));
      expect(service.getIndustry('600519'), equals('食品饮料'));
    });

    test('getIndustry returns null for unknown code', () {
      final service = IndustryService();
      service.setTestData({'000001': '银行'});

      expect(service.getIndustry('999999'), isNull);
    });

    test('allIndustries returns unique industry names', () {
      final service = IndustryService();
      service.setTestData({
        '000001': '银行',
        '000002': '房地产',
        '600519': '食品饮料',
        '601398': '银行',
      });

      final industries = service.allIndustries;

      expect(industries, isA<Set<String>>());
      expect(industries.length, 3);
      expect(industries, contains('银行'));
      expect(industries, contains('房地产'));
      expect(industries, contains('食品饮料'));
    });

    test('getStocksByIndustry returns correct stocks for known industry', () {
      final service = IndustryService();
      service.setTestData({
        '000001': '银行',
        '000002': '银行',
        '600519': '食品饮料',
        '601398': '银行',
      });

      final bankStocks = service.getStocksByIndustry('银行');
      final foodStocks = service.getStocksByIndustry('食品饮料');

      expect(bankStocks.length, 3);
      expect(bankStocks, containsAll(['000001', '000002', '601398']));
      expect(foodStocks.length, 1);
      expect(foodStocks, contains('600519'));
    });

    test('getStocksByIndustry returns empty list for unknown industry', () {
      final service = IndustryService();
      service.setTestData({'000001': '银行'});

      final result = service.getStocksByIndustry('不存在的行业');

      expect(result, isEmpty);
    });

    test('index is rebuilt when setTestData is called', () {
      final service = IndustryService();
      // First data set
      service.setTestData({'000001': '银行', '600519': '食品饮料'});
      expect(service.getStocksByIndustry('银行'), contains('000001'));
      expect(service.getStocksByIndustry('食品饮料'), contains('600519'));
      expect(service.getStocksByIndustry('银行').length, 1);

      // Replace with new data - index should be rebuilt
      service.setTestData({'000001': '银行', '600000': '银行', '600519': '食品饮料'});
      // New data should exist - now there are 2 banks
      final bankStocks = service.getStocksByIndustry('银行');
      expect(bankStocks.length, 2);
      expect(bankStocks, containsAll(['000001', '600000']));
      // Food/beverage should still work
      expect(service.getStocksByIndustry('食品饮料'), contains('600519'));
    });

    test(
      'getStocksByIndustry returns consistent results on repeated calls',
      () {
        final service = IndustryService();
        service.setTestData({
          '000001': '银行',
          '000002': '银行',
          '600519': '食品饮料',
          '601398': '银行',
        });

        // Call multiple times - should return same results
        final result1 = service.getStocksByIndustry('银行');
        final result2 = service.getStocksByIndustry('银行');
        final result3 = service.getStocksByIndustry('银行');

        expect(result1.length, 3);
        expect(result2.length, 3);
        expect(result3.length, 3);
        expect(result1, containsAll(result2));
        expect(result2, containsAll(result3));
      },
    );
  });
}
