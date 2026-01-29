import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/services/ocr_service.dart';

void main() {
  group('OcrService.extractStockCodes', () {
    test('extracts valid 6-digit stock codes', () {
      final text = '''
        贵州茅台 600519
        平安银行 000001
        宁德时代 300750
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, containsAll(['600519', '000001', '300750']));
    });

    test('filters out invalid prefixes', () {
      final text = '''
        600519 valid
        123456 invalid prefix
        999999 invalid prefix
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, ['600519']);
    });

    test('ignores non-6-digit numbers', () {
      final text = '''
        600519
        12345
        1234567
        2024
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, ['600519']);
    });

    test('removes duplicates', () {
      final text = '''
        600519 贵州茅台
        600519 again
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes, ['600519']);
    });

    test('handles empty text', () {
      final codes = OcrService.extractStockCodes('');
      expect(codes, isEmpty);
    });

    test('extracts all valid market prefixes', () {
      final text = '''
        000001 深圳主板
        001979 深圳主板
        002415 深圳中小板
        300750 创业板
        301269 创业板
        600519 上海主板
        601318 上海主板
        603288 上海主板
        605117 上海主板
        688981 科创板
      ''';
      final codes = OcrService.extractStockCodes(text);
      expect(codes.length, 10);
    });
  });
}
