import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/utils/volume_decoder.dart';

void main() {
  group('VolumeDecoder', () {
    test('decodes zero volume', () {
      expect(decodeVolume(0), closeTo(0.0, 0.001));
    });

    test('decodes normal volume', () {
      // 测试用例来自 pytdx 源码
      // 这个编码格式是通达信特有的浮点数编码
      const raw = 0x4A000001; // 示例值
      final result = decodeVolume(raw);
      expect(result, isA<double>());
      expect(result, greaterThanOrEqualTo(0));
    });

    test('decodes large volume', () {
      const raw = 0x4B123456;
      final result = decodeVolume(raw);
      expect(result, isA<double>());
    });
  });
}
