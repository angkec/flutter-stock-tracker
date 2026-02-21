import 'package:shared_preferences/shared_preferences.dart';

typedef RemoteTradingCalendarFetcher = Future<Map<String, dynamic>> Function();
typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

class ChinaTradingCalendarService {
  const ChinaTradingCalendarService({
    Set<String>? officialClosedDates,
    RemoteTradingCalendarFetcher? remoteFetcher,
    DateTime Function()? nowProvider,
    SharedPreferencesLoader? preferencesLoader,
  }) : _officialClosedDates =
           officialClosedDates ?? _defaultOfficialClosedDates,
       _remoteFetcher = remoteFetcher,
       _nowProvider = nowProvider,
       _preferencesLoader = preferencesLoader;

  final Set<String> _officialClosedDates;
  final RemoteTradingCalendarFetcher? _remoteFetcher;
  final DateTime Function()? _nowProvider;
  final SharedPreferencesLoader? _preferencesLoader;

  static final Expando<_RemoteCalendarState> _stateByInstance =
      Expando<_RemoteCalendarState>();

  static const String _cacheClosedDatesKey =
      'china_trading_calendar.remote_closed_dates';
  static const String _cacheOpenDatesKey =
      'china_trading_calendar.remote_open_dates';
  static const String _cacheUpdatedAtKey =
      'china_trading_calendar.remote_updated_at';

  static const Set<String> _defaultOfficialClosedDates = {
    // 2025
    '2025-01-01',
    '2025-01-28',
    '2025-01-29',
    '2025-01-30',
    '2025-01-31',
    '2025-02-03',
    '2025-02-04',
    '2025-04-04',
    '2025-05-01',
    '2025-05-02',
    '2025-05-05',
    '2025-06-02',
    '2025-10-01',
    '2025-10-02',
    '2025-10-03',
    '2025-10-06',
    '2025-10-07',
    '2025-10-08',
    // 2026
    '2026-01-01',
    '2026-02-16',
    '2026-02-17',
    '2026-02-18',
    '2026-02-19',
    '2026-02-20',
    '2026-04-06',
    '2026-05-01',
    '2026-05-04',
    '2026-05-05',
    '2026-06-22',
    '2026-10-01',
    '2026-10-02',
    '2026-10-05',
    '2026-10-06',
    '2026-10-07',
    '2026-10-08',
    // 2027
    '2027-01-01',
    '2027-02-08',
    '2027-02-09',
    '2027-02-10',
    '2027-02-11',
    '2027-02-12',
    '2027-04-05',
    '2027-05-03',
    '2027-05-04',
    '2027-05-05',
    '2027-06-14',
    '2027-09-24',
    '2027-10-01',
    '2027-10-04',
    '2027-10-05',
    '2027-10-06',
    '2027-10-07',
  };

  bool isTradingDay(DateTime day, {Iterable<DateTime>? inferredTradingDates}) {
    final normalizedDay = _normalize(day);
    final dayKey = _dateKey(normalizedDay);

    if (inferredTradingDates != null) {
      for (final inferred in inferredTradingDates) {
        if (_normalize(inferred) == normalizedDay) {
          return true;
        }
      }
    }

    if (_state.remoteOpenDates.contains(dayKey)) {
      return true;
    }

    if (normalizedDay.weekday == DateTime.saturday ||
        normalizedDay.weekday == DateTime.sunday) {
      return false;
    }

    if (_state.remoteClosedDates.contains(dayKey)) {
      return false;
    }

    return !_officialClosedDates.contains(dayKey);
  }

