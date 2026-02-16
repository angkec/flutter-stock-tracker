# New Trading Day Incremental Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 构建“新交易日增量拉取/计算 + 收盘后完整数据覆盖”的统一机制，并用 Unit 为主、E2E 抽样的测试体系完整覆盖关键状态与回归风险。

**Architecture:** 在现有 `MarketDataProvider` 日K拉取链路上引入四个可注入组件：`Clock`、`MarketCalendarProvider`、`DailyCandleCompletenessClassifier`、`FinalOverrideCoordinator`。通过 `DailySyncStateStorage` 记录每只股票“当日 partial/final 接收状态”，强制覆盖只触发受影响股票的增量指标重算，禁止全量重算路径。测试以纯逻辑单测先行，最后补 UI/E2E 验证“>5s 不可无业务反馈”。

**Tech Stack:** Flutter/Dart, `flutter_test`, integration_test, sqflite (`MarketDatabase`), 现有 `MarketDataProvider` + `MacdIndicatorService` + 数据管理页驱动。

---

## 执行前准备

- 推荐先用 `@using-git-worktrees` 创建独立 worktree 后执行。
- 执行过程强制遵循：`@test-driven-development`、`@systematic-debugging`、`@verification-before-completion`。
- 每个 Task 按「先失败测试 -> 最小实现 -> 测试通过 -> 提交」执行，禁止跨 Task 叠改。

### Task 1: 建立新交易日领域模型与可测时间接口

**Files:**
- Create: `lib/data/sync/trading_clock.dart`
- Create: `lib/data/sync/daily_candle_completeness.dart`
- Create: `lib/data/sync/trading_day_session.dart`
- Test: `test/data/sync/daily_candle_completeness_test.dart`
- Test: `test/data/sync/trading_day_session_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';

void main() {
  test('daily completeness should expose terminal state', () {
    expect(DailyCandleCompleteness.partial.isTerminal, isFalse);
    expect(DailyCandleCompleteness.finalized.isTerminal, isTrue);
    expect(DailyCandleCompleteness.unknown.isTerminal, isFalse);
  });

  test('trading session should expose close state', () {
    expect(TradingDaySession.intraday.isClosed, isFalse);
    expect(TradingDaySession.postClosePendingFinal.isClosed, isTrue);
    expect(TradingDaySession.finalized.isClosed, isTrue);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/sync/daily_candle_completeness_test.dart test/data/sync/trading_day_session_test.dart -r expanded`

Expected: FAIL with missing imports/types (`DailyCandleCompleteness`, `TradingDaySession`).

**Step 3: Write minimal implementation**

```dart
// lib/data/sync/daily_candle_completeness.dart
enum DailyCandleCompleteness { partial, finalized, unknown }

extension DailyCandleCompletenessX on DailyCandleCompleteness {
  bool get isTerminal => this == DailyCandleCompleteness.finalized;
}

// lib/data/sync/trading_day_session.dart
enum TradingDaySession {
  nonTrading,
  intraday,
  postClosePendingFinal,
  finalized,
}

extension TradingDaySessionX on TradingDaySession {
  bool get isClosed =>
      this == TradingDaySession.postClosePendingFinal ||
      this == TradingDaySession.finalized;
}

// lib/data/sync/trading_clock.dart
abstract class TradingClock {
  DateTime now();
}

class SystemTradingClock implements TradingClock {
  const SystemTradingClock();
  @override
  DateTime now() => DateTime.now();
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/sync/daily_candle_completeness_test.dart test/data/sync/trading_day_session_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/sync/trading_clock.dart \
  lib/data/sync/daily_candle_completeness.dart \
  lib/data/sync/trading_day_session.dart \
  test/data/sync/daily_candle_completeness_test.dart \
  test/data/sync/trading_day_session_test.dart
git commit -m "feat: add trading-day sync domain primitives"
```

---

### Task 2: 实现数据源日历驱动的交易日会话解析器

