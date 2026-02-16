enum DailyCandleCompleteness { partial, finalized, unknown }

extension DailyCandleCompletenessX on DailyCandleCompleteness {
  bool get isTerminal => this == DailyCandleCompleteness.finalized;
}
