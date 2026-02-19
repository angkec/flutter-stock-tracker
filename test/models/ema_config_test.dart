import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/ema_config.dart';

void main() {
  test('ema config json round-trip', () {
    const config = EmaConfig(shortPeriod: 11, longPeriod: 22);
    final json = config.toJson();
    final decoded = EmaConfig.fromJson(json);
    expect(decoded, config);
  });
}
