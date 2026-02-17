import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/market_snapshot_store.dart';

void main() {
  test('saveJson and loadJson should persist snapshot payload', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'market-snapshot-store-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final store = MarketSnapshotStore(storage: storage);

    await store.saveJson('{"items":[1,2,3]}');
    final loaded = await store.loadJson();

    expect(loaded, '{"items":[1,2,3]}');
  });

  test('clear should remove persisted payload', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'market-snapshot-store-clear-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final store = MarketSnapshotStore(storage: storage);

    await store.saveJson('{"items":[1]}');
    await store.clear();

    expect(await store.loadJson(), isNull);
  });
}
