# Indicator Layer Real E2E Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a full-stock, real-network indicator-layer integration test (MACD/ADX for daily+weekly) that reads the data-layer E2E cache and validates indicator completeness at >=90% OK per validation type.

**Architecture:** Data-layer E2E writes a JSON manifest plus persistent cache root. Indicator-layer E2E reads the manifest, initializes storage to the cache root, runs optimized indicator prewarm paths (daily via prewarmFromBars, weekly via prewarmFromRepository), then validates cached MACD/ADX series against expected point counts derived from bar windows.

**Tech Stack:** Flutter test, Dart, sqflite_common_ffi, stock_rtwatcher data/indicator services.

---

### Task 1: Persist Data-Layer Cache + Emit Manifest

**Files:**
- Modify: `test/integration/data_layer_real_e2e_test.dart`

**Step 1: Add a failing unit test for eligible-stock derivation**

Add a helper test near the existing unit tests:
```dart
  test('deriveEligibleStocks excludes short or errored stocks', () {
    final all = ['000001', '000002', '000003', '000004'];
    final dailyShort = {'000002': 200};
    final weeklyShort = {'000003': 80};
    final dailyErrors = {'000004': 'empty_fetch_result'};
    final weeklyErrors = <String, String>{};

    final eligible = _deriveEligibleStocks(
      allStocks: all,
      dailyShort: dailyShort,
      weeklyShort: weeklyShort,
      dailyErrors: dailyErrors,
      weeklyErrors: weeklyErrors,
    );

    expect(eligible, ['000001']);
  });
```

**Step 2: Run the unit test to confirm it fails**

Run:
```bash
flutter test test/integration/data_layer_real_e2e_test.dart --plain-name "deriveEligibleStocks"
```
Expected: FAIL (function not found)

**Step 3: Implement manifest + persistent cache root**

Add helper:
```dart
List<String> _deriveEligibleStocks({
  required List<String> allStocks,
  required Map<String, int> dailyShort,
  required Map<String, int> weeklyShort,
  required Map<String, String> dailyErrors,
  required Map<String, String> weeklyErrors,
}) {
  final blocked = <String>{
    ...dailyShort.keys,
    ...weeklyShort.keys,
    ...dailyErrors.keys,
    ...weeklyErrors.keys,
  };
  return allStocks.where((code) => !blocked.contains(code)).toList();
}
```

Change cache root to persistent folder and keep it:
```dart
final cacheRoot = Directory(
  p.join(Directory.current.path, 'build', 'real_e2e_cache', dateKey),
);
if (await cacheRoot.exists()) {
  await cacheRoot.delete(recursive: true);
}
await cacheRoot.create(recursive: true);
rootDir = cacheRoot;
```

Compute eligible stocks after validations:
```dart
final eligibleStocks = _deriveEligibleStocks(
  allStocks: stockCodes,
  dailyShort: dailyShort,
  weeklyShort: weeklyShort,
  dailyErrors: {
    ...?allowedErrors['daily'],
    ...?fatalErrors['daily'],
  },
  weeklyErrors: {
    ...?allowedErrors['weekly'],
    ...?fatalErrors['weekly'],
  },
);
```

Write manifest in `finally` (next to report):
```dart
final manifestFile = File(
  p.join(reportDir.path, '${dateKey}-data-layer-real-e2e.json'),
);
final manifest = {
  'date': dateKey,
  'generatedAt': endedAt.toIso8601String(),
  'cacheRoot': rootDir?.path ?? '',
  'fileRoot': fileRoot?.path ?? '',
  'dbRoot': dbRoot?.path ?? '',
  'daily': {
    'anchorDate': _formatDate(anchorDay),
    'targetBars': _dailyTargetBars,
  },
  'weekly': {
    'rangeDays': _weeklyRangeDays,
    'rangeStart': _formatDate(weeklyRange!.start),
    'rangeEnd': _formatDate(weeklyRange!.end),
    'targetBars': _weeklyTargetBars,
  },
  'eligibleStocks': eligibleStocks,
};
await manifestFile.writeAsString(jsonEncode(manifest), flush: true);
```

Remove the cleanup that deletes `rootDir` so the cache persists.

**Step 4: Re-run the unit test**

Run:
```bash
flutter test test/integration/data_layer_real_e2e_test.dart --plain-name "deriveEligibleStocks"
```
Expected: PASS

**Step 5: Commit**

```bash
git add test/integration/data_layer_real_e2e_test.dart
git commit -m "test: persist data layer cache and emit manifest"
```

---

### Task 2: Add Indicator-Layer Real E2E Test

