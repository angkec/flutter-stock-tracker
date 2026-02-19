import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_monthly_storage.dart';

void main() {
  test('KLineFileStorage implements KLineMonthlyStorage', () {
    final storage = KLineFileStorage();
    expect(storage, isA<KLineMonthlyStorage>());
  });
}
