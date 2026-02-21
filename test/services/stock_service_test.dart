import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/power_system_point.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _StreamingFakePool extends TdxPool {
  _StreamingFakePool({required this.barsByStockCode}) : super(poolSize: 1);

  final Map<String, List<KLine>> barsByStockCode;

  @override
  Future<void> batchGetSecurityBarsStreaming({
    required List<Stock> stocks,
    required int category,
    required int start,
    required int count,
    required void Function(int stockIndex, List<KLine> bars) onStockBars,
  }) async {
    for (var index = 0; index < stocks.length; index++) {
      onStockBars(
        index,
        barsByStockCode[stocks[index].code] ?? const <KLine>[],
      );
    }
  }
}

/// 生成指定数量的K线
List<KLine> generateBars(
  int upCount,
  int downCount, {
  double upVolume = 100,
  double downVolume = 100,
}) {
  final bars = <KLine>[];
  final now = DateTime.now();

  for (var i = 0; i < upCount; i++) {
    bars.add(
      KLine(
        datetime: now,
        open: 10,
        close: 11,
        high: 11,
        low: 10,
        volume: upVolume,
        amount: 0,
      ),
    );
  }

  for (var i = 0; i < downCount; i++) {
    bars.add(
      KLine(
        datetime: now,
        open: 11,
        close: 10,
        high: 11,
        low: 10,
        volume: downVolume,
        amount: 0,
      ),
    );
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
          bars.add(
            KLine(
              datetime: now,
              open: 10,
              close: 11,
              high: 11,
              low: 10,
              volume: 100,
              amount: 0,
            ),
          );
        }
        // 5 flat bars (should be ignored)
        for (var i = 0; i < 5; i++) {
          bars.add(
            KLine(
              datetime: now,
              open: 11,
              close: 11,
              high: 11,
              low: 11,
              volume: 50,
              amount: 0,
            ),
          );
        }
        // 7 down bars
        for (var i = 0; i < 7; i++) {
          bars.add(
            KLine(
              datetime: now,
              open: 11,
              close: 10,
              high: 11,
              low: 10,
              volume: 100,
              amount: 0,
            ),
          );
        }

        // upVolume = 800, downVolume = 700
        final ratio = StockService.calculateRatio(bars);
        expect(ratio, isNotNull);
        expect(ratio, closeTo(800 / 700, 0.001));
      });
    });

    group('StockMonitorData serialization', () {
      final stock = Stock(code: '000001', name: 'PingAn', market: 0);

      test('copyWith updates isPowerSystemUp', () {
        final original = StockMonitorData(
          stock: stock,
          ratio: 1.2,
          changePercent: 2.5,
        );

        final updated = original.copyWith(isPowerSystemUp: true);

        expect(updated.isPowerSystemUp, isTrue);
        expect(updated.isBreakout, original.isBreakout);
        expect(updated.isPullback, original.isPullback);
      });

      test('copyWith updates powerSystemStates', () {
        final original = StockMonitorData(
          stock: stock,
          ratio: 1.2,
          changePercent: 2.5,
        );
        final states = <PowerSystemDayState>[
          PowerSystemDayState(
            state: PowerSystemDailyState.bullish,
            date: DateTime(2026, 2, 20),
            dailyState: 1,
            weeklyState: 1,
          ),
        ];

        final updated = original.copyWith(powerSystemStates: states);

        expect(updated.powerSystemStates, hasLength(1));
        expect(
          updated.powerSystemStates.first.state,
          PowerSystemDailyState.bullish,
        );
      });

      test('toJson/fromJson persists isPowerSystemUp', () {
        final states = <PowerSystemDayState>[
          PowerSystemDayState(
            state: PowerSystemDailyState.bearish,
            date: DateTime(2026, 2, 19),
            dailyState: -1,
            weeklyState: -1,
          ),
        ];
        final original = StockMonitorData(
          stock: stock,
          ratio: 1.5,
          changePercent: 3.0,
          isPowerSystemUp: true,
          powerSystemStates: states,
        );

        final restored = StockMonitorData.fromJson(original.toJson());

        expect(restored.isPowerSystemUp, isTrue);
        expect(restored.powerSystemStates, hasLength(1));
        expect(
          restored.powerSystemStates.first.state,
          PowerSystemDailyState.bearish,
        );
        expect(restored.powerSystemStates.first.dailyState, -1);
        expect(restored.powerSystemStates.first.weeklyState, -1);
        expect(restored.stock.code, original.stock.code);
        expect(restored.ratio, original.ratio);
      });

      test('fromJson defaults isPowerSystemUp to false', () {
        final json = {
          'stock': stock.toJson(),
          'ratio': 1.0,
          'changePercent': 0.5,
          'industry': null,
          'isPullback': false,
          'isBreakout': false,
          'upVolume': 0,
          'downVolume': 0,
        };

        final restored = StockMonitorData.fromJson(json);

        expect(restored.isPowerSystemUp, isFalse);
        expect(restored.powerSystemStates, isEmpty);
      });
    });

    group('batchGetMonitorData fallback', () {
      test(
        'should fallback to latest available date when fallbackDates is empty',
        () async {
          final today = DateTime.now();
          final nineBarsToday = List<KLine>.generate(9, (index) {
            return KLine(
              datetime: DateTime(
                today.year,
                today.month,
                today.day,
                9,
                30 + index,
              ),
              open: 10,
              close: 11,
              high: 11,
              low: 10,
              volume: 100,
              amount: 0,
            );
          });

          final validBarsToday = List<KLine>.generate(20, (index) {
            final isUp = index.isEven;
            return KLine(
              datetime: DateTime(today.year, today.month, today.day, 10, index),
              open: isUp ? 10 : 11,
              close: isUp ? 11 : 10,
              high: 11,
              low: 10,
              volume: 100,
              amount: 0,
            );
          });

          final stocks = List<Stock>.generate(
            20,
            (index) => Stock(
              code: index == 0
                  ? '000001'
                  : '000${(index + 1).toString().padLeft(3, '0')}',
              name: 'Stock$index',
              market: 0,
            ),
          );

          final pool = _StreamingFakePool(
            barsByStockCode: {
              '000001': validBarsToday,
              '000002': nineBarsToday,
            },
          );
          final service = StockService(pool);

          final result = await service.batchGetMonitorData(stocks);

          expect(result.data, isNotEmpty);
          expect(result.dataDate.year, today.year);
          expect(result.dataDate.month, today.month);
          expect(result.dataDate.day, today.day);
        },
      );

      test(
        'should fallback per stock latest bars when target date missing',
        () async {
          final today = DateTime.now();
          final yesterday = today.subtract(const Duration(days: 1));

          List<KLine> mixedBarsFor(DateTime day) {
            return List<KLine>.generate(20, (index) {
              final isUp = index.isEven;
              return KLine(
                datetime: DateTime(day.year, day.month, day.day, 10, index),
                open: isUp ? 10 : 11,
                close: isUp ? 11 : 10,
                high: 11,
                low: 10,
                volume: 100,
                amount: 0,
              );
            });
          }

          final stocks = List<Stock>.generate(
            20,
            (index) => Stock(
              code: '00${(index + 1).toString().padLeft(4, '0')}',
              name: 'Stock$index',
              market: 0,
            ),
          );

          final barsByStockCode = <String, List<KLine>>{};
          for (var i = 0; i < 20; i++) {
            barsByStockCode[stocks[i].code] = i == 0
                ? mixedBarsFor(yesterday)
                : mixedBarsFor(today);
          }

          final pool = _StreamingFakePool(barsByStockCode: barsByStockCode);
          final service = StockService(pool);

          final result = await service.batchGetMonitorData(stocks);

          expect(result.data, isNotEmpty);
          expect(result.data.length, greaterThan(10));
        },
      );
    });
  });
}
