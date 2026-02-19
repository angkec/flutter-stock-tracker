# Daily Monthly V2 Storage + Parallel Persist Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Speed up daily monthly archive writes by combining parallel persist with a new binary + fast-compression format, and update all daily read paths accordingly.

**Architecture:** Introduce a v2 monthly storage format (binary records + fast zlib compression) alongside a monthly-storage interface. Use the v2 storage only for daily data types, while keeping existing v1 storage for other data types. Parallelize daily monthly persist with a worker pool and keep metadata updates consistent.

**Tech Stack:** Flutter/Dart, `archive` (zlib), `sqflite`, `path_provider`, existing storage + metadata layers.

---

### Task 1: Define a Monthly Storage Interface (no behavior change)

**Files:**
- Create: `lib/data/storage/kline_monthly_storage.dart`
- Modify: `lib/data/storage/kline_file_storage.dart`
- Test: `test/data/storage/kline_monthly_storage_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/kline_monthly_storage.dart';

void main() {
  test('KLineFileStorage implements KLineMonthlyStorage', () {
    final storage = KLineFileStorage();
    expect(storage, isA<KLineMonthlyStorage>());
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/kline_monthly_storage_test.dart -r compact`
Expected: FAIL (type not found or interface not implemented).

**Step 3: Write minimal implementation**

```dart
// lib/data/storage/kline_monthly_storage.dart
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';

abstract class KLineMonthlyStorage {
  Future<void> initialize();
  void setBaseDirPathForTesting(String path);
  Future<String> getBaseDirectoryPath();
  Future<String> getFilePathAsync(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  );
  Future<List<KLine>> loadMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  );
  Future<void> saveMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> klines,
  );
  Future<KLineAppendResult?> appendKlineData(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> newKlines,
  );
  Future<void> deleteMonthlyFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  );
}
```

