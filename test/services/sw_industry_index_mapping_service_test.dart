import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/sw_industry_l1_mapping_store.dart';
import 'package:stock_rtwatcher/services/sw_industry_index_mapping_service.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

void main() {
  late Directory tempDir;
  late KLineFileStorage storage;
  late SwIndustryL1MappingStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'sw-industry-index-mapping-service-',
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

  test('refreshFromTushare builds unique l1_name to l1_code mapping', () async {
    late Map<String, dynamic> captured;
    final client = TushareClient(
      token: 'token_123',
      postJson: (payload) async {
        captured = payload;
        return {
          'code': 0,
          'msg': '',
          'data': {
            'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
            'items': [
              ['801080.SI', '半导体', '000001.SZ', '平安银行', 'Y'],
              ['801080.SI', '半导体', '000002.SZ', '万科A', 'Y'],
              ['801780.SI', '银行', '600000.SH', '浦发银行', 'Y'],
            ],
          },
        };
      },
    );
    final service = SwIndustryIndexMappingService(client: client, store: store);

    final mapping = await service.refreshFromTushare();

    expect((captured['params'] as Map<String, dynamic>)['is_new'], 'Y');
    expect(mapping, const {'半导体': '801080.SI', '银行': '801780.SI'});
    expect(await store.loadAll(), mapping);
  });

  test('resolveTsCodeByIndustry returns mapped code from cache', () async {
    await store.saveAll(const {'半导体': '801080.SI'});
    final client = TushareClient(token: 'token_123', postJson: (_) async => {});
    final service = SwIndustryIndexMappingService(client: client, store: store);

    final resolved = await service.resolveTsCodeByIndustry('半导体');

    expect(resolved, '801080.SI');
  });

  test('resolveTsCodeByIndustry returns null when no mapping exists', () async {
    final client = TushareClient(token: 'token_123', postJson: (_) async => {});
    final service = SwIndustryIndexMappingService(client: client, store: store);

    final resolved = await service.resolveTsCodeByIndustry('不存在行业');

    expect(resolved, isNull);
  });

  test('refreshFromTushare ignores blank names and blank l1 codes', () async {
    final client = TushareClient(
      token: 'token_123',
      postJson: (_) async {
        return {
          'code': 0,
          'msg': '',
          'data': {
            'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
            'items': [
              ['801080.SI', '半导体', '000001.SZ', '平安银行', 'Y'],
              ['', '空代码行业', '000002.SZ', '万科A', 'Y'],
              ['801780.SI', '', '600000.SH', '浦发银行', 'Y'],
              ['   ', '  ', '600001.SH', '邯郸钢铁', 'Y'],
            ],
          },
        };
      },
    );
    final service = SwIndustryIndexMappingService(client: client, store: store);

    final mapping = await service.refreshFromTushare();

    expect(mapping, const {'半导体': '801080.SI'});
  });

  test(
    'refreshFromTushare falls back to full set when is_new=Y is empty',
    () async {
      var callCount = 0;
      final capturedParams = <Map<String, dynamic>>[];
      final client = TushareClient(
        token: 'token_123',
        postJson: (payload) async {
          callCount++;
          capturedParams.add(
            Map<String, dynamic>.from(
              payload['params'] as Map<String, dynamic>,
            ),
          );
          if (callCount == 1) {
            return {
              'code': 0,
              'msg': '',
              'data': {
                'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
                'items': <List<dynamic>>[],
              },
            };
          }
          return {
            'code': 0,
            'msg': '',
            'data': {
              'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
              'items': [
                ['801780.SI', '银行', '600000.SH', '浦发银行', 'Y'],
              ],
            },
          };
        },
      );
      final service = SwIndustryIndexMappingService(
        client: client,
        store: store,
      );

      final mapping = await service.refreshFromTushare();

      expect(callCount, 2);
      expect(capturedParams[0]['is_new'], 'Y');
      expect(capturedParams[1].containsKey('is_new'), isFalse);
      expect(mapping, const {'银行': '801780.SI'});
      expect(await store.loadAll(), mapping);
    },
  );

  test('refreshFromTushare throws when no mapping is returned', () async {
    final client = TushareClient(
      token: 'token_123',
      postJson: (_) async {
        return {
          'code': 0,
          'msg': '',
          'data': {
            'fields': ['l1_code', 'l1_name', 'ts_code', 'name', 'is_new'],
            'items': <List<dynamic>>[],
          },
        };
      },
    );
    final service = SwIndustryIndexMappingService(client: client, store: store);

    await expectLater(service.refreshFromTushare(), throwsA(isA<StateError>()));
    expect(await store.loadAll(), isEmpty);
  });

  test(
    'seedFromBundledAssetIfEmpty saves bundled mapping when store is empty',
    () async {
      final client = TushareClient(
        token: 'token_123',
        postJson: (_) async => {},
      );
      final service = SwIndustryIndexMappingService(
        client: client,
        store: store,
        bundledMappingLoader: () async => const {
          '半导体': '801080.SI',
          '银行': '801780.SI',
        },
      );

      final seeded = await service.seedFromBundledAssetIfEmpty();

      expect(seeded, const {'半导体': '801080.SI', '银行': '801780.SI'});
      expect(await store.loadAll(), seeded);
    },
  );

  test(
    'refreshFromTushare falls back to bundled mapping when remote fails',
    () async {
      final client = TushareClient(
        token: 'token_123',
        postJson: (_) async => {'code': -2001, 'msg': 'invalid token'},
      );
      final service = SwIndustryIndexMappingService(
        client: client,
        store: store,
        bundledMappingLoader: () async => const {'银行': '801780.SI'},
      );

      final mapping = await service.refreshFromTushare();

      expect(mapping, const {'银行': '801780.SI'});
      expect(await store.loadAll(), const {'银行': '801780.SI'});
    },
  );

  test(
    'resolveTsCodeByIndustry seeds bundled mapping when store is empty',
    () async {
      final client = TushareClient(
        token: 'token_123',
        postJson: (_) async => {},
      );
      final service = SwIndustryIndexMappingService(
        client: client,
        store: store,
        bundledMappingLoader: () async => const {'半导体': '801080.SI'},
      );

      final resolved = await service.resolveTsCodeByIndustry('半导体');

      expect(resolved, '801080.SI');
      expect(await store.loadAll(), const {'半导体': '801080.SI'});
    },
  );
}
