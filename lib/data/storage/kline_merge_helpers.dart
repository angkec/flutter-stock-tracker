import 'package:stock_rtwatcher/models/kline.dart';

class KLineMergeResult {
  final bool changed;
  final List<KLine> merged;

  const KLineMergeResult({required this.changed, required this.merged});
}

class KLineMergeHelper {
  static KLineMergeResult mergeAndDeduplicate(
    List<KLine> existing,
    List<KLine> newKlines,
  ) {
    final normalizedExisting = _ensureSorted(existing);
    final normalizedIncoming = _deduplicateAndSortIncoming(newKlines);

    if (normalizedIncoming.isEmpty) {
      return KLineMergeResult(changed: false, merged: normalizedExisting);
    }

    if (normalizedExisting.isEmpty) {
      return KLineMergeResult(changed: true, merged: normalizedIncoming);
    }

    final merged = <KLine>[];
    var changed = false;
    var existingIndex = 0;
    var incomingIndex = 0;

    while (existingIndex < normalizedExisting.length &&
        incomingIndex < normalizedIncoming.length) {
      final existingBar = normalizedExisting[existingIndex];
      final incomingBar = normalizedIncoming[incomingIndex];
      final compare = existingBar.datetime.compareTo(incomingBar.datetime);

      if (compare < 0) {
        merged.add(existingBar);
        existingIndex++;
        continue;
      }

      if (compare > 0) {
        merged.add(incomingBar);
        incomingIndex++;
        changed = true;
        continue;
      }

      if (!_isSameKLine(existingBar, incomingBar)) {
        changed = true;
      }
      merged.add(incomingBar);
      existingIndex++;
      incomingIndex++;
    }

    while (existingIndex < normalizedExisting.length) {
      merged.add(normalizedExisting[existingIndex]);
      existingIndex++;
    }

    while (incomingIndex < normalizedIncoming.length) {
      merged.add(normalizedIncoming[incomingIndex]);
      incomingIndex++;
      changed = true;
    }

    return KLineMergeResult(changed: changed, merged: merged);
  }

  static List<KLine> _deduplicateAndSortIncoming(List<KLine> newKlines) {
    final byDatetime = <DateTime, KLine>{
      for (final kline in newKlines) kline.datetime: kline,
    };

    final deduplicated = byDatetime.values.toList(growable: false)
      ..sort((left, right) => left.datetime.compareTo(right.datetime));

    return deduplicated;
  }

  static List<KLine> _ensureSorted(List<KLine> klines) {
    if (klines.length < 2) {
      return klines;
    }

    for (var index = 1; index < klines.length; index++) {
      if (klines[index - 1].datetime.isAfter(klines[index].datetime)) {
        final sorted = List<KLine>.from(klines);
        sorted.sort((left, right) => left.datetime.compareTo(right.datetime));
        return sorted;
      }
    }

    return klines;
  }

  static bool _isSameKLine(KLine left, KLine right) {
    return left.datetime == right.datetime &&
        left.open == right.open &&
        left.close == right.close &&
        left.high == right.high &&
        left.low == right.low &&
        left.volume == right.volume &&
        left.amount == right.amount;
  }
}
