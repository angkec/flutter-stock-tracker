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
  });
}
