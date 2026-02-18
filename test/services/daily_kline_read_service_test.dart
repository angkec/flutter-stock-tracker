import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/daily_kline_read_service.dart';

DailyKlineCacheStore _buildStore(String basePath) {
  final storage = KLineFileStorage();
  storage.setBaseDirPathForTesting(basePath);
  return DailyKlineCacheStore(storage: storage);
}

List<KLine> _buildBars(int count) {
  final start = DateTime(2026, 1, 1);
  return List.generate(count, (index) {
    final date = start.add(Duration(days: index));
    return KLine(
      datetime: date,
      open: 10,
      high: 10.5,
      low: 9.8,
      close: 10.2,
      volume: 1000.0 + index,
      amount: 10000.0 + index,
    );
  });
}

void main() {
  test('readOrThrow returns bars when all files are valid', () async {
    final tempDir = await Directory.systemTemp.createTemp('daily-read-ok-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = _buildStore(tempDir.path);
    await store.saveAll({'600000': _buildBars(260)});

    final service = DailyKlineReadService(cacheStore: store);
    final result = await service.readOrThrow(
      stockCodes: const ['600000'],
      anchorDate: DateTime(2026, 12, 31),
      targetBars: 260,
    );

    expect(result['600000'], isNotNull);
    expect(result['600000']!.length, 260);
  });

  test('readOrThrow throws when any stock cache is missing', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'daily-read-missing-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final store = _buildStore(tempDir.path);
    final service = DailyKlineReadService(cacheStore: store);

    expect(
      () => service.readOrThrow(
        stockCodes: const ['600000'],
        anchorDate: DateTime(2026, 12, 31),
        targetBars: 260,
      ),
      throwsA(
        isA<DailyKlineReadException>().having(
          (e) => e.reason,
          'reason',
          DailyKlineReadFailureReason.missingFile,
        ),
      ),
    );
  });

  test(
    'readOrThrow throws corruptedPayload when cache JSON is invalid',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-read-corrupted-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = _buildStore(tempDir.path);
      await store.initialize();

      final cacheFile = File(
        '${tempDir.path}/daily_cache/600000_daily_cache.json',
      );
      await cacheFile.create(recursive: true);
      await cacheFile.writeAsString('{not-json');

      final service = DailyKlineReadService(cacheStore: store);

      expect(
        () => service.readOrThrow(
          stockCodes: const ['600000'],
          anchorDate: DateTime(2026, 12, 31),
          targetBars: 260,
        ),
        throwsA(
          isA<DailyKlineReadException>().having(
            (e) => e.reason,
            'reason',
            DailyKlineReadFailureReason.corruptedPayload,
          ),
        ),
      );
    },
  );

  test(
    'readOrThrow throws insufficientBars when bars are fewer than target',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-read-insufficient-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = _buildStore(tempDir.path);
      await store.saveAll({'600000': _buildBars(120)});

      final service = DailyKlineReadService(cacheStore: store);

      expect(
        () => service.readOrThrow(
          stockCodes: const ['600000'],
          anchorDate: DateTime(2026, 12, 31),
          targetBars: 260,
        ),
        throwsA(
          isA<DailyKlineReadException>().having(
            (e) => e.reason,
            'reason',
            DailyKlineReadFailureReason.insufficientBars,
          ),
        ),
      );
    },
  );

  test(
    'readOrThrow throws corruptedPayload when cache JSON array has invalid element schema',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'daily-read-corrupted-schema-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = _buildStore(tempDir.path);
      await store.initialize();

      final cacheFile = File(
        '${tempDir.path}/daily_cache/600000_daily_cache.json',
      );
      await cacheFile.create(recursive: true);
      await cacheFile.writeAsString('[1, 2, 3]');

      final service = DailyKlineReadService(cacheStore: store);

      expect(
        () => service.readOrThrow(
          stockCodes: const ['600000'],
          anchorDate: DateTime(2026, 12, 31),
          targetBars: 260,
        ),
        throwsA(
          isA<DailyKlineReadException>().having(
            (e) => e.reason,
            'reason',
            DailyKlineReadFailureReason.corruptedPayload,
          ),
        ),
      );
    },
  );
}
