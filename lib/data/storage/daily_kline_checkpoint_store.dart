import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';

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
  DailyKlineCheckpointStore({KLineFileStorage? storage})
    : _storage = storage ?? KLineFileStorage();

  final KLineFileStorage _storage;

  static const String _lastDateKey = 'daily_kline_checkpoint_last_success_date';
  static const String _lastModeKey = 'daily_kline_checkpoint_last_mode';
  static const String _lastSuccessAtMsKey =
      'daily_kline_checkpoint_last_success_at_ms';
  static const String _perStockSuccessAtMsKey =
      'daily_kline_checkpoint_per_stock_last_success_at_ms';
  static const String _perStockCheckpointDirectory = 'checkpoints';
  static const String _perStockCheckpointFileName =
      'daily_kline_per_stock_success_v1.json';

  bool _initialized = false;
  String? _checkpointDirectoryPath;

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
    final file = await _resolvePerStockCheckpointFile();
    final tempFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tempFile.writeAsString(jsonEncode(value), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);

    final prefs = await SharedPreferences.getInstance();
    // Drop legacy SharedPreferences payload to avoid large SP JSON writes.
    await prefs.remove(_perStockSuccessAtMsKey);
  }

  Future<Map<String, int>> loadPerStockSuccessAtMs() async {
    final file = await _resolvePerStockCheckpointFile();
    if (await file.exists()) {
      final rawFromFile = await file.readAsString();
      if (rawFromFile.trim().isNotEmpty) {
        final decoded = jsonDecode(rawFromFile) as Map<String, dynamic>;
        return decoded.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
      }
    }

    // Legacy fallback: migrate old SharedPreferences payload into file store.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_perStockSuccessAtMsKey);
    if (raw == null || raw.isEmpty) {
      return const <String, int>{};
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final migrated = decoded.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );
    await savePerStockSuccessAtMs(migrated);
    return migrated;
  }

  Future<File> _resolvePerStockCheckpointFile() async {
    await _initialize();
    return File('$_checkpointDirectoryPath/$_perStockCheckpointFileName');
  }

  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }

    String basePath;
    try {
      await _storage.initialize();
      basePath = await _storage.getBaseDirectoryPath();
    } catch (_) {
      basePath = '${Directory.systemTemp.path}/stock_rtwatcher_market_data';
      final fallbackDir = Directory(basePath);
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
    }

    final checkpointDirectory = Directory(
      '$basePath/$_perStockCheckpointDirectory',
    );
    if (!await checkpointDirectory.exists()) {
      await checkpointDirectory.create(recursive: true);
    }
    _checkpointDirectoryPath = checkpointDirectory.path;
    _initialized = true;
  }
}
