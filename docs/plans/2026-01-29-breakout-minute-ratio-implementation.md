# 突破日分钟量比条件 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add minimum minute volume ratio filter for breakout day in multi-day pullback detection.

**Architecture:** Extends `HistoricalKlineService` with `getDailyRatio()` method, adds `minBreakoutMinuteRatio` config to `BreakoutConfig`, injects dependency into `BreakoutService`, converts detection methods to async.

**Tech Stack:** Flutter/Dart, Provider for DI, SharedPreferences for config persistence

---

## Task 1: Add getDailyRatio to HistoricalKlineService

**Files:**
- Modify: `lib/services/historical_kline_service.dart:129` (after `_computeDailyVolumes`)
- Test: `test/services/historical_kline_service_test.dart`

**Step 1: Write the failing test**

Add to `test/services/historical_kline_service_test.dart` after the `getDailyVolumes` group:

```dart
    group('getDailyRatio', () {
      late HistoricalKlineService service;
      late MockDataRepository mockRepo;

      setUp(() {
        mockRepo = MockDataRepository();
        service = HistoricalKlineService(repository: mockRepo);
      });

      test('returns null for unknown stock', () async {
        final ratio = await service.getDailyRatio('999999', DateTime(2025, 1, 25));
        expect(ratio, isNull);
      });

      test('returns null for unknown date', () async {
        final date = DateTime(2025, 1, 24, 9, 30);
        mockRepo.setKlineData('000001', _generateBars(date, 5, 3));

        final ratio = await service.getDailyRatio('000001', DateTime(2025, 1, 25));
        expect(ratio, isNull);
      });

      test('returns null when down volume is zero', () async {
        final date = DateTime(2025, 1, 25, 9, 30);
        mockRepo.setKlineData('000001', _generateBars(date, 5, 0));

        final ratio = await service.getDailyRatio('000001', DateTime(2025, 1, 25));
        expect(ratio, isNull);
      });

      test('returns null when up volume is zero', () async {
        final date = DateTime(2025, 1, 25, 9, 30);
        mockRepo.setKlineData('000001', _generateBars(date, 0, 5));

        final ratio = await service.getDailyRatio('000001', DateTime(2025, 1, 25));
        expect(ratio, isNull);
      });

      test('calculates ratio correctly', () async {
        final date = DateTime(2025, 1, 25, 9, 30);
        // 5 up bars * 100 vol = 500 up, 2 down bars * 100 vol = 200 down
        mockRepo.setKlineData('000001', _generateBars(date, 5, 2));

        final ratio = await service.getDailyRatio('000001', DateTime(2025, 1, 25));
        expect(ratio, 2.5); // 500 / 200
      });

      test('matches date by day only (ignores time)', () async {
        final date = DateTime(2025, 1, 25, 9, 30);
        mockRepo.setKlineData('000001', _generateBars(date, 4, 2));

        // Query with different time on same day
        final ratio = await service.getDailyRatio('000001', DateTime(2025, 1, 25, 15, 0));
        expect(ratio, 2.0); // 400 / 200
      });
    });
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/services/historical_kline_service_test.dart --name "getDailyRatio"`
Expected: FAIL with "getDailyRatio" not found

**Step 3: Write minimal implementation**

Add to `lib/services/historical_kline_service.dart` after line 129 (after `_computeDailyVolumes` method):

```dart
  /// 获取某只股票某日的分钟量比
  /// 返回 null 表示数据不足或无法计算（涨停/跌停等）
  Future<double?> getDailyRatio(String stockCode, DateTime date) async {
    final volumes = await getDailyVolumes(stockCode);
    final dateKey = formatDate(date);
    final dayVolume = volumes[dateKey];
    if (dayVolume == null || dayVolume.down == 0 || dayVolume.up == 0) {
      return null;
    }
    return dayVolume.up / dayVolume.down;
  }
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/services/historical_kline_service_test.dart --name "getDailyRatio"`
Expected: All 6 tests PASS

**Step 5: Commit**

```bash
git add lib/services/historical_kline_service.dart test/services/historical_kline_service_test.dart
git commit -m "feat(historical-kline): add getDailyRatio method"
```

---

## Task 2: Add minBreakoutMinuteRatio to BreakoutConfig

**Files:**
- Modify: `lib/models/breakout_config.dart:117-259`

