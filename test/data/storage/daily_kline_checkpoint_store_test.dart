import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

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
}
