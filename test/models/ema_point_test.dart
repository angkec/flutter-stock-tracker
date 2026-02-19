import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/ema_point.dart';

void main() {
  test('ema point json round-trip', () {
    final point = EmaPoint(
      datetime: DateTime(2026, 2, 19),
      emaShort: 10.5,
      emaLong: 11.0,
    );
    final json = point.toJson();
    final decoded = EmaPoint.fromJson(json);
    expect(decoded, point);
  });
}