```dart
// lib/data/storage/kline_file_storage.dart
class KLineFileStorage implements KLineMonthlyStorage {
  // no behavior change, just implements the interface
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/kline_monthly_storage_test.dart -r compact`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/data/storage/kline_monthly_storage.dart lib/data/storage/kline_file_storage.dart test/data/storage/kline_monthly_storage_test.dart
git commit -m "chore: add monthly storage interface"
```

### Task 2: Add Binary + Fast-Zlib Codec (v2)

**Files:**
- Create: `lib/data/storage/kline_codec.dart`
- Test: `test/data/storage/kline_codec_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_codec.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  test('BinaryKLineCodec roundtrip preserves data', () {
    final codec = BinaryKLineCodec();
    final source = [
      KLine(
        datetime: DateTime(2026, 2, 18),
        open: 10.1,
        close: 11.2,
        high: 11.8,
        low: 9.9,
        volume: 12345,
        amount: 98765,
      ),
      KLine(
        datetime: DateTime(2026, 2, 19),
        open: 11.2,
        close: 10.8,
        high: 11.4,
        low: 10.3,
        volume: 54321,
        amount: 45678,
      ),
    ];

    final encoded = codec.encode(source);
    final decoded = codec.decode(encoded);

    expect(decoded.length, source.length);
    expect(decoded.first.datetime, source.first.datetime);
    expect(decoded.first.open, source.first.open);
    expect(decoded.last.amount, source.last.amount);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/kline_codec_test.dart -r compact`
Expected: FAIL (BinaryKLineCodec missing).

**Step 3: Write minimal implementation**

```dart
// lib/data/storage/kline_codec.dart
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class BinaryKLineCodec {
  static const int _recordSize = 8 + 8 + 8 + 8 + 8 + 8 + 8; // 7 x 8-byte

  Uint8List encode(List<KLine> klines) {
    final raw = _serialize(klines);
    final encoder = ZLibEncoder(level: 1);
    final compressed = encoder.encode(raw);
    return Uint8List.fromList(compressed!);
  }

  List<KLine> decode(Uint8List bytes) {
    final decoder = ZLibDecoder();
    final raw = decoder.decodeBytes(bytes);
    return _deserialize(Uint8List.fromList(raw));
  }

  Uint8List _serialize(List<KLine> klines) {
    final buffer = BytesBuilder();
    for (final k in klines) {
      final data = ByteData(_recordSize);
      var offset = 0;
      data.setInt64(offset, k.datetime.millisecondsSinceEpoch); offset += 8;
      data.setFloat64(offset, k.open); offset += 8;
      data.setFloat64(offset, k.close); offset += 8;
      data.setFloat64(offset, k.high); offset += 8;
      data.setFloat64(offset, k.low); offset += 8;
      data.setFloat64(offset, k.volume); offset += 8;
      data.setFloat64(offset, k.amount); offset += 8;
      buffer.add(data.buffer.asUint8List());
    }
    return buffer.toBytes();
  }

  List<KLine> _deserialize(Uint8List raw) {
    if (raw.isEmpty) return <KLine>[];
    final result = <KLine>[];
    final data = ByteData.sublistView(raw);
    for (var offset = 0; offset + _recordSize <= data.lengthInBytes; offset += _recordSize) {
      final ts = data.getInt64(offset); offset += 8;
      final open = data.getFloat64(offset); offset += 8;
      final close = data.getFloat64(offset); offset += 8;
      final high = data.getFloat64(offset); offset += 8;
      final low = data.getFloat64(offset); offset += 8;
      final volume = data.getFloat64(offset); offset += 8;
      final amount = data.getFloat64(offset); offset += 8;
      result.add(KLine(
        datetime: DateTime.fromMillisecondsSinceEpoch(ts),
        open: open,
        close: close,
        high: high,
        low: low,
        volume: volume,
        amount: amount,
      ));
    }
    return result;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/kline_codec_test.dart -r compact`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/data/storage/kline_codec.dart test/data/storage/kline_codec_test.dart
git commit -m "feat: add binary kline codec with fast zlib"
```

### Task 3: Add V2 Monthly Storage (binary + zlib)

**Files:**
- Create: `lib/data/storage/kline_file_storage_v2.dart`
- Modify: `lib/data/storage/kline_file_storage.dart` (reuse merge helpers or extract)
- Test: `test/data/storage/kline_file_storage_v2_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  test('KLineFileStorageV2 save/load roundtrip', () async {
    final dir = await Directory.systemTemp.createTemp('kline_v2_');
    final storage = KLineFileStorageV2()..setBaseDirPathForTesting(dir.path);

    final bars = [
      KLine(
        datetime: DateTime(2026, 2, 18),
        open: 10,
        close: 11,
        high: 11.5,
        low: 9.5,
        volume: 100,
        amount: 200,
      ),
    ];

    await storage.saveMonthlyKlineFile('000001', KLineDataType.daily, 2026, 2, bars);
    final loaded = await storage.loadMonthlyKlineFile('000001', KLineDataType.daily, 2026, 2);

    expect(loaded.length, 1);
    expect(loaded.first.close, 11);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/kline_file_storage_v2_test.dart -r compact`
Expected: FAIL (class not found).

**Step 3: Write minimal implementation**

```dart
// lib/data/storage/kline_file_storage_v2.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_codec.dart';
import 'package:stock_rtwatcher/data/storage/kline_monthly_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class KLineFileStorageV2 implements KLineMonthlyStorage {
  static const String _baseDir = 'market_data/klines_v2';
  final BinaryKLineCodec _codec = BinaryKLineCodec();
  String? _baseDirPath;
  String? _resolvedBaseDirectory;

  @override
  void setBaseDirPathForTesting(String path) {
    _baseDirPath = path;
    _resolvedBaseDirectory = path;
  }

  Future<String> _getBaseDirectory() async {
    if (_resolvedBaseDirectory != null) return _resolvedBaseDirectory!;
    if (_baseDirPath != null) {
      _resolvedBaseDirectory = _baseDirPath!;
      return _resolvedBaseDirectory!;
    }
    final appDocsDir = await getApplicationDocumentsDirectory();
    _resolvedBaseDirectory = '${appDocsDir.path}/$_baseDir';
    return _resolvedBaseDirectory!;
  }

  @override
  Future<void> initialize() async {
    final base = await _getBaseDirectory();
    final dir = Directory(base);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<String> getBaseDirectoryPath() async => _getBaseDirectory();

  @override
  Future<String> getFilePathAsync(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final base = await _getBaseDirectory();
    final yearMonth = '$year${month.toString().padLeft(2, '0')}';
    final fileName = '${stockCode}_${dataType.name}_$yearMonth.bin.zlib';
    return '$base/$fileName';
  }

  @override
  Future<List<KLine>> loadMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final path = await getFilePathAsync(stockCode, dataType, year, month);
    final file = File(path);
    if (!await file.exists()) return [];
    final bytes = await file.readAsBytes();
    return _codec.decode(bytes);
  }

  @override
  Future<void> saveMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> klines,
  ) async {
    if (klines.isEmpty) return;
    await initialize();
    final path = await getFilePathAsync(stockCode, dataType, year, month);
    final tempPath = '$path.${DateTime.now().microsecondsSinceEpoch}.tmp';
    final tempFile = File(tempPath);
    final encoded = _codec.encode(klines);
    await tempFile.writeAsBytes(encoded, flush: true);
    await tempFile.rename(path);
  }

  @override
  Future<KLineAppendResult?> appendKlineData(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> newKlines,
  ) async {
    if (newKlines.isEmpty) return null;
    final existing = await loadMonthlyKlineFile(stockCode, dataType, year, month);
    final merged = _mergeAndDeduplicate(existing, newKlines);
    final path = await getFilePathAsync(stockCode, dataType, year, month);
    if (merged.changed) {
      await saveMonthlyKlineFile(stockCode, dataType, year, month, merged.merged);
    }
    final file = File(path);
    final size = await file.length();
    return KLineAppendResult(
      changed: merged.changed,
      startDate: merged.merged.isEmpty ? null : merged.merged.first.datetime,
      endDate: merged.merged.isEmpty ? null : merged.merged.last.datetime,
      recordCount: merged.merged.length,
      filePath: path,
      fileSize: size,
    );
  }

  @override
  Future<void> deleteMonthlyFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  ) async {
    final path = await getFilePathAsync(stockCode, dataType, year, month);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  _KLineMergeResult _mergeAndDeduplicate(List<KLine> existing, List<KLine> incoming) {
    // copy the same merge logic from KLineFileStorage or extract shared helper
    // minimal code: ensure sorted + merge like v1
    throw UnimplementedError();
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/kline_file_storage_v2_test.dart -r compact`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/data/storage/kline_file_storage_v2.dart test/data/storage/kline_file_storage_v2_test.dart lib/data/storage/kline_file_storage.dart
git commit -m "feat: add v2 monthly storage with binary + zlib"
```

### Task 4: Route Daily DataType to V2 Storage in Metadata Manager

**Files:**
- Modify: `lib/data/storage/kline_metadata_manager.dart`
- Modify: `lib/data/storage/daily_kline_monthly_writer.dart`
- Test: `test/data/monthly_daily_storage_readback_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  test('daily metadata manager uses v2 file paths', () async {
    final v2 = KLineFileStorageV2()..setBaseDirPathForTesting('v2');
    final manager = KLineMetadataManager(dailyFileStorage: v2);

    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [
        KLine(
          datetime: DateTime(2026, 2, 18),
          open: 10,
          close: 11,
          high: 12,
          low: 9,
          volume: 100,
          amount: 200,
        ),
      ],
      dataType: KLineDataType.daily,
    );

    final meta = await manager.getMetadata(
      stockCode: '000001',
      dataType: KLineDataType.daily,
    );
    expect(meta.first.filePath.contains('klines_v2'), isTrue);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/monthly_daily_storage_readback_test.dart -r compact`
Expected: FAIL (manager not routing to v2 storage).

**Step 3: Write minimal implementation**

```dart
// lib/data/storage/kline_metadata_manager.dart
class KLineMetadataManager {
  final KLineMonthlyStorage _fileStorage;
  final KLineMonthlyStorage? _dailyFileStorage;

  KLineMetadataManager({
    MarketDatabase? database,
    KLineMonthlyStorage? fileStorage,
    KLineMonthlyStorage? dailyFileStorage,
  }) : _db = database ?? MarketDatabase(),
       _fileStorage = fileStorage ?? KLineFileStorage(),
       _dailyFileStorage = dailyFileStorage;

  KLineMonthlyStorage _resolveStorage(KLineDataType dataType) {
    if (dataType == KLineDataType.daily && _dailyFileStorage != null) {
      return _dailyFileStorage!;
    }
    return _fileStorage;
  }

  Future<void> saveKlineData({
    required String stockCode,
    required List<KLine> newBars,
    required KLineDataType dataType,
    bool bumpVersion = true,
  }) async {
    final storage = _resolveStorage(dataType);
    // use storage for append/load/delete operations
  }
}
```

```dart
// lib/data/storage/daily_kline_monthly_writer.dart
class DailyKlineMonthlyWriterImpl {
  DailyKlineMonthlyWriterImpl({KLineMetadataManager? manager})
    : _manager = manager ?? KLineMetadataManager(dailyFileStorage: KLineFileStorageV2());
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/monthly_daily_storage_readback_test.dart -r compact`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/data/storage/kline_metadata_manager.dart lib/data/storage/daily_kline_monthly_writer.dart test/data/monthly_daily_storage_readback_test.dart

git commit -m "feat: route daily metadata to v2 storage"
```

### Task 5: Parallelize Daily Monthly Persist

**Files:**
- Modify: `lib/data/storage/daily_kline_monthly_writer.dart`
- Test: `test/data/storage/daily_kline_monthly_writer_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_monthly_writer.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/models/kline.dart';

void main() {
  test('daily monthly writer supports maxConcurrentWrites', () async {
    final writer = DailyKlineMonthlyWriterImpl(
      maxConcurrentWrites: 4,
      manager: KLineMetadataManager(),
    );

    final payload = <String, List<KLine>>{
      '000001': [
        KLine(
          datetime: DateTime(2026, 2, 18),
          open: 10,
          close: 11,
          high: 12,
          low: 9,
          volume: 100,
          amount: 200,
        ),
      ],
    };

    await writer(payload);
    expect(true, isTrue);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/daily_kline_monthly_writer_test.dart -r compact`
Expected: FAIL (constructor params not supported).

**Step 3: Write minimal implementation**

```dart
// lib/data/storage/daily_kline_monthly_writer.dart
class DailyKlineMonthlyWriterImpl {
  DailyKlineMonthlyWriterImpl({
    KLineMetadataManager? manager,
    this.maxConcurrentWrites = 6,
  }) : _manager = manager ?? KLineMetadataManager(dailyFileStorage: KLineFileStorageV2());

  final KLineMetadataManager _manager;
  final int maxConcurrentWrites;

  Future<void> call(
    Map<String, List<KLine>> barsByStock, {
    void Function(int current, int total)? onProgress,
  }) async {
    final entries = barsByStock.entries.where((e) => e.value.isNotEmpty).toList(growable: false);
    final total = entries.length;
    var completed = 0;

    final workerCount = total == 0 ? 0 : maxConcurrentWrites.clamp(1, total);
    var nextIndex = 0;

    Future<void> runWorker() async {
      while (true) {
        final idx = nextIndex;
        if (idx >= entries.length) return;
        nextIndex++;
        final entry = entries[idx];
        await _manager.saveKlineData(
          stockCode: entry.key,
          newBars: entry.value,
          dataType: KLineDataType.daily,
          bumpVersion: false,
        );
        completed++;
        onProgress?.call(completed, total);
      }
    }

    await Future.wait(List.generate(workerCount, (_) => runWorker()));
    if (total > 0) {
      await _manager.incrementDataVersion('Daily sync monthly persist');
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/daily_kline_monthly_writer_test.dart -r compact`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/data/storage/daily_kline_monthly_writer.dart test/data/storage/daily_kline_monthly_writer_test.dart

git commit -m "feat: parallelize daily monthly persist"
```

### Task 6: Update Daily Cache Fallback to V2 Monthly Storage

**Files:**
- Modify: `lib/data/storage/daily_kline_cache_store.dart`
- Modify: `lib/main.dart`
- Test: `test/data/storage/daily_kline_cache_store_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';

void main() {
  test('daily cache uses v2 monthly storage fallback', () async {
    final cache = DailyKlineCacheStore(monthlyStorage: KLineFileStorageV2());
    expect(cache.monthlyStorage, isA<KLineFileStorageV2>());
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/daily_kline_cache_store_test.dart -r compact`
Expected: FAIL (no monthlyStorage parameter).

**Step 3: Write minimal implementation**

```dart
// lib/data/storage/daily_kline_cache_store.dart
class DailyKlineCacheStore {
  DailyKlineCacheStore({
    KLineFileStorage? storage,
    KLineMonthlyStorage? monthlyStorage,
    AtomicFileWriter? atomicWriter,
    this.defaultTargetBars = 260,
    this.defaultLookbackMonths = 18,
    this.defaultMaxConcurrentWrites = 8,
  }) : _storage = storage ?? KLineFileStorage(),
       _monthlyStorage = monthlyStorage ?? KLineFileStorageV2(),
       _atomicWriter = atomicWriter ?? const AtomicFileWriter();

  final KLineFileStorage _storage;
  final KLineMonthlyStorage _monthlyStorage;
  KLineMonthlyStorage get monthlyStorage => _monthlyStorage;
}
```

```dart
// replace _storage.loadMonthlyKlineFile(...) with _monthlyStorage.loadMonthlyKlineFile(...)
```

```dart
// lib/main.dart
Provider(create: (_) => DailyKlineCacheStore(monthlyStorage: KLineFileStorageV2())),
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/daily_kline_cache_store_test.dart -r compact`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/data/storage/daily_kline_cache_store.dart lib/main.dart test/data/storage/daily_kline_cache_store_test.dart

git commit -m "feat: use v2 storage for daily monthly fallback"
```

### Task 7: Update Benchmarks and Readback Tests

**Files:**
- Modify: `test/data/monthly_daily_storage_readback_test.dart`
- Modify: `test/integration/daily_kline_write_benchmark_test.dart`
- Modify: `test/integration/daily_kline_refetch_performance_e2e_test.dart`

**Step 1: Write the failing test**

```dart
// Update tests to construct KLineMetadataManager(dailyFileStorage: KLineFileStorageV2())
// and assert v2 file suffix .bin.zlib in file paths.
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/monthly_daily_storage_readback_test.dart -r compact`
Expected: FAIL (old file extension or storage path).

**Step 3: Write minimal implementation**

```dart
// Example update in tests
manager = KLineMetadataManager(
  dailyFileStorage: KLineFileStorageV2()..setBaseDirPathForTesting(tempDir.path),
);
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/monthly_daily_storage_readback_test.dart -r compact`
Expected: PASS

**Step 5: Commit**

```bash
git add test/data/monthly_daily_storage_readback_test.dart test/integration/daily_kline_write_benchmark_test.dart test/integration/daily_kline_refetch_performance_e2e_test.dart

git commit -m "test: migrate daily monthly readback to v2"
```

### Task 8: Verification and Performance Check

**Files:**
- No code changes required.

**Step 1: Run focused tests**

Run:
- `flutter test test/data/storage/kline_codec_test.dart -r compact`
- `flutter test test/data/storage/kline_file_storage_v2_test.dart -r compact`
- `flutter test test/data/storage/daily_kline_cache_store_test.dart -r compact`
- `flutter test test/data/monthly_daily_storage_readback_test.dart -r compact`

Expected: PASS

**Step 2: Run integration perf smoke**

Run:
- `flutter test test/integration/daily_kline_write_benchmark_test.dart -r compact`

Expected: PASS and log shows improved monthly persist time vs baseline.

**Step 3: Commit perf notes**

```bash
git add docs/reports/2026-02-19-daily-monthly-v2-perf.md
git commit -m "docs: record daily monthly v2 perf"
```

---

**Expected speedup (vs ~5 min baseline)**
- Parallel persist: 1.5–3x
- Binary + fast zlib: 2–3x
- Combined: 3–6x (target 50–100s on Dimensity 9300 class devices)

---

**Notes**
- Execution should happen in a worktree per @superpowers:using-git-worktrees.
- Implementation must follow @superpowers:executing-plans.

