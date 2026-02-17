import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';

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

  test('persists per-stock success timestamp map', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DailyKlineCheckpointStore();

    await store.savePerStockSuccessAtMs({'600000': 1000, '000001': 2000});
    final map = await store.loadPerStockSuccessAtMs();

    expect(map['600000'], 1000);
    expect(map['000001'], 2000);
  });
}