**Files:**
- Create: `lib/data/sync/market_calendar_provider.dart`
- Create: `lib/data/sync/trading_day_session_resolver.dart`
- Test: `test/data/sync/trading_day_session_resolver_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/market_calendar_provider.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session_resolver.dart';

void main() {
  test('resolves intraday when market day is open', () async {
    final provider = FakeMarketCalendarProvider(
      snapshot: const MarketDaySnapshot(
        isTradingDay: true,
        isClosed: false,
      ),
    );
    final resolver = TradingDaySessionResolver(provider: provider);
    final session = await resolver.resolve(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
    );
    expect(session, TradingDaySession.intraday);
  });

  test('resolves post-close pending-final when trading day closed but not finalized', () async {
    final provider = FakeMarketCalendarProvider(
      snapshot: const MarketDaySnapshot(
        isTradingDay: true,
        isClosed: true,
      ),
    );
    final resolver = TradingDaySessionResolver(provider: provider);
    final session = await resolver.resolve(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
      hasFinalSnapshot: false,
    );
    expect(session, TradingDaySession.postClosePendingFinal);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/sync/trading_day_session_resolver_test.dart -r expanded`

Expected: FAIL with missing `MarketCalendarProvider` / `TradingDaySessionResolver`.

**Step 3: Write minimal implementation**

```dart
// lib/data/sync/market_calendar_provider.dart
class MarketDaySnapshot {
  final bool isTradingDay;
  final bool isClosed;
  const MarketDaySnapshot({required this.isTradingDay, required this.isClosed});
}

abstract class MarketCalendarProvider {
  Future<MarketDaySnapshot> getMarketDaySnapshot({
    required String stockCode,
    required DateTime tradeDate,
  });
}

// lib/data/sync/trading_day_session_resolver.dart
class TradingDaySessionResolver {
  final MarketCalendarProvider provider;
  const TradingDaySessionResolver({required this.provider});

  Future<TradingDaySession> resolve({
    required String stockCode,
    required DateTime tradeDate,
    bool hasFinalSnapshot = false,
  }) async {
    final snapshot = await provider.getMarketDaySnapshot(
      stockCode: stockCode,
      tradeDate: tradeDate,
    );
    if (!snapshot.isTradingDay) return TradingDaySession.nonTrading;
    if (!snapshot.isClosed) return TradingDaySession.intraday;
    return hasFinalSnapshot
        ? TradingDaySession.finalized
        : TradingDaySession.postClosePendingFinal;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/sync/trading_day_session_resolver_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/sync/market_calendar_provider.dart \
  lib/data/sync/trading_day_session_resolver.dart \
  test/data/sync/trading_day_session_resolver_test.dart
git commit -m "feat: add market-calendar session resolver"
```

---

### Task 3: 实现日线完整性混合判定器（来源标记优先 + 结构规则兜底）

**Files:**
- Create: `lib/data/sync/daily_candle_completeness_classifier.dart`
- Test: `test/data/sync/daily_candle_completeness_classifier_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness_classifier.dart';

void main() {
  final bar = KLine(
    datetime: DateTime(2026, 2, 16),
    open: 10, close: 10.2, high: 10.3, low: 9.9, volume: 1200, amount: 9800,
  );

  test('source explicit final should win', () {
    final classifier = DailyCandleCompletenessClassifier();
    final result = classifier.classify(
      bar: bar,
      sourceFinalFlag: true,
      marketClosed: false,
    );
    expect(result.completeness, DailyCandleCompleteness.finalized);
    expect(result.reason, 'source_final_flag');
  });

  test('fallback to partial when not closed and no source flag', () {
    final classifier = DailyCandleCompletenessClassifier();
    final result = classifier.classify(
      bar: bar,
      sourceFinalFlag: null,
      marketClosed: false,
    );
    expect(result.completeness, DailyCandleCompleteness.partial);
    expect(result.reason, 'structure_intraday_open');
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/sync/daily_candle_completeness_classifier_test.dart -r expanded`

Expected: FAIL with undefined classifier/result types.

