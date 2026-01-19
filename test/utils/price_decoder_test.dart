import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/utils/price_decoder.dart';

void main() {
  group('PriceDecoder', () {
    test('decodes single byte positive number', () {
      // 0x05 = 5 (无符号位，无延续位)
      final data = Uint8List.fromList([0x05]);
      final result = decodePrice(data, 0);
      expect(result.value, 5);
      expect(result.nextPos, 1);
    });

    test('decodes single byte negative number', () {
      // 0x45 = -5 (符号位=1, 值=5)
      final data = Uint8List.fromList([0x45]);
      final result = decodePrice(data, 0);
      expect(result.value, -5);
      expect(result.nextPos, 1);
    });

    test('decodes multi-byte number', () {
      // 0x82 0x01 = 66 (延续位=1, 值=2, 然后 值=1<<6 + 2 = 66)
      final data = Uint8List.fromList([0x82, 0x01]);
      final result = decodePrice(data, 0);
      expect(result.value, 66);
      expect(result.nextPos, 2);
    });

    test('decodes from offset position', () {
      final data = Uint8List.fromList([0xFF, 0xFF, 0x05]);
      final result = decodePrice(data, 2);
      expect(result.value, 5);
      expect(result.nextPos, 3);
    });
  });
}
