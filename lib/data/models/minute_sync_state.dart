class MinuteSyncState {
  final String stockCode;
  final DateTime? lastCompleteTradingDay;
  final DateTime? lastSuccessFetchAt;
  final DateTime? lastAttemptAt;
  final int consecutiveFailures;
  final String? lastError;
  final DateTime updatedAt;

  const MinuteSyncState({
    required this.stockCode,
    this.lastCompleteTradingDay,
    this.lastSuccessFetchAt,
    this.lastAttemptAt,
    this.consecutiveFailures = 0,
    this.lastError,
    required this.updatedAt,
  });

  factory MinuteSyncState.fromMap(Map<String, dynamic> map) {
    return MinuteSyncState(
      stockCode: map['stock_code'] as String,
      lastCompleteTradingDay: _dateTimeFromMap(
        map,
        'last_complete_trading_day',
      ),
      lastSuccessFetchAt: _dateTimeFromMap(map, 'last_success_fetch_at'),
      lastAttemptAt: _dateTimeFromMap(map, 'last_attempt_at'),
      consecutiveFailures: (map['consecutive_failures'] as int?) ?? 0,
      lastError: map['last_error'] as String?,
      updatedAt:
          _dateTimeFromMap(map, 'updated_at') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stock_code': stockCode,
      'last_complete_trading_day':
          lastCompleteTradingDay?.millisecondsSinceEpoch,
      'last_success_fetch_at': lastSuccessFetchAt?.millisecondsSinceEpoch,
      'last_attempt_at': lastAttemptAt?.millisecondsSinceEpoch,
      'consecutive_failures': consecutiveFailures,
      'last_error': lastError,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  MinuteSyncState copyWith({
    DateTime? lastCompleteTradingDay,
    DateTime? lastSuccessFetchAt,
    DateTime? lastAttemptAt,
    int? consecutiveFailures,
    String? lastError,
    bool clearLastError = false,
    DateTime? updatedAt,
  }) {
    return MinuteSyncState(
      stockCode: stockCode,
      lastCompleteTradingDay:
          lastCompleteTradingDay ?? this.lastCompleteTradingDay,
      lastSuccessFetchAt: lastSuccessFetchAt ?? this.lastSuccessFetchAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _dateTimeFromMap(Map<String, dynamic> map, String key) {
    final value = map[key] as int?;
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
