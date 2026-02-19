import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  test('KLineFileStorageV2 save/load roundtrip', () async {
    final dir = await Directory.systemTemp.createTemp('kline_v2_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    final storage = KLineFileStorageV2()..setBaseDirPathForTesting(dir.path);

    final bars = [
      KLine(
        datetime: DateTime(2026, 2, 18),
        open: 10,
        close: 11,
        high: 11.5,
        low: 9.5,
        volume: 100,
        amount: 200,
      ),
    ];

    await storage.saveMonthlyKlineFile('000001', KLineDataType.daily, 2026, 2, bars);
    final filePath =
        await storage.getFilePathAsync('000001', KLineDataType.daily, 2026, 2);
    expect(filePath, endsWith('.bin.zlib'));
    final loaded =
        await storage.loadMonthlyKlineFile('000001', KLineDataType.daily, 2026, 2);

    expect(loaded.length, 1);
    expect(loaded.first.close, 11);
  });
}
