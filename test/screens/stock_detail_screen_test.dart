import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/adx_config.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/screens/stock_detail_screen.dart';

import '../support/kline_fixture_builder.dart';

class _FakeMacdCacheStore extends MacdCacheStore {
  _FakeMacdCacheStore(this._seriesByKey);

  final Map<String, MacdCacheSeries> _seriesByKey;

  @override
  Future<MacdCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    return _seriesByKey['$stockCode|${dataType.name}'];
  }
}

class _FakeAdxCacheStore extends AdxCacheStore {
  _FakeAdxCacheStore(this._seriesByKey);

  final Map<String, AdxCacheSeries> _seriesByKey;

  @override
  Future<AdxCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    return _seriesByKey['$stockCode|${dataType.name}'];
  }
}

MacdCacheSeries _buildSeries({
  required String stockCode,
  required KLineDataType dataType,
  required List<DateTime> dates,
}) {
  return MacdCacheSeries(
    stockCode: stockCode,
    dataType: dataType,
    config: MacdConfig.defaults,
    sourceSignature: 'test_${stockCode}_${dataType.name}',
    points: dates
        .map(
          (date) => MacdPoint(datetime: date, dif: 0.1, dea: 0.08, hist: 0.04),
        )
        .toList(growable: false),
  );
}

AdxCacheSeries _buildAdxSeries({
  required String stockCode,
  required KLineDataType dataType,
  required List<DateTime> dates,
}) {
  return AdxCacheSeries(
    stockCode: stockCode,
    dataType: dataType,
    config: const AdxConfig(period: 14, threshold: 25),
    sourceSignature: 'test_adx_${stockCode}_${dataType.name}',
    points: dates
        .map(
          (date) => AdxPoint(datetime: date, adx: 20, plusDi: 25, minusDi: 15),
        )
        .toList(growable: false),
  );
}

void main() {
  final stock = Stock(code: '600000', name: '浦发银行', market: 1, preClose: 10.2);

  testWidgets('daily mode displays cached MACD subchart section', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StockDetailScreen(
          stock: stock,
          skipAutoConnectForTest: true,
          showWatchlistToggle: false,
          showIndustryHeatSection: false,
          initialChartMode: ChartMode.daily,
          initialDailyBars: buildDailyBars(
            count: 50,
            startDate: DateTime(2026, 1, 1),
          ),
          initialWeeklyBars: buildWeeklyBars(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('stock_detail_macd_daily')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock_detail_adx_daily')),
      findsOneWidget,
    );
  });

  testWidgets('weekly mode displays cached MACD subchart section', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StockDetailScreen(
          stock: stock,
          skipAutoConnectForTest: true,
          showWatchlistToggle: false,
          showIndustryHeatSection: false,
          initialChartMode: ChartMode.weekly,
          initialDailyBars: buildDailyBars(
            count: 50,
            startDate: DateTime(2026, 1, 1),
          ),
          initialWeeklyBars: buildWeeklyBars(),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('stock_detail_macd_weekly')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock_detail_adx_weekly')),
      findsOneWidget,
    );
  });

  testWidgets(
    'weekly mode renders MACD paint with trailing-only weekly cache',
    (tester) async {
      final weeklyBars = buildDailyBars(
        count: 80,
        startDate: DateTime(2025, 1, 1),
      );
      const stockCode = '600000';
      final cacheStore = _FakeMacdCacheStore({
        '$stockCode|weekly': _buildSeries(
          stockCode: stockCode,
          dataType: KLineDataType.weekly,
          dates: weeklyBars
              .sublist(weeklyBars.length - 12)
              .map((bar) => bar.datetime)
              .toList(growable: false),
        ),
      });
      final adxCacheStore = _FakeAdxCacheStore({
        '$stockCode|weekly': _buildAdxSeries(
          stockCode: stockCode,
          dataType: KLineDataType.weekly,
          dates: weeklyBars
              .sublist(weeklyBars.length - 12)
              .map((bar) => bar.datetime)
              .toList(growable: false),
        ),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: StockDetailScreen(
            stock: stock,
            skipAutoConnectForTest: true,
            showWatchlistToggle: false,
            showIndustryHeatSection: false,
            initialChartMode: ChartMode.weekly,
            initialDailyBars: buildDailyBars(
              count: 50,
              startDate: DateTime(2026, 1, 1),
            ),
            initialWeeklyBars: weeklyBars,
            macdCacheStoreForTest: cacheStore,
            adxCacheStoreForTest: adxCacheStore,
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('暂无MACD缓存，请先在数据管理同步'), findsNothing);
      expect(
        find.byKey(const ValueKey('stock_detail_macd_paint_weekly')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('stock_detail_adx_paint_weekly')),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders MACD paint for daily and linked modes with cache', (
    tester,
  ) async {
    final dailyBars = buildDailyBars(
      count: 50,
      startDate: DateTime(2026, 1, 1),
    );
    final weeklyBars = buildWeeklyBars();
    const stockCode = '600000';

    final cacheStore = _FakeMacdCacheStore({
      '$stockCode|daily': _buildSeries(
        stockCode: stockCode,
        dataType: KLineDataType.daily,
        dates: dailyBars.map((bar) => bar.datetime).toList(growable: false),
      ),
      '$stockCode|weekly': _buildSeries(
        stockCode: stockCode,
        dataType: KLineDataType.weekly,
        dates: weeklyBars.map((bar) => bar.datetime).toList(growable: false),
      ),
    });
    final adxCacheStore = _FakeAdxCacheStore({
      '$stockCode|daily': _buildAdxSeries(
        stockCode: stockCode,
        dataType: KLineDataType.daily,
        dates: dailyBars.map((bar) => bar.datetime).toList(growable: false),
      ),
      '$stockCode|weekly': _buildAdxSeries(
        stockCode: stockCode,
        dataType: KLineDataType.weekly,
        dates: weeklyBars.map((bar) => bar.datetime).toList(growable: false),
      ),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StockDetailScreen(
          stock: stock,
          skipAutoConnectForTest: true,
          showWatchlistToggle: false,
          showIndustryHeatSection: false,
          initialChartMode: ChartMode.daily,
          initialDailyBars: dailyBars,
          initialWeeklyBars: weeklyBars,
          macdCacheStoreForTest: cacheStore,
          adxCacheStoreForTest: adxCacheStore,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('stock_detail_macd_paint_daily')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock_detail_adx_paint_daily')),
      findsOneWidget,
    );

    await tester.tap(find.text('联动'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('linked_weekly_macd_paint')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_daily_macd_paint')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_weekly_adx_paint')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_daily_adx_paint')),
      findsOneWidget,
    );
  });
}
