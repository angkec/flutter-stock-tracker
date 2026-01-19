import 'dart:typed_data';

class DecodeResult {
  final int value;
  final int nextPos;

  DecodeResult(this.value, this.nextPos);
}

/// 解码 TDX 协议中的变长价格编码
/// 类似 UTF-8 的变长编码方式，用于存储有符号整数
DecodeResult decodePrice(Uint8List data, int pos) {
  int positionBit = 6;
  int byte = data[pos];
  int intData = byte & 0x3F; // 低6位是数据
  bool isNegative = (byte & 0x40) != 0; // 第6位是符号位

  // 第7位是延续位
  if ((byte & 0x80) != 0) {
    while (true) {
      pos++;
      byte = data[pos];
      intData += (byte & 0x7F) << positionBit;
      positionBit += 7;

      if ((byte & 0x80) == 0) {
        break;
      }
    }
  }

  pos++;

  if (isNegative) {
    intData = -intData;
  }

  return DecodeResult(intData, pos);
}
