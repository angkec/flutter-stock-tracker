import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/sw_industry_l1_mapping_store.dart';

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late SwIndustryL1MappingStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sw-industry-l1-mapping-store-',
    );
    storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    store = SwIndustryL1MappingStore(storage: storage);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('saveAll and loadAll persist industry mapping', () async {
    const mapping = {'半导体': '801080.SI', '银行': '801780.SI'};

    await store.saveAll(mapping);
    final loaded = await store.loadAll();

    expect(loaded, mapping);
  });

  test('loadAll returns empty map when file does not exist', () async {
    final loaded = await store.loadAll();

    expect(loaded, isEmpty);
  });

  test('saveAll overwrites previous mapping atomically', () async {
    await store.saveAll(const {'旧行业': '801000.SI'});
    await store.saveAll(const {'新行业': '801001.SI'});

    final loaded = await store.loadAll();
    expect(loaded, const {'新行业': '801001.SI'});
  });
}