**Step 1: Add field declaration**

In `lib/models/breakout_config.dart`, add after line 129 (`maxUpperShadowRatio`):

```dart
  /// 突破日最小分钟量比（0=不检测）
  final double minBreakoutMinuteRatio;
```

**Step 2: Add to constructor**

In the `const BreakoutConfig({` constructor (line 165), add after `this.maxUpperShadowRatio = 0.2,`:

```dart
    this.minBreakoutMinuteRatio = 0,
```

**Step 3: Add to copyWith**

In `copyWith` method (line 186), add parameter:

```dart
    double? minBreakoutMinuteRatio,
```

And in the return statement, add after `maxUpperShadowRatio`:

```dart
      minBreakoutMinuteRatio: minBreakoutMinuteRatio ?? this.minBreakoutMinuteRatio,
```

**Step 4: Add to toJson**

In `toJson` (line 222), add after `'maxUpperShadowRatio'`:

```dart
    'minBreakoutMinuteRatio': minBreakoutMinuteRatio,
```

**Step 5: Add to fromJson**

In `fromJson` (line 240), add after `maxUpperShadowRatio`:

```dart
    minBreakoutMinuteRatio: (json['minBreakoutMinuteRatio'] as num?)?.toDouble() ?? 0,
```

**Step 6: Run tests to verify no regression**

Run: `flutter test test/services/breakout_service_test.dart`
Expected: All existing tests PASS

**Step 7: Commit**

```bash
git add lib/models/breakout_config.dart
git commit -m "feat(breakout-config): add minBreakoutMinuteRatio field"
```

---

## Task 3: Add minuteRatioCheck to BreakoutDetectionResult

**Files:**
- Modify: `lib/models/breakout_config.dart:23-67`

**Step 1: Add field**

In `BreakoutDetectionResult` class (line 23), add after `upperShadowCheck` (line 37):

```dart
  /// 分钟量比检测
  final DetectionItem? minuteRatioCheck;
```

**Step 2: Add to constructor**

In the constructor (line 42), add after `this.upperShadowCheck,`:

```dart
    this.minuteRatioCheck,
```

**Step 3: Update breakoutPassed getter**

Replace the `breakoutPassed` getter (lines 51-57) with:

```dart
  /// 突破日条件是否全部通过
  bool get breakoutPassed =>
      isUpDay.passed &&
      volumeCheck.passed &&
      (maBreakCheck?.passed ?? true) &&
      (highBreakCheck?.passed ?? true) &&
      (upperShadowCheck?.passed ?? true) &&
      (minuteRatioCheck?.passed ?? true);
```

**Step 4: Update allItems getter**

Replace the `allItems` getter (lines 59-66) with:

```dart
  /// 获取所有检测项
  List<DetectionItem> get allItems => [
        isUpDay,
        volumeCheck,
        if (maBreakCheck != null) maBreakCheck!,
        if (highBreakCheck != null) highBreakCheck!,
        if (upperShadowCheck != null) upperShadowCheck!,
        if (minuteRatioCheck != null) minuteRatioCheck!,
      ];
```

**Step 5: Run tests**

Run: `flutter test test/services/breakout_service_test.dart`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add lib/models/breakout_config.dart
git commit -m "feat(breakout-config): add minuteRatioCheck to BreakoutDetectionResult"
```

---

## Task 4: Add HistoricalKlineService dependency to BreakoutService

**Files:**
- Modify: `lib/services/breakout_service.dart:1-53`

**Step 1: Add import**

At top of `lib/services/breakout_service.dart`, add after existing imports:

```dart
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
```

**Step 2: Add field and setter**

After line 11 (`BreakoutConfig _config = BreakoutConfig.defaults;`), add:

```dart
  HistoricalKlineService? _historicalKlineService;

  /// 设置历史K线服务（用于获取突破日分钟量比）
  void setHistoricalKlineService(HistoricalKlineService service) {
    _historicalKlineService = service;
  }
