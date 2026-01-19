import 'dart:typed_data';
import 'package:fast_gbk/fast_gbk.dart';

/// GBK to Unicode decoder for Chinese stock names
class GbkDecoder {
  /// Decode GBK-encoded bytes to a Unicode string
  static String decode(Uint8List bytes) {
    // Remove trailing null bytes
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end--;
    }

    if (end == 0) return '';

    final trimmedBytes = bytes.sublist(0, end);

    try {
      return gbk.decode(trimmedBytes);
    } catch (e) {
      // If fast_gbk fails, try fallback decoding
      return _fallbackDecode(trimmedBytes);
    }
  }

  /// Fallback decoder for invalid/incomplete GBK sequences
  static String _fallbackDecode(Uint8List bytes) {
    final result = StringBuffer();
    var i = 0;

    while (i < bytes.length) {
      final byte1 = bytes[i];

      // Check if this is a GBK double-byte character
      if (byte1 >= 0x81 && byte1 <= 0xFE && i + 1 < bytes.length) {
        final byte2 = bytes[i + 1];

        if ((byte2 >= 0x40 && byte2 <= 0x7E) ||
            (byte2 >= 0x80 && byte2 <= 0xFE)) {
          // Try to decode this 2-byte sequence
          try {
            final decoded = gbk.decode(bytes.sublist(i, i + 2));
            result.write(decoded);
            i += 2;
            continue;
          } catch (_) {
            // Skip invalid sequence
            i += 2;
            continue;
          }
        }
      }

      // Single byte ASCII character
      if (byte1 < 0x80) {
        result.writeCharCode(byte1);
      }
      // Skip invalid bytes
      i++;
    }

    return result.toString();
  }
}
