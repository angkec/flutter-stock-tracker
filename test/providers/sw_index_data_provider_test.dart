import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/repository/sw_index_repository.dart';
import 'package:stock_rtwatcher/providers/sw_index_data_provider.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

void main() {
  group('SwIndexDataProvider', () {
    test('syncIncremental updates loading state and stats', () async {
      final repository = _FakeSwIndexRepository();
      final provider = SwIndexDataProvider(repository: repository);

      await provider.refreshStats();
      expect(provider.cacheCodeCount, 2);

      final future = provider.syncIncremental(
        tsCodes: const ['801010.SI'],
        dateRange: DateRange(DateTime(2025, 1, 1), DateTime(2025, 1, 31)),
      );

      expect(provider.isLoading, isTrue);
      await future;

      expect(provider.isLoading, isFalse);
      expect(provider.lastError, isNull);
      expect(provider.lastFetchedCodes, const ['801010.SI']);
    });
  });
}

class _FakeSwIndexRepository extends SwIndexRepository {
  _FakeSwIndexRepository()
    : super(
        client: TushareClient(
          token: 'fake-token',
          postJson: (_) async => {
            'code': 0,
            'msg': '',
            'data': {'fields': <String>[], 'items': <List<dynamic>>[]},
          },
        ),
      );

  @override
  Future<SwIndexCacheStats> getCacheStats() async {
    return const SwIndexCacheStats(codeCount: 2, dataVersion: 3);
  }

  @override
  Future<SwIndexSyncResult> syncMissingDaily({
    required List<String> tsCodes,
    required DateRange dateRange,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const SwIndexSyncResult(fetchedCodes: ['801010.SI'], totalBars: 1);
  }
}
