import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

void main() {
  group('StockService', () {
    group('calculateRatio', () {
      test('calculates ratio for up bars only', () {
        final bars = [
          KLine(datetime: DateTime.now(), open: 10, close: 11, high: 11, low: 10, volume: 100, amount: 0),
          KLine(datetime: DateTime.now(), open: 11, close: 12, high: 12, low: 11, volume: 200, amount: 0),
        ];
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, 999); // 无跌量时返回999
      });

      test('calculates ratio for mixed bars', () {
        final bars = [
          KLine(datetime: DateTime.now(), open: 10, close: 11, high: 11, low: 10, volume: 100, amount: 0),
          KLine(datetime: DateTime.now(), open: 11, close: 10, high: 11, low: 10, volume: 50, amount: 0),
        ];
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, 2.0);
      });

      test('ignores flat bars', () {
        final bars = [
          KLine(datetime: DateTime.now(), open: 10, close: 11, high: 11, low: 10, volume: 100, amount: 0),
          KLine(datetime: DateTime.now(), open: 11, close: 11, high: 11, low: 11, volume: 50, amount: 0),
          KLine(datetime: DateTime.now(), open: 11, close: 10, high: 11, low: 10, volume: 100, amount: 0),
        ];
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, 1.0);
      });
    });
  });
}