```

**Step 3: Run tests**

Run: `flutter test test/services/breakout_service_test.dart`
Expected: All tests PASS (no behavior change yet)

**Step 4: Commit**

```bash
git add lib/services/breakout_service.dart
git commit -m "feat(breakout-service): add HistoricalKlineService dependency"
```

---

## Task 5: Inject HistoricalKlineService in main.dart

**Files:**
- Modify: `lib/main.dart:97-119`

**Step 1: Update ProxyProvider**

The current `ChangeNotifierProxyProvider5` (line 97) needs to become `ChangeNotifierProxyProvider6` to include `HistoricalKlineService`.

Replace lines 97-119 with:

```dart
        ChangeNotifierProxyProvider6<TdxPool, StockService, IndustryService, PullbackService, BreakoutService, HistoricalKlineService, MarketDataProvider>(
          create: (context) {
            final pool = context.read<TdxPool>();
            final stockService = context.read<StockService>();
            final industryService = context.read<IndustryService>();
            final pullbackService = context.read<PullbackService>();
            final breakoutService = context.read<BreakoutService>();
            final historicalKlineService = context.read<HistoricalKlineService>();
            breakoutService.setHistoricalKlineService(historicalKlineService);
            final provider = MarketDataProvider(
              pool: pool,
              stockService: stockService,
              industryService: industryService,
            );
            provider.setPullbackService(pullbackService);
            provider.setBreakoutService(breakoutService);
            provider.loadFromCache();
            return provider;
          },
          update: (_, pool, stockService, industryService, pullbackService, breakoutService, historicalKlineService, previous) {
            breakoutService.setHistoricalKlineService(historicalKlineService);
            previous!.setPullbackService(pullbackService);
            previous.setBreakoutService(breakoutService);
            return previous;
          },
        ),
```

**Step 2: Verify app builds**

Run: `flutter build apk --debug --target-platform android-arm64`
Expected: BUILD SUCCESSFUL

**Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(di): inject HistoricalKlineService into BreakoutService"
```

---

## Task 6: Convert isBreakoutPullback to async with minute ratio check

**Files:**
- Modify: `lib/services/breakout_service.dart:55-149`

**Step 1: Update method signature**

Change `bool isBreakoutPullback(List<KLine> dailyBars)` to:

```dart
  Future<bool> isBreakoutPullback(List<KLine> dailyBars, {String? stockCode}) async {
```

**Step 2: Add minute ratio check in the breakout day loop**

After the upper shadow check (around line 136, after `continue;` for maxUpperShadowRatio), add:

```dart
      // 6. 检测突破日分钟量比
      if (_config.minBreakoutMinuteRatio > 0 &&
          stockCode != null &&
          _historicalKlineService != null) {
        final ratio = await _historicalKlineService!.getDailyRatio(
          stockCode,
          breakoutBar.datetime,
        );
        if (ratio == null || ratio < _config.minBreakoutMinuteRatio) {
          continue;
        }
      }
```

**Step 3: Update comment numbering**

Update the comment for `_hasValidPullbackAfter` check from "6." to "7.".

**Step 4: Commit**

```bash
git add lib/services/breakout_service.dart
git commit -m "feat(breakout-service): add minute ratio check to isBreakoutPullback"
```

---

## Task 7: Convert findBreakoutDays to async with minute ratio check

**Files:**
- Modify: `lib/services/breakout_service.dart:432-507`

**Step 1: Update method signature**

Change `Set<int> findBreakoutDays(List<KLine> dailyBars)` to:

```dart
  Future<Set<int>> findBreakoutDays(List<KLine> dailyBars, {String? stockCode}) async {
```

**Step 2: Add minute ratio check**

After the upper shadow check (around line 495), add:

```dart
      // 6. 检测突破日分钟量比
      if (_config.minBreakoutMinuteRatio > 0 &&
          stockCode != null &&
          _historicalKlineService != null) {
        final ratio = await _historicalKlineService!.getDailyRatio(
          stockCode,
          bar.datetime,
        );
        if (ratio == null || ratio < _config.minBreakoutMinuteRatio) {
          continue;
        }
      }
```

**Step 3: Update comment numbering**

Update the comment for `_hasValidPullbackAfter` check from "6." to "7.".

**Step 4: Commit**

```bash
git add lib/services/breakout_service.dart
git commit -m "feat(breakout-service): add minute ratio check to findBreakoutDays"
```

---

## Task 8: Convert getDetectionResult to async with minuteRatioCheck

**Files:**
- Modify: `lib/services/breakout_service.dart:151-254`

**Step 1: Update method signature**

