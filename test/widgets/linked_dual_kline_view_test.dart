import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/models/linked_layout_result.dart';
import 'package:stock_rtwatcher/models/power_system_point.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/linked_dual_kline_view.dart';

import '../support/kline_fixture_builder.dart';

class _FakePowerSystemCacheStore extends PowerSystemCacheStore {
  _FakePowerSystemCacheStore(this._seriesByKey);

  final Map<String, PowerSystemCacheSeries> _seriesByKey;

  @override
  Future<PowerSystemCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    return _seriesByKey['$stockCode|${dataType.name}'];
  }
}

class _FakeEmaCacheStore extends EmaCacheStore {
  _FakeEmaCacheStore(this._seriesByKey);

  final Map<String, EmaCacheSeries> _seriesByKey;

  @override
  Future<EmaCacheSeries?> loadSeries({
    required String stockCode,
    required KLineDataType dataType,
  }) async {
    return _seriesByKey['$stockCode|${dataType.name}'];
  }
}

PowerSystemCacheSeries _buildPowerSystemSeries({
  required String stockCode,
  required KLineDataType dataType,
  required List<DateTime> dates,
}) {
  return PowerSystemCacheSeries(
    stockCode: stockCode,
    dataType: dataType,
    sourceSignature: 'test_power_${stockCode}_${dataType.name}',
    points: dates
        .map((date) => PowerSystemPoint(datetime: date, state: 1))
        .toList(growable: false),
  );
}

void main() {
  testWidgets('renders weekly and daily charts in linked mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkedDualKlineView(
            stockCode: '600000',
            weeklyBars: buildWeeklyBars(),
            dailyBars: buildDailyBarsForTwoWeeks(),
            ratios: const [],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('linked_weekly_chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('linked_daily_chart')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('linked_weekly_macd_subchart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_daily_macd_subchart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_weekly_adx_subchart')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('linked_daily_adx_subchart')),
      findsOneWidget,
    );

    final weeklyChart = tester.widget<KLineChartWithSubCharts>(
      find.byKey(const ValueKey('linked_weekly_chart')),
    );
    final dailyChart = tester.widget<KLineChartWithSubCharts>(
      find.byKey(const ValueKey('linked_daily_chart')),
    );
    expect(weeklyChart.showWeeklySeparators, isFalse);
    expect(dailyChart.showWeeklySeparators, isTrue);
  });

  testWidgets(
    'uses injected resolved heights for weekly and daily main charts',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const layout = LinkedLayoutResult(
        containerHeight: 700,
        top: LinkedPaneLayoutResult(
          mainChartHeight: 96,
          subchartHeights: [60, 60],
        ),
        bottom: LinkedPaneLayoutResult(
          mainChartHeight: 130,
          subchartHeights: [62, 62],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: layout.containerHeight,
              child: LinkedDualKlineView(
                stockCode: '600000',
                weeklyBars: buildWeeklyBars(),
                dailyBars: buildDailyBarsForTwoWeeks(),
                ratios: const [],
                layout: layout,
              ),
            ),
          ),
        ),
      );

      final weeklyChart = tester.widget<KLineChartWithSubCharts>(
        find.byKey(const ValueKey('linked_weekly_chart')),
      );
      final dailyChart = tester.widget<KLineChartWithSubCharts>(
        find.byKey(const ValueKey('linked_daily_chart')),
      );

      expect(weeklyChart.chartHeight, 96);
      expect(dailyChart.chartHeight, 130);
    },
  );

  testWidgets('wires weekly and daily candle resolvers from power cache', (
    tester,
  ) async {
    final weeklyBars = buildWeeklyBars();
    final dailyBars = buildDailyBarsForTwoWeeks();
    const stockCode = '600000';

    final powerStore = _FakePowerSystemCacheStore({
      '$stockCode|weekly': _buildPowerSystemSeries(
        stockCode: stockCode,
        dataType: KLineDataType.weekly,
        dates: weeklyBars.map((bar) => bar.datetime).toList(growable: false),
      ),
      '$stockCode|daily': _buildPowerSystemSeries(
        stockCode: stockCode,
        dataType: KLineDataType.daily,
        dates: dailyBars.map((bar) => bar.datetime).toList(growable: false),
      ),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkedDualKlineView(
            stockCode: stockCode,
            weeklyBars: weeklyBars,
            dailyBars: dailyBars,
            ratios: const [],
            emaCacheStoreForTest: _FakeEmaCacheStore(const {}),
            powerSystemCacheStoreForTest: powerStore,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final weeklyChart = tester.widget<KLineChartWithSubCharts>(
      find.byKey(const ValueKey('linked_weekly_chart')),
    );
    final dailyChart = tester.widget<KLineChartWithSubCharts>(
      find.byKey(const ValueKey('linked_daily_chart')),
    );

    expect(weeklyChart.candleColorResolver, isNotNull);
    expect(dailyChart.candleColorResolver, isNotNull);
  });
}
