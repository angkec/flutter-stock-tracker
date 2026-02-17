import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/adx_config.dart';

void main() {
  test('defaults should be valid with expected values', () {
    expect(AdxConfig.defaults.isValid, isTrue);
    expect(AdxConfig.defaults.period, 14);
    expect(AdxConfig.defaults.threshold, 25);
  });

  test('fromJson should fall back to defaults on invalid payload', () {
    final config = AdxConfig.fromJson(const {'period': 0, 'threshold': -1});
    expect(config, AdxConfig.defaults);
  });
}
