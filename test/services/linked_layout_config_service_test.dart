import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/linked_layout_config.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('load returns balanced defaults when no stored config exists', () async {
    final service = LinkedLayoutConfigService();

    await service.load();

    expect(service.config.mainMinHeight, 92);
    expect(service.config.subMinHeight, 52);
    expect(service.config.containerMinHeight, 640);
  });

  test('update persists values and load restores them', () async {
    final service = LinkedLayoutConfigService();
    await service.load();

    await service.update(
      const LinkedLayoutConfig.balanced(mainMinHeight: 100, subMinHeight: 60),
    );

    final another = LinkedLayoutConfigService();
    await another.load();

    expect(another.config.mainMinHeight, 100);
    expect(another.config.subMinHeight, 60);
  });

  test('resetToDefaults clears override and restores defaults', () async {
    final service = LinkedLayoutConfigService();
    await service.load();
    await service.update(const LinkedLayoutConfig.balanced(mainMinHeight: 101));

    await service.resetToDefaults();

    expect(service.config.mainMinHeight, 92);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LinkedLayoutConfigService.storageKey), isNull);
  });

  test('load falls back to defaults when payload is invalid json', () async {
    SharedPreferences.setMockInitialValues({
      LinkedLayoutConfigService.storageKey: '{bad json',
    });

    final service = LinkedLayoutConfigService();
    await service.load();

    expect(service.config, const LinkedLayoutConfig.balanced());
  });

  test('load normalizes invalid numeric payload', () async {
    SharedPreferences.setMockInitialValues({
      LinkedLayoutConfigService.storageKey: jsonEncode({
        'mainMinHeight': -1,
        'subMinHeight': 0,
        'topPaneWeight': -1,
      }),
    });

    final service = LinkedLayoutConfigService();
    await service.load();

    expect(service.config.mainMinHeight, 92);
    expect(service.config.subMinHeight, 52);
    expect(service.config.topPaneWeight, 42);
  });
}
