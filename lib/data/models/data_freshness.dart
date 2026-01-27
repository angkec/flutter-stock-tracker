// lib/data/models/data_freshness.dart

import 'date_range.dart';

/// 数据新鲜度
sealed class DataFreshness {
  const DataFreshness();

  factory DataFreshness.fresh() => const Fresh();
  factory DataFreshness.stale({required DateRange missingRange}) =>
      Stale(missingRange: missingRange);
  factory DataFreshness.missing() => const Missing();
}

class Fresh extends DataFreshness {
  const Fresh();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Fresh && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

class Stale extends DataFreshness {
  final DateRange missingRange;
  const Stale({required this.missingRange});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stale &&
          runtimeType == other.runtimeType &&
          missingRange == other.missingRange;

  @override
  int get hashCode => missingRange.hashCode;
}

class Missing extends DataFreshness {
  const Missing();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Missing && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
