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
  });
}
