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
}

class Stale extends DataFreshness {
  final DateRange missingRange;
  const Stale({required this.missingRange});
}

class Missing extends DataFreshness {
  const Missing();
}
