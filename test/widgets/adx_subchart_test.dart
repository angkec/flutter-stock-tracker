import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/adx_cache_store.dart';
import 'package:stock_rtwatcher/models/adx_config.dart';
import 'package:stock_rtwatcher/models/adx_point.dart';
import 'package:stock_rtwatcher/widgets/adx_subchart.dart';
import 'package:stock_rtwatcher/widgets/kline_chart_with_subcharts.dart';

import '../support/kline_fixture_builder.dart';

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

void main() {
  testWidgets('shows cache-miss hint when local adx cache does not exist', (
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
                AdxSubChart(
                  key: const ValueKey('daily_adx_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeAdxCacheStore(const {}),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('暂无ADX缓存，请先在数据管理同步'), findsOneWidget);
  });

  testWidgets('renders ADX lines when cache covers visible bars', (
    tester,
  ) async {
    final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));
    final points = bars
        .map(
          (bar) => AdxPoint(
            datetime: bar.datetime,
            adx: 20.0,
            plusDi: 25.0,
            minusDi: 15.0,
          ),
        )
        .toList(growable: false);

    final series = AdxCacheSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: const AdxConfig(period: 14, threshold: 25),
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
                AdxSubChart(
                  key: const ValueKey('daily_adx_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeAdxCacheStore({'600000|daily': series}),
                  chartKey: const ValueKey('daily_adx_paint'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('daily_adx_paint')),
    );
    final painter = paint.painter as AdxSubChartPainter;
    expect(painter.points.length, 30);
    expect(painter.threshold, 25);
  });

  testWidgets('shows indicator values in top info strip', (tester) async {
    final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));
    final points = List<AdxPoint>.generate(
      bars.length,
      (index) => AdxPoint(
        datetime: bars[index].datetime,
        adx: 18 + index * 0.2,
        plusDi: 20 + index * 0.1,
        minusDi: 14 + index * 0.1,
      ),
      growable: false,
    );

    final series = AdxCacheSeries(
      stockCode: '600000',
      dataType: KLineDataType.daily,
      config: const AdxConfig(period: 14, threshold: 25),
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
                AdxSubChart(
                  key: const ValueKey('daily_adx_subchart'),
                  dataType: KLineDataType.daily,
                  cacheStore: _FakeAdxCacheStore({'600000|daily': series}),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('ADX'), findsWidgets);
    expect(find.textContaining('+DI'), findsWidgets);
    expect(find.textContaining('-DI'), findsWidgets);
  });

  testWidgets(
    'renders ADX when cache misses only the latest visible daily bar',
    (tester) async {
      final bars = buildDailyBars(count: 50, startDate: DateTime(2026, 1, 1));
      final points = bars
          .take(49)
          .map(
            (bar) => AdxPoint(
              datetime: bar.datetime,
              adx: 22.0,
              plusDi: 26.0,
              minusDi: 14.0,
            ),
          )
          .toList(growable: false);

      final series = AdxCacheSeries(
        stockCode: '600000',
        dataType: KLineDataType.daily,
        config: const AdxConfig(period: 14, threshold: 25),
        sourceSignature: 'test_tail_missing',
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
                  AdxSubChart(
                    key: const ValueKey('daily_adx_subchart'),
                    dataType: KLineDataType.daily,
                    cacheStore: _FakeAdxCacheStore({'600000|daily': series}),
                    chartKey: const ValueKey('daily_adx_paint_tail_missing'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('暂无ADX缓存，请先在数据管理同步'), findsNothing);

      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('daily_adx_paint_tail_missing')),
      );
      final painter = paint.painter as AdxSubChartPainter;
      expect(painter.points.length, 29);
    },
  );
}
