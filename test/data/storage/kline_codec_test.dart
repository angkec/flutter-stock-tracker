import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_codec.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  test('BinaryKLineCodec encodes with zlib level 1', () {
    final codec = BinaryKLineCodec();
    final source = [
      KLine(
        datetime: DateTime(2026, 2, 18),
        open: 10.1,
        close: 11.2,
        high: 11.8,
        low: 9.9,
        volume: 12345,
        amount: 98765,
      ),
      KLine(
        datetime: DateTime(2026, 2, 19),
        open: 11.2,
        close: 10.8,
        high: 11.4,
        low: 10.3,
        volume: 54321,
        amount: 45678,
      ),
    ];

    final encoded = codec.encode(source);
    final raw = ZLibDecoder().decodeBytes(encoded);
    final expected = ZLibEncoder().encode(raw, level: 1);

    expect(encoded, Uint8List.fromList(expected!));
  });

  test('BinaryKLineCodec rejects truncated payloads', () {
    final codec = BinaryKLineCodec();
    final raw = Uint8List(1);
    final encoded = ZLibEncoder().encode(raw, level: 1);

    expect(
      () => codec.decode(Uint8List.fromList(encoded!)),
      throwsA(isA<FormatException>()),
    );
  });

  test('BinaryKLineCodec roundtrip preserves data', () {
    final codec = BinaryKLineCodec();
    final source = [
      KLine(
        datetime: DateTime(2026, 2, 18),
        open: 10.1,
        close: 11.2,
        high: 11.8,
        low: 9.9,
        volume: 12345,
        amount: 98765,
      ),
      KLine(
        datetime: DateTime(2026, 2, 19),
        open: 11.2,
        close: 10.8,
        high: 11.4,
        low: 10.3,
        volume: 54321,
        amount: 45678,
      ),
    ];

    final encoded = codec.encode(source);
    final decoded = codec.decode(encoded);

    expect(decoded.length, source.length);
    expect(decoded.first.datetime, source.first.datetime);
    expect(decoded.first.open, source.first.open);
    expect(decoded.first.close, source.first.close);
    expect(decoded.first.high, source.first.high);
    expect(decoded.first.low, source.first.low);
    expect(decoded.first.volume, source.first.volume);
    expect(decoded.first.amount, source.first.amount);
    expect(decoded.last.datetime, source.last.datetime);
    expect(decoded.last.open, source.last.open);
    expect(decoded.last.close, source.last.close);
    expect(decoded.last.high, source.last.high);
    expect(decoded.last.low, source.last.low);
    expect(decoded.last.volume, source.last.volume);
    expect(decoded.last.amount, source.last.amount);
  });
}
