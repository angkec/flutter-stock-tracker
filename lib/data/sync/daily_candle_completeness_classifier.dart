import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class DailyCandleCompletenessResult {
  const DailyCandleCompletenessResult({
    required this.completeness,
    required this.reason,
  });

  final DailyCandleCompleteness completeness;
  final String reason;
}

class DailyCandleCompletenessClassifier {
  const DailyCandleCompletenessClassifier();

  DailyCandleCompletenessResult classify({
    required KLine bar,
    required bool marketClosed,
    bool? sourceFinalFlag,
  }) {
    if (sourceFinalFlag == true) {
      return const DailyCandleCompletenessResult(
        completeness: DailyCandleCompleteness.finalized,
        reason: 'source_final_flag',
      );
    }

    if (sourceFinalFlag == false) {
      return const DailyCandleCompletenessResult(
        completeness: DailyCandleCompleteness.partial,
        reason: 'source_partial_flag',
      );
    }

    if (!marketClosed) {
      return const DailyCandleCompletenessResult(
        completeness: DailyCandleCompleteness.partial,
        reason: 'structure_intraday_open',
      );
    }

    return const DailyCandleCompletenessResult(
      completeness: DailyCandleCompleteness.unknown,
      reason: 'structure_closed_without_source_flag',
    );
  }
}