Change `BreakoutDetectionResult? getDetectionResult(List<KLine> dailyBars, int index)` to:

```dart
  Future<BreakoutDetectionResult?> getDetectionResult(
    List<KLine> dailyBars,
    int index, {
    String? stockCode,
  }) async {
```

**Step 2: Add minuteRatioCheck calculation**

After the upper shadow check (around line 232), add:

```dart
    // 6. 分钟量比检测
    DetectionItem? minuteRatioCheck;
    if (_config.minBreakoutMinuteRatio > 0 &&
        stockCode != null &&
        _historicalKlineService != null) {
      final ratio = await _historicalKlineService!.getDailyRatio(
        stockCode,
        bar.datetime,
      );
      minuteRatioCheck = DetectionItem(
        name: '分钟量比',
        passed: ratio != null && ratio >= _config.minBreakoutMinuteRatio,
        detail: ratio != null
            ? '${ratio.toStringAsFixed(2)} (需≥${_config.minBreakoutMinuteRatio})'
            : '数据不足',
      );
    }
```

**Step 3: Update BreakoutDetectionResult constructor call**

In the return statement (around line 246), add `minuteRatioCheck`:

```dart
    return BreakoutDetectionResult(
      isUpDay: isUpDay,
      volumeCheck: volumeCheck,
      maBreakCheck: maBreakCheck,
      highBreakCheck: highBreakCheck,
      upperShadowCheck: upperShadowCheck,
      minuteRatioCheck: minuteRatioCheck,
      pullbackResult: pullbackResult,
    );
```

**Step 4: Commit**

```bash
git add lib/services/breakout_service.dart
git commit -m "feat(breakout-service): add minuteRatioCheck to getDetectionResult"
```

---

## Task 9: Update MarketDataProvider to handle async detection

**Files:**
- Modify: `lib/providers/market_data_provider.dart:555-575`

**Step 1: Update _applyBreakoutDetection**

The method `_applyBreakoutDetection()` needs to handle async. Replace the entire method with:

```dart
  /// 应用突破回踩检测逻辑
  Future<void> _applyBreakoutDetection() async {
    if (_breakoutService == null) return;

    final updatedData = <StockMonitorData>[];
    for (final data in _allData) {
      final dailyBars = _dailyBarsCache[data.stock.code];

      bool isBreakout = false;
      if (dailyBars != null && dailyBars.length >= 6) {
        isBreakout = await _breakoutService!.isBreakoutPullback(
          dailyBars,
          stockCode: data.stock.code,
        );

        // 检查今日分钟量比条件
        if (isBreakout && _breakoutService!.config.minMinuteRatio > 0) {
          isBreakout = data.ratio >= _breakoutService!.config.minMinuteRatio;
        }

        // 检查是否过滤暴涨
        if (isBreakout && _breakoutService!.config.filterSurgeAfterPullback) {
          final todayGain = data.changePercent / 100;
          if (todayGain > _breakoutService!.config.surgeThreshold) {
            isBreakout = false;
          }
        }
      }

      updatedData.add(data.copyWith(isPullback: data.isPullback, isBreakout: isBreakout));
    }

    _allData = updatedData;
    notifyListeners();
  }
```

**Step 2: Update _detectBreakouts caller**

In `_detectBreakouts()` method (around line 534), change:

```dart
  Future<void> _detectBreakouts() async {
    if (_breakoutService == null || _allData.isEmpty || _dailyBarsCache.isEmpty) return;
    await _applyBreakoutDetection();
  }
```

**Step 3: Update recalculateBreakouts**

In `recalculateBreakouts()` method (around line 540), change the call to async:

```dart
  Future<String?> recalculateBreakouts() async {
    if (_breakoutService == null) {
      return '突破服务未初始化';
    }
    if (_allData.isEmpty) {
      return '缺失分钟数据，请先刷新';
    }
    if (_dailyBarsCache.isEmpty) {
      return '缺失日K数据，请先刷新';
    }
    await _applyBreakoutDetection();
    return null;
  }
```

**Step 4: Update callers of recalculateBreakouts**

Search for `recalculateBreakouts()` calls and add `await` where needed. In `lib/widgets/breakout_config_dialog.dart` line 149:

```dart
await context.read<MarketDataProvider>().recalculateBreakouts();
```

**Step 5: Commit**

