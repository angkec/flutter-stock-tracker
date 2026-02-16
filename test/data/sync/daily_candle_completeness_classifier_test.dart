import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness_classifier.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  final bar = KLine(
    datetime: DateTime(2026, 2, 16),
    open: 10,
    close: 10.2,
    high: 10.3,
    low: 9.9,
    volume: 1200,
    amount: 9800,
  );

  test('source explicit final should win', () {
    const classifier = DailyCandleCompletenessClassifier();
    final result = classifier.classify(
      bar: bar,
      sourceFinalFlag: true,
      marketClosed: false,
    );

    expect(result.completeness, DailyCandleCompleteness.finalized);
    expect(result.reason, 'source_final_flag');
  });

  test('source explicit partial should win', () {
    const classifier = DailyCandleCompletenessClassifier();
    final result = classifier.classify(
      bar: bar,
      sourceFinalFlag: false,
      marketClosed: true,
    );

    expect(result.completeness, DailyCandleCompleteness.partial);
    expect(result.reason, 'source_partial_flag');
  });

  test('fallback to partial when market is still open and source is missing', () {
    const classifier = DailyCandleCompletenessClassifier();
    final result = classifier.classify(
      bar: bar,
      sourceFinalFlag: null,
      marketClosed: false,
    );

    expect(result.completeness, DailyCandleCompleteness.partial);
    expect(result.reason, 'structure_intraday_open');
  });

  test('fallback to unknown when market closed without source flag', () {
    const classifier = DailyCandleCompletenessClassifier();
    final result = classifier.classify(
      bar: bar,
      sourceFinalFlag: null,
      marketClosed: true,
    );

    expect(result.completeness, DailyCandleCompleteness.unknown);
    expect(result.reason, 'structure_closed_without_source_flag');
  });
}
