import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_config_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late IndustryEmaBreadthConfigStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'industry-ema-breadth-config-store-',
    );
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    store = IndustryEmaBreadthConfigStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load returns default when file does not exist', () async {
    final loaded = await store.load();

    expect(loaded, IndustryEmaBreadthConfig.defaultConfig);
  });

  test('save and load config', () async {
    const config = IndustryEmaBreadthConfig(
      upperThreshold: 82,
      lowerThreshold: 28,
    );

    await store.save(config);

    final loaded = await store.load();
    expect(loaded, config);
  });

  test('corrupt config returns default', () async {
    await store.initialize();
    final path = await store.configFilePath();
    await File(path).writeAsString('not json');

    final loaded = await store.load();
    expect(loaded, IndustryEmaBreadthConfig.defaultConfig);
  });
}