```bash
git add lib/providers/market_data_provider.dart lib/widgets/breakout_config_dialog.dart
git commit -m "feat(market-data-provider): convert breakout detection to async"
```

---

## Task 10: Add UI for minBreakoutMinuteRatio in config dialog

**Files:**
- Modify: `lib/widgets/breakout_config_dialog.dart`

**Step 1: Add controller**

After `_maxUpperShadowRatioController` declaration (around line 29), add:

```dart
  late TextEditingController _minBreakoutMinuteRatioController;
```

**Step 2: Initialize controller**

In `initState()`, after `_maxUpperShadowRatioController` initialization (around line 56), add:

```dart
    _minBreakoutMinuteRatioController = TextEditingController(
      text: config.minBreakoutMinuteRatio.toStringAsFixed(2),
    );
```

**Step 3: Dispose controller**

In `dispose()`, after `_maxUpperShadowRatioController.dispose()`, add:

```dart
    _minBreakoutMinuteRatioController.dispose();
```

**Step 4: Parse in _save()**

In `_save()`, after `maxUpperShadowRatio` parsing (around line 112), add:

```dart
    final minBreakoutMinuteRatio =
        double.tryParse(_minBreakoutMinuteRatioController.text) ?? 0;
```

And add to `BreakoutConfig` constructor:

```dart
      minBreakoutMinuteRatio: minBreakoutMinuteRatio,
```

**Step 5: Reset in _reset()**

In `_reset()`, after `_maxUpperShadowRatioController.text` reset, add:

```dart
    _minBreakoutMinuteRatioController.text =
        defaults.minBreakoutMinuteRatio.toStringAsFixed(2);
```

**Step 6: Add UI field**

In the build method, inside the "突破日条件" ExpansionTile children, after the `_maxUpperShadowRatioController` TextField (around line 259), add:

```dart
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _minBreakoutMinuteRatioController,
                        label: '最小分钟量比',
                        hint: '突破日分钟涨跌量比，0=不检测',
                        suffix: '',
                      ),
```

**Step 7: Verify app runs**

Run: `flutter run`
Expected: Config dialog shows new field

**Step 8: Commit**

```bash
git add lib/widgets/breakout_config_dialog.dart
git commit -m "feat(ui): add minBreakoutMinuteRatio config field"
```

---

## Task 11: Update stock_detail_screen for async getDetectionResult

**Files:**
- Modify: `lib/screens/stock_detail_screen.dart`

**Step 1: Find getDetectionResult usage**

The `KlineChart` widget receives `getDetectionResult` callback. We need to handle async.

**Step 2: Add state for detection results**

Add a cache for detection results:

```dart
  Map<int, BreakoutDetectionResult?> _detectionResultsCache = {};
```

**Step 3: Preload detection results when daily bars load**

Add a method to preload results after daily bars are loaded:

```dart
  Future<void> _preloadDetectionResults() async {
    if (_dailyBars.isEmpty) return;
    final breakoutService = context.read<BreakoutService>();
    final newCache = <int, BreakoutDetectionResult?>{};

    for (int i = 5; i < _dailyBars.length; i++) {
      final result = await breakoutService.getDetectionResult(
        _dailyBars,
        i,
        stockCode: widget.stockCode,
      );
      newCache[i] = result;
    }

    if (mounted) {
      setState(() {
        _detectionResultsCache = newCache;
      });
    }
  }
```

**Step 4: Call preload after loading daily bars**

In the daily bars loading completion, call `_preloadDetectionResults()`.

**Step 5: Update KlineChart callback**

Change the `getDetectionResult` callback to use the cache:

```dart
getDetectionResult: (index) => _detectionResultsCache[index],
```

**Step 6: Commit**

```bash
git add lib/screens/stock_detail_screen.dart
git commit -m "feat(stock-detail): handle async detection results"
```

---

## Task 12: Run full test suite and final commit

**Step 1: Run all tests**

Run: `flutter test`
Expected: All tests PASS

**Step 2: Run app and verify feature**

Run: `flutter run`
Verify:
1. Open config dialog, see new "最小分钟量比" field
2. Set a value > 0
3. Refresh data
4. Check breakout detection filters by minute ratio
5. Open stock detail, verify detection overlay shows minute ratio check

**Step 3: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: address review feedback"
```
