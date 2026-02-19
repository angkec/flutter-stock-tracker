import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class BinaryKLineCodec {
  static const int _recordSize = 8 + 8 + 8 + 8 + 8 + 8 + 8; // 7 x 8-byte

  Uint8List encode(List<KLine> klines) {
    final raw = _serialize(klines);
    final encoder = ZLibEncoder();
    final compressed = encoder.encode(raw);
    return Uint8List.fromList(compressed!);
  }

  List<KLine> decode(Uint8List bytes) {
    final decoder = ZLibDecoder();
    final raw = decoder.decodeBytes(bytes);
    return _deserialize(Uint8List.fromList(raw));
  }

  Uint8List _serialize(List<KLine> klines) {
    final buffer = BytesBuilder();
    for (final k in klines) {
      final data = ByteData(_recordSize);
      var offset = 0;
      data.setInt64(offset, k.datetime.millisecondsSinceEpoch);
      offset += 8;
      data.setFloat64(offset, k.open);
      offset += 8;
      data.setFloat64(offset, k.close);
      offset += 8;
      data.setFloat64(offset, k.high);
      offset += 8;
      data.setFloat64(offset, k.low);
      offset += 8;
      data.setFloat64(offset, k.volume);
      offset += 8;
      data.setFloat64(offset, k.amount);
      offset += 8;
      buffer.add(data.buffer.asUint8List());
    }
    return buffer.toBytes();
  }

  List<KLine> _deserialize(Uint8List raw) {
    if (raw.isEmpty) return <KLine>[];
    final result = <KLine>[];
    final data = ByteData.sublistView(raw);
    for (var offset = 0;
        offset + _recordSize <= data.lengthInBytes;
        offset += _recordSize) {
      var cursor = offset;
      final ts = data.getInt64(cursor);
      cursor += 8;
      final open = data.getFloat64(cursor);
      cursor += 8;
      final close = data.getFloat64(cursor);
      cursor += 8;
      final high = data.getFloat64(cursor);
      cursor += 8;
      final low = data.getFloat64(cursor);
      cursor += 8;
      final volume = data.getFloat64(cursor);
      cursor += 8;
      final amount = data.getFloat64(cursor);
      cursor += 8;
      result.add(
        KLine(
          datetime: DateTime.fromMillisecondsSinceEpoch(ts),
          open: open,
          close: close,
          high: high,
          low: low,
          volume: volume,
          amount: amount,
        ),
      );
    }
    return result;
  }
}
