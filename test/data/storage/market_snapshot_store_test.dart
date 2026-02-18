import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/market_snapshot_store.dart';

class _RenameFailure implements Exception {
  const _RenameFailure();
}

class _RenameFailingAtomicFileWriter extends AtomicFileWriter {
  const _RenameFailingAtomicFileWriter();

  @override
  Future<void> writeAtomic({
    required File targetFile,
    required List<int> content,
    AtomicWritePreRenameHook? onBeforeRenameForTest,
    AtomicRenameHook? renameForTest,
    AtomicTempTokenHook? tempTokenForTest,
  }) {
    return super.writeAtomic(
      targetFile: targetFile,
      content: content,
      onBeforeRenameForTest: onBeforeRenameForTest,
      tempTokenForTest: tempTokenForTest,
      renameForTest: (_, __) async {
        throw const _RenameFailure();
      },
    );
  }
}

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

  test(
    'saveJson preserves existing file when atomic writer rename fails',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'market-snapshot-store-failure-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final storage = KLineFileStorage();
      storage.setBaseDirPathForTesting(tempDir.path);

      final file = File(
        '${tempDir.path}/market_snapshot/minute_market_snapshot_v1.json',
      );
      await file.parent.create(recursive: true);
      const originalContent = '{"items":["legacy"]}';
      await file.writeAsString(originalContent, flush: true);

      final store = MarketSnapshotStore(
        storage: storage,
        atomicWriter: const _RenameFailingAtomicFileWriter(),
      );

      await expectLater(
        store.saveJson('{"items":[1,2,3]}'),
        throwsA(isA<_RenameFailure>()),
      );
      expect(await file.readAsString(), originalContent);
    },
  );
}