**Step 3: Write minimal implementation**

```dart
class DailyCandleCompletenessResult {
  final DailyCandleCompleteness completeness;
  final String reason;
  const DailyCandleCompletenessResult({
    required this.completeness,
    required this.reason,
  });
}

class DailyCandleCompletenessClassifier {
  const DailyCandleCompletenessClassifier();

  DailyCandleCompletenessResult classify({
    required KLine bar,
    required bool marketClosed,
    bool? sourceFinalFlag,
  }) {
    if (sourceFinalFlag == true) {
      return const DailyCandleCompletenessResult(
        completeness: DailyCandleCompleteness.finalized,
        reason: 'source_final_flag',
      );
    }
    if (sourceFinalFlag == false) {
      return const DailyCandleCompletenessResult(
        completeness: DailyCandleCompleteness.partial,
        reason: 'source_partial_flag',
      );
    }
    if (!marketClosed) {
      return const DailyCandleCompletenessResult(
        completeness: DailyCandleCompleteness.partial,
        reason: 'structure_intraday_open',
      );
    }
    return const DailyCandleCompletenessResult(
      completeness: DailyCandleCompleteness.unknown,
      reason: 'structure_closed_without_source_flag',
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/sync/daily_candle_completeness_classifier_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/sync/daily_candle_completeness_classifier.dart \
  test/data/sync/daily_candle_completeness_classifier_test.dart
git commit -m "feat: add hybrid daily candle completeness classifier"
```

---

### Task 4: 增加 DailySyncState 持久化（幂等覆盖与乱序防回退）

**Files:**
- Create: `lib/data/models/daily_sync_state.dart`
- Create: `lib/data/storage/daily_sync_state_storage.dart`
- Modify: `lib/data/storage/database_schema.dart`
- Modify: `lib/data/storage/market_database.dart`
- Test: `test/data/storage/daily_sync_state_storage_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/daily_sync_state.dart';
import 'package:stock_rtwatcher/data/storage/daily_sync_state_storage.dart';

void main() {
  test('upsert + getByStockCode roundtrip keeps finalized date', () async {
    final storage = DailySyncStateStorage();
    final state = DailySyncState(
      stockCode: '600000',
      lastIntradayDate: DateTime(2026, 2, 16),
      lastFinalizedDate: DateTime(2026, 2, 16),
      lastFingerprint: 'fp_v1',
      updatedAt: DateTime(2026, 2, 16, 15, 10),
    );

    await storage.upsert(state);
    final loaded = await storage.getByStockCode('600000');
    expect(loaded, isNotNull);
    expect(loaded!.lastFinalizedDate, DateTime(2026, 2, 16));
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/storage/daily_sync_state_storage_test.dart -r expanded`

Expected: FAIL with missing model/storage/table.

**Step 3: Write minimal implementation**

```dart
// database_schema.dart
static const int version = 6;
static const String createDailySyncStateTable = '''
  CREATE TABLE daily_sync_state (
    stock_code TEXT PRIMARY KEY,
    last_intraday_date INTEGER,
    last_finalized_date INTEGER,
    last_fingerprint TEXT,
    updated_at INTEGER NOT NULL
  )
''';

// market_database.dart in onCreate/onUpgrade
await db.execute(DatabaseSchema.createDailySyncStateTable);

// lib/data/models/daily_sync_state.dart
class DailySyncState {
  final String stockCode;
  final DateTime? lastIntradayDate;
  final DateTime? lastFinalizedDate;
  final String? lastFingerprint;
  final DateTime updatedAt;
  // fromMap/toMap...
}

// lib/data/storage/daily_sync_state_storage.dart
class DailySyncStateStorage {
  Future<void> upsert(DailySyncState state) async { /* insert replace */ }
  Future<DailySyncState?> getByStockCode(String stockCode) async { /* query */ }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/storage/daily_sync_state_storage_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/models/daily_sync_state.dart \
  lib/data/storage/daily_sync_state_storage.dart \
  lib/data/storage/database_schema.dart \
  lib/data/storage/market_database.dart \
  test/data/storage/daily_sync_state_storage_test.dart
git commit -m "feat: add daily sync state persistence and schema migration"
```

