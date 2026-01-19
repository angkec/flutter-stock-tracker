import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/utils/gbk_decoder.dart';

void main() {
  group('GbkDecoder', () {
    test('decodes pure ASCII string', () {
      // "HELLO" in ASCII
      final data = Uint8List.fromList([0x48, 0x45, 0x4C, 0x4C, 0x4F]);
      final result = GbkDecoder.decode(data);
      expect(result, 'HELLO');
    });

    test('decodes ASCII string with trailing nulls', () {
      // "ABC" followed by null bytes
      final data = Uint8List.fromList([0x41, 0x42, 0x43, 0x00, 0x00]);
      final result = GbkDecoder.decode(data);
      expect(result, 'ABC');
    });

    test('decodes Chinese characters', () {
      // GBK encoding for common financial terms
      // 0xBDF0 = 金, 0xC8DA = 融
      final data = Uint8List.fromList([0xBD, 0xF0, 0xC8, 0xDA]);
      final result = GbkDecoder.decode(data);
      expect(result, '金融');
    });

    test('decodes mixed ASCII and Chinese', () {
      // "A" + 银行 + "B"
      // A = 0x41, 银 = 0xD2F8, 行 = 0xD0D0, B = 0x42
      final data =
          Uint8List.fromList([0x41, 0xD2, 0xF8, 0xD0, 0xD0, 0x42]);
      final result = GbkDecoder.decode(data);
      expect(result, 'A银行B');
    });

    test('decodes stock exchange names', () {
      // 证券 = 0xD6A4 0xC8AF
      final data = Uint8List.fromList([0xD6, 0xA4, 0xC8, 0xAF]);
      final result = GbkDecoder.decode(data);
      expect(result, '证券');
    });

    test('decodes technology related terms', () {
      // 科技 = 0xBFC6 0xBCBC
      final data = Uint8List.fromList([0xBF, 0xC6, 0xBC, 0xBC]);
      final result = GbkDecoder.decode(data);
      expect(result, '科技');
    });

    test('decodes healthcare related terms', () {
      // 医药 = 0xD2BD 0xD2A9
      final data = Uint8List.fromList([0xD2, 0xBD, 0xD2, 0xA9]);
      final result = GbkDecoder.decode(data);
      expect(result, '医药');
    });

    test('decodes energy related terms', () {
      // 能源 = 0xC4DC 0xD4B4
      final data = Uint8List.fromList([0xC4, 0xDC, 0xD4, 0xB4]);
      final result = GbkDecoder.decode(data);
      expect(result, '能源');
    });

    test('handles empty input', () {
      final data = Uint8List.fromList([]);
      final result = GbkDecoder.decode(data);
      expect(result, '');
    });

    test('handles all null bytes', () {
      final data = Uint8List.fromList([0x00, 0x00, 0x00]);
      final result = GbkDecoder.decode(data);
      expect(result, '');
    });

    test('decodes numbers in stock names', () {
      // "123" in ASCII
      final data = Uint8List.fromList([0x31, 0x32, 0x33]);
      final result = GbkDecoder.decode(data);
      expect(result, '123');
    });

    test('replaces unknown GBK codes with replacement character', () {
      // Invalid GBK sequence that's not in our mapping
      final data = Uint8List.fromList([0x81, 0x40]);
      final result = GbkDecoder.decode(data);
      // Should contain replacement character since 0x8140 is not mapped
      expect(result, '\uFFFD');
    });

    test('decodes typical stock name with company suffix', () {
      // 股份 = 0xB9C9 0xB7DD
      final data = Uint8List.fromList([0xB9, 0xC9, 0xB7, 0xDD]);
      final result = GbkDecoder.decode(data);
      expect(result, '股份');
    });

    test('decodes geographic terms in stock names', () {
      // 中国 = 0xD6D0 0xB9FA
      final data = Uint8List.fromList([0xD6, 0xD0, 0xB9, 0xFA]);
      final result = GbkDecoder.decode(data);
      expect(result, '中国');
    });
  });
}
