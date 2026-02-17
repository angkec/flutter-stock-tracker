import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum DailyKlineSyncMode { incremental, forceFull }

class DailyKlineGlobalCheckpoint {
  const DailyKlineGlobalCheckpoint({
    required this.dateKey,
    required this.mode,
    required this.successAtMs,
  });

  final String dateKey;
  final DailyKlineSyncMode mode;
  final int successAtMs;
}

class DailyKlineCheckpointStore {
  static const String _lastDateKey = 'daily_kline_checkpoint_last_success_date';
  static const String _lastModeKey = 'daily_kline_checkpoint_last_mode';
  static const String _lastSuccessAtMsKey =
      'daily_kline_checkpoint_last_success_at_ms';
  static const String _perStockSuccessAtMsKey =
      'daily_kline_checkpoint_per_stock_last_success_at_ms';

  Future<void> saveGlobal({
    required String dateKey,
    required DailyKlineSyncMode mode,
    required int successAtMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastDateKey, dateKey);
    await prefs.setString(_lastModeKey, mode.name);
    await prefs.setInt(_lastSuccessAtMsKey, successAtMs);
  }

  Future<DailyKlineGlobalCheckpoint?> loadGlobal() async {
    final prefs = await SharedPreferences.getInstance();
    final dateKey = prefs.getString(_lastDateKey);
    final modeName = prefs.getString(_lastModeKey);
    final successAtMs = prefs.getInt(_lastSuccessAtMsKey);

    if (dateKey == null || modeName == null || successAtMs == null) {
      return null;
    }

    final mode = DailyKlineSyncMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => DailyKlineSyncMode.incremental,
    );

    return DailyKlineGlobalCheckpoint(
      dateKey: dateKey,
      mode: mode,
      successAtMs: successAtMs,
    );
  }

  Future<void> savePerStockSuccessAtMs(Map<String, int> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_perStockSuccessAtMsKey, jsonEncode(value));
  }

  Future<Map<String, int>> loadPerStockSuccessAtMs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_perStockSuccessAtMsKey);
    if (raw == null || raw.isEmpty) {
      return const <String, int>{};
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, (value as num).toInt()));
  }
}
