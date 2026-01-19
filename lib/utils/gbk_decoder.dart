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
    return gbk.decode(trimmedBytes);
  }
}
