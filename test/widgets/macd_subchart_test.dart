import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/macd_cache_store.dart';
import 'package:stock_rtwatcher/models/macd_config.dart';
import 'package:stock_rtwatcher/models/macd_point.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';
import 'package:stock_rtwatcher/widgets/macd_subchart.dart';

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

void main() {
  testWidgets('shows cache-miss hint when local macd cache does not exist', (
    tester,
  ) async {
    final bars = buildDailyBars(count: 40, startDate: DateTime(2026, 1, 1));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChartWithSubCharts(
              stockCode: '600000',
              bars: bars,
              subCharts: [
                MacdSubChart(
                  key: const ValueKey('daily_macd_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeMacdCacheStore(const {}),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('暂无MACD缓存，请先在数据管理同步'), findsOneWidget);
  });

  testWidgets('renders the same number of macd points as visible bars', (
    tester,
  ) async {
    final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));
    final points = bars
        .map(
          (bar) => MacdPoint(
            datetime: bar.datetime,
            dif: 0.1,
            dea: 0.08,
            hist: 0.04,
          ),
        )
        .toList(growable: false);

    final series = MacdCacheSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: MacdConfig.defaults,
      sourceSignature: 'test',
      points: points,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChartWithSubCharts(
              stockCode: '600000',
              bars: bars,
              subCharts: [
                MacdSubChart(
                  key: const ValueKey('daily_macd_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeMacdCacheStore({'600000|daily': series}),
                  chartKey: const ValueKey('daily_macd_paint'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('daily_macd_paint')),
    );
    final painter = paint.painter as MacdSubChartPainter;
    expect(painter.points.length, 30);
    expect(painter.selectedVisibleIndex, isNull);
  });

  testWidgets('passes selected visible index to painter when selecting', (
    tester,
  ) async {
    final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));
    final points = bars
        .map(
          (bar) => MacdPoint(
            datetime: bar.datetime,
            dif: 0.1,
            dea: 0.08,
            hist: 0.04,
          ),
        )
        .toList(growable: false);

    final series = MacdCacheSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: MacdConfig.defaults,
      sourceSignature: 'test_selected',
      points: points,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChartWithSubCharts(
              stockCode: '600000',
              bars: bars,
              subCharts: [
                MacdSubChart(
                  key: const ValueKey('daily_macd_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeMacdCacheStore({'600000|daily': series}),
                  chartKey: const ValueKey('daily_macd_paint_selected'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(KLineChartWithSubCharts));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('daily_macd_paint_selected')),
    );
    final painter = paint.painter as MacdSubChartPainter;
    expect(painter.selectedVisibleIndex, isNotNull);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('applies custom selection line style to painter', (tester) async {
    final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));
    final points = bars
        .map(
          (bar) => MacdPoint(
            datetime: bar.datetime,
            dif: 0.1,
            dea: 0.08,
            hist: 0.04,
          ),
        )
        .toList(growable: false);

    final series = MacdCacheSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: MacdConfig.defaults,
      sourceSignature: 'test_custom_style',
      points: points,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChartWithSubCharts(
              stockCode: '600000',
              bars: bars,
              subCharts: [
                MacdSubChart(
                  key: const ValueKey('daily_macd_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeMacdCacheStore({'600000|daily': series}),
                  chartKey: const ValueKey('daily_macd_paint_custom_style'),
                  selectionLineColor: Colors.purple,
                  selectionLineWidth: 2,
                  selectionDashLength: 6,
                  selectionGapLength: 4,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(KLineChartWithSubCharts));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('daily_macd_paint_custom_style')),
    );
    final painter = paint.painter as MacdSubChartPainter;
    expect(painter.selectionLineColor, Colors.purple);
    expect(painter.selectionLineWidth, 2);
    expect(painter.selectionDashLength, 6);
    expect(painter.selectionGapLength, 4);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('shows indicator values in top info strip', (tester) async {
    final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));
    final points = List<MacdPoint>.generate(
      bars.length,
      (index) => MacdPoint(
        datetime: bars[index].datetime,
        dif: index * 0.1,
        dea: index * 0.05,
        hist: index * 0.02,
      ),
      growable: false,
    );

    final series = MacdCacheSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: MacdConfig.defaults,
      sourceSignature: 'test_info_strip',
      points: points,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: KLineChartWithSubCharts(
              stockCode: '600000',
              bars: bars,
              subCharts: [
                MacdSubChart(
                  key: const ValueKey('daily_macd_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeMacdCacheStore({'600000|daily': series}),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('DIF'), findsOneWidget);
    expect(find.textContaining('DEA'), findsOneWidget);
    expect(find.textContaining('MACD'), findsWidgets);
    expect(find.text('DIF 4.90'), findsOneWidget);
    expect(find.text('DEA 2.45'), findsOneWidget);
    expect(find.text('MACD 0.98'), findsOneWidget);
  });
}
