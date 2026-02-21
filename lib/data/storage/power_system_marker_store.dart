import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stock_rtwatcher/data/storage/atomic_file_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/models/power_system_point.dart';

class PowerSystemMarkerData {
  final String stockCode;
  final bool isPowerSystemUp;
  final List<PowerSystemDayState> states;
  final DateTime updatedAt;

  PowerSystemMarkerData({
    required this.stockCode,
    required this.isPowerSystemUp,
    required this.states,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'stockCode': stockCode,
    'isPowerSystemUp': isPowerSystemUp,
    'states': states
        .map(
          (state) => {
            'state': state.state.index,
            'date': state.date.toIso8601String(),
            'dailyState': state.dailyState,
            'weeklyState': state.weeklyState,
          },
        )
        .toList(growable: false),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PowerSystemMarkerData.fromJson(Map<String, dynamic> json) {
    final statesJson = (json['states'] as List<dynamic>?) ?? const <dynamic>[];
    final states = statesJson
        .whereType<Map<String, dynamic>>()
        .map(
          (stateJson) => PowerSystemDayState(
            state:
                PowerSystemDailyState.values[(stateJson['state'] as int?) ?? 0],
            date: DateTime.parse(stateJson['date'] as String),
            dailyState: stateJson['dailyState'] as int,
            weeklyState: stateJson['weeklyState'] as int,
          ),
        )
        .toList(growable: false);

    return PowerSystemMarkerData(
      stockCode: json['stockCode'] as String,
      isPowerSystemUp: json['isPowerSystemUp'] as bool? ?? false,
      states: states,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }
}

class PowerSystemMarkerStore {
  PowerSystemMarkerStore({
    KLineFileStorage? storage,
    AtomicFileWriter? atomicWriter,
    this.defaultMaxConcurrentWrites = 6,
  }) : _storage = storage ?? KLineFileStorage(),
       _atomicWriter = atomicWriter ?? const AtomicFileWriter();

  final KLineFileStorage _storage;
  final AtomicFileWriter _atomicWriter;
  final int defaultMaxConcurrentWrites;

  static const String _cacheSubDir = 'power_system_marker';

  bool _initialized = false;
  String? _cacheDirectoryPath;

  Future<void> initialize() async {
    if (_initialized) return;

    await _storage.initialize();
    final basePath = await _storage.getBaseDirectoryPath();
    final dir = Directory('$basePath/$_cacheSubDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _cacheDirectoryPath = dir.path;
    _initialized = true;
  }

  Future<void> saveMarker(PowerSystemMarkerData marker) async {
    await saveAll([marker]);
  }

  Future<void> saveAll(
    List<PowerSystemMarkerData> items, {
    int? maxConcurrentWrites,
    void Function(int current, int total)? onProgress,
  }) async {
    if (items.isEmpty) return;
    await initialize();

    final total = items.length;
    final workerCount = min(
      max(1, maxConcurrentWrites ?? defaultMaxConcurrentWrites),
      total,
    );

    var nextIndex = 0;
    var completed = 0;

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        if (index >= total) {
          return;
        }
        nextIndex++;

        await _saveSingle(items[index]);

        completed++;
        onProgress?.call(completed, total);
      }
    }

    await Future.wait(
      List.generate(workerCount, (_) => runWorker(), growable: false),
    );
  }

  Future<PowerSystemMarkerData?> loadMarker(String stockCode) async {
    await initialize();

    final file = File(await _cacheFilePath(stockCode));
    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return PowerSystemMarkerData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<List<PowerSystemMarkerData>> loadAll() async {
    await initialize();

    final dir = Directory(_cacheDirectoryPath!);
    if (!await dir.exists()) {
      return const <PowerSystemMarkerData>[];
    }

    final result = <PowerSystemMarkerData>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }

      try {
        final content = await entity.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        result.add(PowerSystemMarkerData.fromJson(json));
      } catch (_) {
        continue;
      }
    }

    return result;
  }

  Future<void> _saveSingle(PowerSystemMarkerData marker) async {
    final file = File(await _cacheFilePath(marker.stockCode));
    await _atomicWriter.writeAtomic(
      targetFile: file,
      content: utf8.encode(jsonEncode(marker.toJson())),
    );
  }

  Future<String> _cacheFilePath(String stockCode) async {
    await initialize();
    return '$_cacheDirectoryPath/$stockCode.json';
  }
}
