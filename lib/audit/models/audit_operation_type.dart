enum AuditOperationType {
  historicalFetchMissing,
  dailyForceRefetch,
  weeklyFetchMissing,
  weeklyForceRefetch,
  weeklyMacdRecompute,
}

extension AuditOperationTypeX on AuditOperationType {
  String get wireName {
    switch (this) {
      case AuditOperationType.historicalFetchMissing:
        return 'historical_fetch_missing';
      case AuditOperationType.dailyForceRefetch:
        return 'daily_force_refetch';
      case AuditOperationType.weeklyFetchMissing:
        return 'weekly_fetch_missing';
      case AuditOperationType.weeklyForceRefetch:
        return 'weekly_force_refetch';
      case AuditOperationType.weeklyMacdRecompute:
        return 'weekly_macd_recompute';
    }
  }

  static AuditOperationType fromWireName(String value) {
    for (final candidate in AuditOperationType.values) {
      if (candidate.wireName == value) {
        return candidate;
      }
    }
    throw ArgumentError('Unsupported audit operation wire name: $value');
  }
}