**Files:**
- Create: `test/integration/indicator_layer_real_e2e_test.dart`

**Step 1: Write failing unit tests for expected point counts**

Create file with only helper tests first:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';

int _expectedAdxPoints(int barsLength, int period) => throw UnimplementedError();
int _expectedMacdPoints(List<KLine> bars, int windowMonths) => throw UnimplementedError();

void main() {
  test('expectedAdxPoints matches algorithm length', () {
    expect(_expectedAdxPoints(27, 14), 0);
    expect(_expectedAdxPoints(28, 14), 1);
    expect(_expectedAdxPoints(29, 14), 2);
  });
}
```

**Step 2: Run unit test to confirm failure**

```bash
flutter test test/integration/indicator_layer_real_e2e_test.dart --plain-name "expectedAdxPoints"
```
Expected: FAIL (UnimplementedError)

**Step 3: Implement helpers, manifest loader, and E2E flow**

Implement helpers:
```dart
int _expectedAdxPoints(int barsLength, int period) {
  if (barsLength < period + 1) return 0;
  return (barsLength - (2 * period - 1)).clamp(0, barsLength);
}

int _expectedMacdPoints(List<KLine> bars, int windowMonths) {
  if (bars.isEmpty) return 0;
  final latest = bars.last.datetime;
  final cutoff = _subtractMonths(latest, windowMonths);
  return bars.where((bar) => !bar.datetime.isBefore(cutoff)).length;
}
```

Add manifest loader (latest file by mtime):
```dart
Future<Map<String, dynamic>> _loadLatestManifest() async {
  final reportDir = Directory(p.join(Directory.current.path, 'docs', 'reports'));
  if (!await reportDir.exists()) {
    throw StateError('Missing docs/reports; run data_layer_real_e2e first.');
  }
  final manifests = <File>[];
  await for (final entity in reportDir.list()) {
    if (entity is File && entity.path.endsWith('-data-layer-real-e2e.json')) {
      manifests.add(entity);
    }
  }
  if (manifests.isEmpty) {
    throw StateError('No data-layer manifest found; run data_layer_real_e2e first.');
  }
  manifests.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  final content = await manifests.first.readAsString();
  return jsonDecode(content) as Map<String, dynamic>;
}
```

Implement E2E test body:
- Initialize FFI + SharedPreferences
- Read manifest
- Set `KLineFileStorage` base dir to `fileRoot`
- Set `databaseFactory.setDatabasesPath(dbRoot)`
- Build `MarketDataRepository`, `MacdIndicatorService`, `AdxIndicatorService`
- Daily prewarm: load daily bars using `DailyKlineCacheStore.loadForStocksWithStatus`, then `Future.wait` for `prewarmFromBars` on MACD+ADX
- Weekly prewarm: call `prewarmFromRepository` sequentially for MACD then ADX with `fetchBatchSize=120`, `maxConcurrentPersistWrites=8`, `forceRecompute=true`
- Validate:
  - daily MACD and daily ADX from cache stores using daily bars
  - weekly MACD and weekly ADX from cache stores using weekly bars read via repository
  - Track failures + first-seen IDs (10 sample)
  - Enforce OK rate >= 90% per validation type
- Write report to `docs/reports/YYYY-MM-DD-indicator-layer-real-e2e.md`

**Step 4: Re-run unit tests**

```bash
flutter test test/integration/indicator_layer_real_e2e_test.dart --plain-name "expectedAdxPoints"
```
Expected: PASS

**Step 5: Run the full indicator E2E (requires manifest + cache)**

```bash
flutter test test/integration/indicator_layer_real_e2e_test.dart --plain-name "indicator layer real e2e" -r compact
```
Expected: PASS (may take minutes)

**Step 6: Commit**

```bash
git add test/integration/indicator_layer_real_e2e_test.dart
git commit -m "test: add indicator layer real e2e"
```

---

### Task 3: Smoke the End-to-End Flow

**Files:**
- No code changes

**Step 1: Run data-layer E2E to produce manifest**

```bash
flutter test test/integration/data_layer_real_e2e_test.dart --plain-name "data layer real e2e" -r compact
```
Expected: PASS and a `docs/reports/YYYY-MM-DD-data-layer-real-e2e.json` file

**Step 2: Run indicator-layer E2E**

```bash
flutter test test/integration/indicator_layer_real_e2e_test.dart --plain-name "indicator layer real e2e" -r compact
```
Expected: PASS and a `docs/reports/YYYY-MM-DD-indicator-layer-real-e2e.md` file

**Step 3: Commit any report updates (optional)**

Only commit reports if explicitly requested.
