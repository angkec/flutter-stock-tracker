import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';

void main() {
  test('daily completeness should expose terminal state', () {
    expect(DailyCandleCompleteness.partial.isTerminal, isFalse);
    expect(DailyCandleCompleteness.finalized.isTerminal, isTrue);
    expect(DailyCandleCompleteness.unknown.isTerminal, isFalse);
  });
}