---

### Task 5: 实现终盘强覆盖决策器与 DirtyRange 输出

**Files:**
- Create: `lib/data/sync/final_override_coordinator.dart`
- Test: `test/data/sync/final_override_coordinator_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/sync/daily_candle_completeness.dart';
import 'package:stock_rtwatcher/data/sync/final_override_coordinator.dart';
import 'package:stock_rtwatcher/data/sync/trading_day_session.dart';

void main() {
  test('promotes partial -> final and marks dirty range', () {
    final coordinator = FinalOverrideCoordinator();
    final decision = coordinator.decide(
      stockCode: '600000',
      tradeDate: DateTime(2026, 2, 16),
      session: TradingDaySession.postClosePendingFinal,
      incoming: DailyCandleCompleteness.finalized,
      previous: DailyCandleCompleteness.partial,
    );
    expect(decision.action, OverrideAction.promoteFinal);
    expect(decision.dirtyRangeStart, DateTime(2025, 12, 16));
    expect(decision.requiresFullRecompute, isFalse);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/sync/final_override_coordinator_test.dart -r expanded`

Expected: FAIL with missing `FinalOverrideCoordinator`.

**Step 3: Write minimal implementation**

```dart
enum OverrideAction { skip, acceptPartial, promoteFinal, markUnknownRetry }

class OverrideDecision {
  final OverrideAction action;
  final DateTime? dirtyRangeStart;
  final DateTime? dirtyRangeEnd;
  final bool requiresFullRecompute;
  const OverrideDecision({
    required this.action,
    this.dirtyRangeStart,
    this.dirtyRangeEnd,
    this.requiresFullRecompute = false,
  });
}

class FinalOverrideCoordinator {
  const FinalOverrideCoordinator({this.warmupDays = 45});
  final int warmupDays;

  OverrideDecision decide({
    required String stockCode,
    required DateTime tradeDate,
    required TradingDaySession session,
    required DailyCandleCompleteness incoming,
    required DailyCandleCompleteness? previous,
  }) {
    if (incoming == DailyCandleCompleteness.unknown) {
      return const OverrideDecision(action: OverrideAction.markUnknownRetry);
    }
    if (incoming == DailyCandleCompleteness.partial) {
      return const OverrideDecision(action: OverrideAction.acceptPartial);
    }
    if (incoming == DailyCandleCompleteness.finalized &&
        previous != DailyCandleCompleteness.finalized) {
      return OverrideDecision(
        action: OverrideAction.promoteFinal,
        dirtyRangeStart: tradeDate.subtract(Duration(days: warmupDays)),
        dirtyRangeEnd: tradeDate,
      );
    }
    return const OverrideDecision(action: OverrideAction.skip);
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/sync/final_override_coordinator_test.dart -r expanded`

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/data/sync/final_override_coordinator.dart \
  test/data/sync/final_override_coordinator_test.dart
git commit -m "feat: add final-override coordinator with dirty-range output"
```

---

### Task 6: Provider 集成增量覆盖流程（禁止全量重算）

**Files:**
- Modify: `lib/providers/market_data_provider.dart`
- Modify: `test/providers/market_data_provider_test.dart`

**Step 1: Write the failing test**

```dart
test(
  'final override should recompute only impacted stocks and never call full recompute',
  () async {
    // Arrange: 3 stocks, only 600000 receives final promotion.
    // Act: run forceRefetchDailyBars twice (intraday -> final).
    // Assert: breakout/macd recompute only for 600000, and fullRecomputeCount == 0.
    expect(fakeMacd.fullRecomputeCount, 0);
    expect(fakeMacd.incrementalRecomputeStockCodes, ['600000']);
  },
);
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/providers/market_data_provider_test.dart -r expanded --plain-name "final override should recompute only impacted stocks and never call full recompute"`

Expected: FAIL because provider currently always recomputes for all stocks.

**Step 3: Write minimal implementation**

```dart
// market_data_provider.dart (核心改动示意)
Future<void> _recomputeIndicatorsForStocks(
  Set<String> impactedCodes, {
  void Function(int current, int total)? onProgress,
}) async {
  if (impactedCodes.isEmpty) return;

  await _applyBreakoutDetection(
    targetStockCodes: impactedCodes,
    onProgress: onProgress,
  );
  await _prewarmDailyMacd(
    stockCodes: impactedCodes,
    onProgress: onProgress,
  );
}

