import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/ema_config.dart';

void main() {
  test('ema config json round-trip', () {
    const config = EmaConfig(shortPeriod: 11, longPeriod: 22);
    final json = config.toJson();
    final decoded = EmaConfig.fromJson(json);
    expect(decoded, config);
  });

  test('ema config json weekly defaults fallback', () {
    final decoded = EmaConfig.fromJson(
      {},
      defaults: EmaConfig.weeklyDefaults,
    );
    expect(decoded, EmaConfig.weeklyDefaults);
  });

  test('ema config invalid values fall back to defaults', () {
    final decoded = EmaConfig.fromJson({
      'shortPeriod': 30,
      'longPeriod': 10,
    });
    expect(decoded, EmaConfig.dailyDefaults);
  });
}
