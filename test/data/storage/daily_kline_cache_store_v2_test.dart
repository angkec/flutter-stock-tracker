import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_monthly_storage.dart';

void main() {
  test('daily cache uses v2 monthly storage fallback', () {
    final v2 = KLineFileStorageV2();
    final cache = DailyKlineCacheStore(monthlyStorage: v2);
    expect(cache.monthlyStorage, isA<KLineFileStorageV2>());
  });

  test('daily cache defaults to v2 monthly storage', () {
    final cache = DailyKlineCacheStore();
    expect(cache.monthlyStorage, isA<KLineFileStorageV2>());
  });
}