  Future<bool> refreshRemoteCalendar() async {
    final fetcher = _remoteFetcher;
    if (fetcher == null) {
      return false;
    }

    try {
      final payload = await fetcher();
      final closedDates = _parseDateKeys(
        payload['closedDates'] ?? payload['holidays'],
      );
      final openDates = _parseDateKeys(payload['openDates']);
      _applyRemoteDates(closedDates: closedDates, openDates: openDates);
      await _persistRemoteDates(closedDates: closedDates, openDates: openDates);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> loadCachedCalendar() async {
    final prefs = await _getPreferences();
    final closedDates = prefs.getStringList(_cacheClosedDatesKey);
    final openDates = prefs.getStringList(_cacheOpenDatesKey);

    if ((closedDates == null || closedDates.isEmpty) &&
        (openDates == null || openDates.isEmpty)) {
      return false;
    }

    _applyRemoteDates(
      closedDates: closedDates?.toSet() ?? const <String>{},
      openDates: openDates?.toSet() ?? const <String>{},
    );
    return true;
  }

  bool isNonTradingRange(
    DateTime startDay,
    DateTime endDay, {
    Iterable<DateTime>? inferredTradingDates,
  }) {
    if (startDay.isAfter(endDay)) {
      return false;
    }

    var cursor = _normalize(startDay);
    final normalizedEnd = _normalize(endDay);
    while (!cursor.isAfter(normalizedEnd)) {
      if (isTradingDay(cursor, inferredTradingDates: inferredTradingDates)) {
        return false;
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    return true;
  }

  DateTime? latestTradingDayOnOrBefore(
    DateTime anchorDay, {
    Iterable<DateTime>? availableTradingDates,
    bool includeAnchor = false,
    int maxLookbackDays = 40,
  }) {
    final normalizedAnchor = _normalize(anchorDay);
    final available = availableTradingDates?.map(_normalize).toSet();

    var cursor = includeAnchor
        ? normalizedAnchor
        : normalizedAnchor.subtract(const Duration(days: 1));

    for (var i = 0; i < maxLookbackDays; i++) {
      if (available != null && available.isNotEmpty) {
        if (available.contains(cursor)) {
          return cursor;
        }
      } else if (isTradingDay(cursor)) {
        return cursor;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }

    if (available != null && available.isNotEmpty) {
      DateTime? best;
      for (final day in available) {
        if (day.isAfter(normalizedAnchor)) {
          continue;
        }
        if (best == null || day.isAfter(best)) {
          best = day;
        }
      }
      return best;
    }

    return null;
  }

  static DateTime _normalize(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  static String _dateKey(DateTime day) {
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$year-$month-$date';
  }

  void _applyRemoteDates({
    required Set<String> closedDates,
    required Set<String> openDates,
  }) {
    _state.remoteClosedDates
      ..clear()
      ..addAll(closedDates);
    _state.remoteOpenDates
      ..clear()
      ..addAll(openDates);
  }

  _RemoteCalendarState get _state {
    return _stateByInstance[this] ??= _RemoteCalendarState();
  }

  Set<String> _parseDateKeys(dynamic raw) {
    if (raw is! Iterable) {
      return <String>{};
    }

    final result = <String>{};
    for (final value in raw) {
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          result.add(_dateKey(_normalize(parsed)));
        }
      } else if (value is DateTime) {
        result.add(_dateKey(_normalize(value)));
      }
    }
    return result;
  }

  Future<void> _persistRemoteDates({
    required Set<String> closedDates,
    required Set<String> openDates,
  }) async {
    final prefs = await _getPreferences();
    final sortedClosed = closedDates.toList()..sort();
    final sortedOpen = openDates.toList()..sort();
    await prefs.setStringList(_cacheClosedDatesKey, sortedClosed);
    await prefs.setStringList(_cacheOpenDatesKey, sortedOpen);
    await prefs.setString(_cacheUpdatedAtKey, _resolveNow().toIso8601String());
  }

  Future<SharedPreferences> _getPreferences() {
    final loader = _preferencesLoader;
    if (loader != null) {
      return loader();
    }
    return SharedPreferences.getInstance();
  }

  DateTime _resolveNow() {
    final nowProvider = _nowProvider;
    if (nowProvider != null) {
      return nowProvider();
    }
    return DateTime.now();
  }
}

class _RemoteCalendarState {
  final Set<String> remoteClosedDates = <String>{};
  final Set<String> remoteOpenDates = <String>{};
}
