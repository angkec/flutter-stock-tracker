import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// 生成指定数量的K线
List<KLine> generateBars(int upCount, int downCount, {double upVolume = 100, double downVolume = 100}) {
  final bars = <KLine>[];
  final now = DateTime.now();

  for (var i = 0; i < upCount; i++) {
    bars.add(KLine(
      datetime: now,
      open: 10,
      close: 11,
      high: 11,
      low: 10,
      volume: upVolume,
      amount: 0,
    ));
  }

  for (var i = 0; i < downCount; i++) {
    bars.add(KLine(
      datetime: now,
      open: 11,
      close: 10,
      high: 11,
      low: 10,
      volume: downVolume,
      amount: 0,
    ));
  }

  return bars;
}

void main() {
  group('StockService', () {
    group('calculateRatio', () {
      test('returns null for insufficient bars', () {
        final bars = generateBars(3, 3); // 6 bars < minBarsCount (10)
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNull);
      });

      test('returns null for up bars only (涨停)', () {
        final bars = generateBars(15, 0); // all up, no down
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNull);
      });

      test('returns null for down bars only (跌停)', () {
        final bars = generateBars(0, 15); // all down, no up
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNull);
      });

      test('returns null for extreme ratio (接近涨停)', () {
        // ratio = 100 > maxValidRatio (50)
        final bars = generateBars(10, 5, upVolume: 1000, downVolume: 10);
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNull);
      });

      test('returns null for extreme low ratio (接近跌停)', () {
        // ratio = 0.01 < 1/maxValidRatio (0.02)
        final bars = generateBars(5, 10, upVolume: 10, downVolume: 1000);
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNull);
      });

      test('calculates ratio for mixed bars', () {
        final bars = generateBars(8, 7, upVolume: 100, downVolume: 50);
        // upVolume = 8 * 100 = 800, downVolume = 7 * 50 = 350
        // ratio = 800 / 350 ≈ 2.286
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNotNull);
        expect(ratio, closeTo(800 / 350, 0.001));
      });

      test('ignores flat bars', () {
        final bars = <KLine>[];
        final now = DateTime.now();

        // 8 up bars
        for (var i = 0; i < 8; i++) {
          bars.add(KLine(datetime: now, open: 10, close: 11, high: 11, low: 10, volume: 100, amount: 0));
        }
        // 5 flat bars (should be ignored)
        for (var i = 0; i < 5; i++) {
          bars.add(KLine(datetime: now, open: 11, close: 11, high: 11, low: 11, volume: 50, amount: 0));
        }
        // 7 down bars
        for (var i = 0; i < 7; i++) {
          bars.add(KLine(datetime: now, open: 11, close: 10, high: 11, low: 10, volume: 100, amount: 0));
        }

        // upVolume = 800, downVolume = 700
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNotNull);
        expect(ratio, closeTo(800 / 700, 0.001));
      });
    });
  });
}
