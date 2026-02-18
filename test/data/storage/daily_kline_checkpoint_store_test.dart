import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

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
  test('writes and reads global checkpoint metadata', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DailyKlineCheckpointStore();

    await store.saveGlobal(
      dateKey: '2026-02-17',
      mode: DailyKlineSyncMode.incremental,
      successAtMs: 123456,
    );

    final checkpoint = await store.loadGlobal();
    expect(checkpoint?.dateKey, '2026-02-17');
    expect(checkpoint?.mode, DailyKlineSyncMode.incremental);
    expect(checkpoint?.successAtMs, 123456);
  });

  test('persists per-stock success timestamp map via file store', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-kline-checkpoint-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = KLineFileStorage();
    storage.setBaseDirPathForTesting(tempDir.path);
    final store = DailyKlineCheckpointStore(storage: storage);

    await store.savePerStockSuccessAtMs({'600000': 1000, '000001': 2000});

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('daily_kline_checkpoint_per_stock_last_success_at_ms'),
      isNull,
    );

    final reloaded = DailyKlineCheckpointStore(storage: storage);
    final map = await reloaded.loadPerStockSuccessAtMs();

    expect(map['600000'], 1000);
    expect(map['000001'], 2000);
  });

  test(
    'savePerStockSuccessAtMs preserves existing file when atomic writer rename fails',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-kline-checkpoint-failure-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final storage = KLineFileStorage();
      storage.setBaseDirPathForTesting(tempDir.path);

      final checkpointFile = File(
        '${tempDir.path}/checkpoints/daily_kline_per_stock_success_v1.json',
      );
      await checkpointFile.parent.create(recursive: true);
      const originalContent = '{"600000":1234}';
      await checkpointFile.writeAsString(originalContent, flush: true);

      final store = DailyKlineCheckpointStore(
        storage: storage,
        atomicWriter: const _RenameFailingAtomicFileWriter(),
      );

      await expectLater(
        store.savePerStockSuccessAtMs({'000001': 5678}),
        throwsA(isA<_RenameFailure>()),
      );
      expect(await checkpointFile.readAsString(), originalContent);
    },
  );
}
