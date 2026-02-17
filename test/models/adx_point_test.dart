import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';

void main() {
  test('toJson/fromJson should roundtrip', () {
    final point = AdxPoint(
      datetime: DateTime(2026, 2, 17),
      adx: 21.5,
      plusDi: 26.0,
      minusDi: 14.0,
    );

    final decoded = AdxPoint.fromJson(point.toJson());
    expect(decoded.datetime, point.datetime);
    expect(decoded.adx, point.adx);
    expect(decoded.plusDi, point.plusDi);
    expect(decoded.minusDi, point.minusDi);
  });
}
