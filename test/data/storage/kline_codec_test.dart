import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_codec.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
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
    expect(decoded.last.amount, source.last.amount);
  });
}
