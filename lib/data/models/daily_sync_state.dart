class DailySyncState {
  const DailySyncState({
    required this.stockCode,
    this.lastIntradayDate,
    this.lastFinalizedDate,
    this.lastFingerprint,
    required this.updatedAt,
  });

  final String stockCode;
  final DateTime? lastIntradayDate;
  final DateTime? lastFinalizedDate;
  final String? lastFingerprint;
  final DateTime updatedAt;

  factory DailySyncState.fromMap(Map<String, dynamic> map) {
    return DailySyncState(
      stockCode: map['stock_code'] as String,
      lastIntradayDate: _dateTimeFromMap(map, 'last_intraday_date'),
      lastFinalizedDate: _dateTimeFromMap(map, 'last_finalized_date'),
      lastFingerprint: map['last_fingerprint'] as String?,
      updatedAt:
          _dateTimeFromMap(map, 'updated_at') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stock_code': stockCode,
      'last_intraday_date': lastIntradayDate?.millisecondsSinceEpoch,
      'last_finalized_date': lastFinalizedDate?.millisecondsSinceEpoch,
      'last_fingerprint': lastFingerprint,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  DailySyncState copyWith({
    DateTime? lastIntradayDate,
    DateTime? lastFinalizedDate,
    String? lastFingerprint,
    bool clearLastFingerprint = false,
    DateTime? updatedAt,
  }) {
    return DailySyncState(
      stockCode: stockCode,
      lastIntradayDate: lastIntradayDate ?? this.lastIntradayDate,
      lastFinalizedDate: lastFinalizedDate ?? this.lastFinalizedDate,
      lastFingerprint: clearLastFingerprint
          ? null
          : (lastFingerprint ?? this.lastFingerprint),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _dateTimeFromMap(Map<String, dynamic> map, String key) {
    final value = map[key] as int?;
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}