Future<void> _applyBreakoutDetection({
  Set<String>? targetStockCodes,
  void Function(int current, int total)? onProgress,
}) async {
  final target = targetStockCodes == null
      ? _allData
      : _allData.where((d) => targetStockCodes.contains(d.stock.code)).toList();
  // 仅对 target 计算，保留其余股票旧值
}

Future<void> _prewarmDailyMacd({
  Set<String>? stockCodes,
  void Function(int current, int total)? onProgress,
}) async {
  final payload = <String, List<KLine>>{};
  for (final entry in _dailyBarsCache.entries) {
    if (stockCodes != null && !stockCodes.contains(entry.key)) continue;
    payload[entry.key] = entry.value;
  }
  await _macdService!.prewarmFromBars(
    dataType: KLineDataType.daily,
    barsByStockCode: payload,
    onProgress: onProgress,
  );
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/providers/market_data_provider_test.dart -r expanded`

Expected: PASS for新增用例，且既有 provider 用例不回归。

**Step 5: Commit**

```bash
git add lib/providers/market_data_provider.dart \
  test/providers/market_data_provider_test.dart
git commit -m "feat: integrate incremental final override into market data provider"
```

---

### Task 7: 数据管理页离线 E2E 覆盖“日内可算 + 终盘覆盖”双场景

**Files:**
- Modify: `integration_test/support/data_management_fixtures.dart`
- Modify: `integration_test/features/data_management_offline_test.dart`
- Modify: `integration_test/support/data_management_driver.dart`

**Step 1: Write the failing test**

```dart
testWidgets('new trading day intraday partial data remains computable', (tester) async {
  final context = await launchDataManagementWithFixture(
    tester,
    preset: DataManagementFixturePreset.newTradingDayIntradayPartial,
  );
  final driver = DataManagementDriver(tester);

  await driver.tapDailyForceRefetch();
  await driver.waitForProgressDialogClosedWithWatchdog(context.createWatchdog());
  await driver.expectSnackBarContains('日内数据已增量计算');
});

testWidgets('post-close final snapshot overrides intraday snapshot', (tester) async {
  final context = await launchDataManagementWithFixture(
    tester,
    preset: DataManagementFixturePreset.newTradingDayFinalOverride,
  );
  final driver = DataManagementDriver(tester);

  await driver.tapDailyForceRefetch();
  await driver.waitForProgressDialogClosedWithWatchdog(context.createWatchdog());
  await driver.expectSnackBarContains('终盘数据已覆盖并完成增量重算');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos -r expanded`

Expected: FAIL with missing preset/driver assertions.

**Step 3: Write minimal implementation**

```dart
// data_management_fixtures.dart
enum DataManagementFixturePreset {
  normal,
  stalledProgress,
  failedFetch,
  newTradingDayIntradayPartial,
  newTradingDayFinalOverride,
}

// 根据 preset 注入不同 stage 文案与结果提示:
// - "日内增量计算..."
// - "终盘覆盖..."
```

**Step 4: Run test to verify it passes**

Run: `flutter test integration_test/features/data_management_offline_test.dart -d macos -r expanded`

Expected: PASS，且 watchdog 场景继续有效（>5s 无业务反馈仍失败）。

**Step 5: Commit**

```bash
git add integration_test/support/data_management_fixtures.dart \
  integration_test/support/data_management_driver.dart \
  integration_test/features/data_management_offline_test.dart
git commit -m "test: add offline e2e coverage for new trading-day partial/final flows"
```

---

### Task 8: 真网络 E2E 增加观测指标并更新报告文档

**Files:**
- Modify: `integration_test/features/data_management_real_network_test.dart`
- Modify: `docs/e2e-testing-guide.md`
- Create: `docs/reports/data-management-new-trading-day-latency-2026-02-16.md`

**Step 1: Write the failing assertion/log expectation**

```dart
// 在 real network test 中新增日志字段（先写断言占位）：
debugPrint('[DataManagement Real E2E] daily_intraday_or_final_state=$state');
debugPrint('[DataManagement Real E2E] daily_incremental_recompute_elapsed_ms=$elapsed');
expect(state, isNotEmpty);
```

**Step 2: Run test to verify it fails (or logs missing)**

Run: `flutter test integration_test/features/data_management_real_network_test.dart -d macos --dart-define=RUN_DATA_MGMT_REAL_E2E=true -r expanded`

Expected: FAIL/日志缺失，提示新增指标未接线。

**Step 3: Write minimal implementation**

```dart
// real_network_test.dart 中在 daily_force_refetch 之后追加:
debugPrint(
  '[DataManagement Real E2E] daily_force_refetch_phase='
  'partial_or_final:$dailyState, incremental:$incrementalUsed',
);
debugPrint(
  '[DataManagement Real E2E] daily_incremental_recompute_elapsed_ms='
  '${dailyIncrementalStopwatch.elapsedMilliseconds}',
);
```

并在文档同步新增字段定义与样例日志。

**Step 4: Run test to verify it passes**

Run: `flutter test integration_test/features/data_management_real_network_test.dart -d macos --dart-define=RUN_DATA_MGMT_REAL_E2E=true -r expanded`

Expected: PASS，输出新增字段，便于后续统计 median/p95。

**Step 5: Commit**

```bash
git add integration_test/features/data_management_real_network_test.dart \
  docs/e2e-testing-guide.md \
  docs/reports/data-management-new-trading-day-latency-2026-02-16.md
git commit -m "test: instrument real-network e2e for new trading-day incremental flow"
```

---

### Task 9: 全量验证与收尾提交

**Files:**
- Modify: `docs/plans/2026-02-16-new-trading-day-incremental-validation-implementation.md` (仅在执行偏差时更新)

**Step 1: Run focused unit suites**

Run:
`flutter test test/data/sync -r expanded`
`flutter test test/data/storage/daily_sync_state_storage_test.dart -r expanded`
`flutter test test/providers/market_data_provider_test.dart -r expanded`

Expected: PASS。

**Step 2: Run screen/integration regression**

Run:
`flutter test test/screens/data_management_screen_test.dart -r expanded`
`flutter test integration_test/features/data_management_offline_test.dart -d macos -r expanded`

Expected: PASS。

**Step 3: Run real-network validation (optional but recommended in this task)**

Run:
`flutter test integration_test/features/data_management_real_network_test.dart -d macos --dart-define=RUN_DATA_MGMT_REAL_E2E=true -r expanded`

Expected: PASS，日志包含新交易日状态与增量重算耗时字段。

**Step 4: Summarize evidence in report**

```md
- unit: pass
- offline e2e: pass
- real-network e2e: pass
- key metrics: daily_incremental_recompute_elapsed_ms median/p95
```

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat: harden new trading-day incremental sync with full test coverage"
```

---

## 实施注意事项（必须遵守）

1. 任何路径都不得调用“全量重算”接口；若误触发应立即 fail-fast 并打日志。
2. `DailySyncState` 的更新必须在同一次覆盖事务内完成，避免可见版本指针与状态脱节。
3. E2E 判定继续沿用“5 秒无业务信号即失败”硬约束。
4. 真实网络测试结果只用于发现瓶颈，不可作为唯一正确性依据；正确性以 Unit/Offline Integration 为准。
