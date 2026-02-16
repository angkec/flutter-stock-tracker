# Data Management Audit Export Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a reliability-first on-device audit trail for Data Management operations with strict PASS/FAIL verdicts, latest-audit UI signal, and local export.

**Architecture:** Add a new `lib/audit` module with event-sourced JSONL persistence, deterministic verdict evaluation, and a latest-run index for fast UI reads. Integrate auditing at Data Management operation boundaries (`historical`, `daily force`, `weekly`, `weekly force`, `weekly MACD`) through a reusable runner, then render a Diagnostic Console card in `DataManagementScreen`. Keep latency as recorded evidence only (never fail criteria in V1).

**Tech Stack:** Flutter/Dart, Provider, `dart:io`, `path_provider`, `archive`, `flutter_test`, integration_test.

---

## 执行前准备

- 推荐先用 `@using-git-worktrees` 创建独立 worktree 后执行。
- 执行过程强制遵循：`@test-driven-development`、`@systematic-debugging`、`@verification-before-completion`。
- 每个 Task 严格按：先失败测试 -> 最小实现 -> 测试通过 -> 提交。
- 严格保持 YAGNI：V1 仅覆盖 Data Management，不扩散到主刷新流程。

### Task 1: 建立 Audit 领域模型（操作类型、事件、总结、判定）

**Files:**
- Create: `lib/audit/models/audit_operation_type.dart`
- Create: `lib/audit/models/audit_verdict.dart`
- Create: `lib/audit/models/audit_event.dart`
- Create: `lib/audit/models/audit_run_summary.dart`
- Test: `test/audit/models/audit_models_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';

void main() {
  test('audit event should roundtrip json', () {
    final event = AuditEvent(
      ts: DateTime(2026, 2, 16, 10, 30),
      runId: 'run-1',
      operation: AuditOperationType.dailyForceRefetch,
      eventType: AuditEventType.fetchResult,
      payload: const {'errors': 0, 'updated_stocks': 12},
    );

    final decoded = AuditEvent.fromJson(event.toJson());
    expect(decoded, event);
  });

  test('run summary should expose fail state', () {
    final summary = AuditRunSummary(
      runId: 'run-2',
      operation: AuditOperationType.weeklyFetchMissing,
      startedAt: DateTime(2026, 2, 16, 9),
      completedAt: DateTime(2026, 2, 16, 9, 0, 2),
      verdict: AuditVerdict.fail,
      reasonCodes: const ['unknown_state'],
      errorCount: 1,
      missingCount: 0,
      incompleteCount: 0,
      unknownStateCount: 1,
      updatedStockCount: 8,
      totalRecords: 320,
      elapsedMs: 2000,
      stageDurationsMs: const {'fetch': 1400, 'write': 600},
    );

    expect(summary.isPass, isFalse);
    expect(summary.primaryReasonCode, 'unknown_state');
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/audit/models/audit_models_test.dart -r expanded`  
Expected: FAIL with missing imports/types under `lib/audit/models`.

**Step 3: Write minimal implementation**

```dart
// lib/audit/models/audit_operation_type.dart
enum AuditOperationType {
  historicalFetchMissing,
  dailyForceRefetch,
  weeklyFetchMissing,
  weeklyForceRefetch,
  weeklyMacdRecompute,
}

extension AuditOperationTypeX on AuditOperationType {
  String get wireName => switch (this) {
    AuditOperationType.historicalFetchMissing => 'historical_fetch_missing',
    AuditOperationType.dailyForceRefetch => 'daily_force_refetch',
    AuditOperationType.weeklyFetchMissing => 'weekly_fetch_missing',
    AuditOperationType.weeklyForceRefetch => 'weekly_force_refetch',
    AuditOperationType.weeklyMacdRecompute => 'weekly_macd_recompute',
  };
}
```

```dart
// lib/audit/models/audit_verdict.dart
enum AuditVerdict { pass, fail }
```

```dart
// lib/audit/models/audit_event.dart
enum AuditEventType {
  runStarted,
  stageStarted,
  stageProgress,
  stageCompleted,
  fetchResult,
  verificationResult,
  completenessState,
  indicatorRecomputeResult,
  errorRaised,
  runCompleted,
}

class AuditEvent {
  const AuditEvent({
    required this.ts,
    required this.runId,
    required this.operation,
    required this.eventType,
    required this.payload,
  });

  final DateTime ts;
  final String runId;
  final AuditOperationType operation;
  final AuditEventType eventType;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'ts': ts.toIso8601String(),
    'run_id': runId,
    'operation': operation.wireName,
    'event_type': eventType.name,
    'payload': payload,
  };

  static AuditEvent fromJson(Map<String, Object?> json) {
    final operation = AuditOperationType.values.firstWhere(
      (value) => value.wireName == json['operation'],
    );
    final eventType = AuditEventType.values.firstWhere(
      (value) => value.name == json['event_type'],
    );
    return AuditEvent(
      ts: DateTime.parse(json['ts']! as String),
      runId: json['run_id']! as String,
      operation: operation,
      eventType: eventType,
      payload: Map<String, Object?>.from(json['payload']! as Map),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuditEvent &&
      ts == other.ts &&
      runId == other.runId &&
      operation == other.operation &&
      eventType == other.eventType &&
      _mapEquals(payload, other.payload);

  @override
  int get hashCode => Object.hash(ts, runId, operation, eventType, payload.length);

  bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
```

```dart
// lib/audit/models/audit_run_summary.dart
class AuditRunSummary {
  const AuditRunSummary({
    required this.runId,
    required this.operation,
    required this.startedAt,
    required this.completedAt,
    required this.verdict,
    required this.reasonCodes,
    required this.errorCount,
    required this.missingCount,
    required this.incompleteCount,
    required this.unknownStateCount,
    required this.updatedStockCount,
    required this.totalRecords,
    required this.elapsedMs,
    required this.stageDurationsMs,
  });

  final String runId;
  final AuditOperationType operation;
  final DateTime startedAt;
  final DateTime completedAt;
  final AuditVerdict verdict;
  final List<String> reasonCodes;
  final int errorCount;
  final int missingCount;
  final int incompleteCount;
  final int unknownStateCount;
  final int updatedStockCount;
  final int totalRecords;
  final int elapsedMs;
  final Map<String, int> stageDurationsMs;

  bool get isPass => verdict == AuditVerdict.pass;
  String? get primaryReasonCode => reasonCodes.isEmpty ? null : reasonCodes.first;
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/audit/models/audit_models_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/audit/models/audit_operation_type.dart \
  lib/audit/models/audit_verdict.dart \
  lib/audit/models/audit_event.dart \
  lib/audit/models/audit_run_summary.dart \
  test/audit/models/audit_models_test.dart
git commit -m "feat: add audit domain models"
```

---

### Task 2: 实现严格可靠性判定引擎（不包含延迟失败）

**Files:**
- Create: `lib/audit/services/audit_verdict_engine.dart`
- Test: `test/audit/services/audit_verdict_engine_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/services/audit_verdict_engine.dart';

void main() {
  final engine = AuditVerdictEngine();

  test('fails on unknown completeness state', () {
    final verdict = engine.evaluate(
      runId: 'run-unknown',
      operation: AuditOperationType.dailyForceRefetch,
      startedAt: DateTime(2026, 2, 16, 9),
      completedAt: DateTime(2026, 2, 16, 9, 0, 3),
      events: [
        AuditEvent(
          ts: DateTime(2026, 2, 16, 9, 0, 1),
          runId: 'run-unknown',
          operation: AuditOperationType.dailyForceRefetch,
          eventType: AuditEventType.completenessState,
          payload: const {'state': 'unknown'},
        ),
      ],
    );
    expect(verdict.verdict.name, 'fail');
    expect(verdict.reasonCodes, contains('unknown_state'));
  });

  test('does not fail on high latency alone', () {
    final verdict = engine.evaluate(
      runId: 'run-latency',
      operation: AuditOperationType.weeklyFetchMissing,
      startedAt: DateTime(2026, 2, 16, 9),
      completedAt: DateTime(2026, 2, 16, 9, 0, 20),
      events: const [],
      elapsedMs: 20000,
    );
    expect(verdict.verdict.name, 'pass');
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/audit/services/audit_verdict_engine_test.dart -r expanded`  
Expected: FAIL with missing `AuditVerdictEngine`.

**Step 3: Write minimal implementation**

```dart
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';

class AuditVerdictEngine {
  AuditRunSummary evaluate({
    required String runId,
    required AuditOperationType operation,
    required DateTime startedAt,
    required DateTime completedAt,
    required List<AuditEvent> events,
    int? elapsedMs,
  }) {
    var errorCount = 0;
    var missingCount = 0;
    var incompleteCount = 0;
    var unknownStateCount = 0;
    var updatedStockCount = 0;
    var totalRecords = 0;
    final reasons = <String>{};

    for (final event in events) {
      switch (event.eventType) {
        case AuditEventType.errorRaised:
          errorCount += 1;
          reasons.add('runtime_error');
          break;
        case AuditEventType.verificationResult:
          final missing = (event.payload['missing_count'] as int?) ?? 0;
          final incomplete = (event.payload['incomplete_count'] as int?) ?? 0;
          missingCount += missing;
          incompleteCount += incomplete;
          if (missing > 0) reasons.add('missing_after_fetch');
          if (incomplete > 0) reasons.add('incomplete_after_fetch');
          break;
        case AuditEventType.completenessState:
          if (event.payload['state'] == 'unknown') {
            unknownStateCount += 1;
            reasons.add('unknown_state');
          }
          break;
        case AuditEventType.fetchResult:
          updatedStockCount += (event.payload['updated_stock_count'] as int?) ?? 0;
          totalRecords += (event.payload['total_records'] as int?) ?? 0;
          break;
        case AuditEventType.indicatorRecomputeResult:
          final changed = (event.payload['data_changed'] as bool?) ?? false;
          final scope = (event.payload['scope_count'] as int?) ?? 0;
          if (changed && scope == 0) reasons.add('recompute_scope_empty');
          break;
        default:
          break;
      }
    }

    final fail = reasons.isNotEmpty;
    final effectiveElapsed =
        elapsedMs ?? completedAt.difference(startedAt).inMilliseconds;

    return AuditRunSummary(
      runId: runId,
      operation: operation,
      startedAt: startedAt,
      completedAt: completedAt,
      verdict: fail ? AuditVerdict.fail : AuditVerdict.pass,
      reasonCodes: reasons.toList()..sort(),
      errorCount: errorCount,
      missingCount: missingCount,
      incompleteCount: incompleteCount,
      unknownStateCount: unknownStateCount,
      updatedStockCount: updatedStockCount,
      totalRecords: totalRecords,
      elapsedMs: effectiveElapsed,
      stageDurationsMs: const {},
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/audit/services/audit_verdict_engine_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/audit/services/audit_verdict_engine.dart \
  test/audit/services/audit_verdict_engine_test.dart
git commit -m "feat: add strict reliability audit verdict engine"
```

---

### Task 3: 实现 JSONL 审计存储与最新索引存储

**Files:**
- Create: `lib/audit/storage/audit_log_store.dart`
- Create: `lib/audit/storage/latest_audit_index_store.dart`
- Test: `test/audit/storage/audit_log_store_test.dart`
- Test: `test/audit/storage/latest_audit_index_store_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/storage/audit_log_store.dart';

void main() {
  test('appends and reads events by run id', () async {
    final tempDir = await Directory.systemTemp.createTemp('audit-log-store');
    final store = AuditLogStore(
      rootDirectoryProvider: () async => tempDir,
      nowProvider: () => DateTime(2026, 2, 16, 10),
      retentionDays: 14,
      maxBytesPerFile: 1 << 20,
    );

    final event = AuditEvent(
      ts: DateTime(2026, 2, 16, 10, 1),
      runId: 'run-1',
      operation: AuditOperationType.dailyForceRefetch,
      eventType: AuditEventType.runStarted,
      payload: const {'stock_count': 20},
    );
    await store.append(event);

    final loaded = await store.readEvents(runId: 'run-1');
    expect(loaded, hasLength(1));
    expect(loaded.first.eventType, AuditEventType.runStarted);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/audit/storage/audit_log_store_test.dart test/audit/storage/latest_audit_index_store_test.dart -r expanded`  
Expected: FAIL with missing store implementations.

**Step 3: Write minimal implementation**

```dart
// lib/audit/storage/audit_log_store.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';

class AuditLogStore {
  AuditLogStore({
    Future<Directory> Function()? rootDirectoryProvider,
    DateTime Function()? nowProvider,
    this.retentionDays = 14,
    this.maxBytesPerFile = 2 * 1024 * 1024,
  }) : _rootDirectoryProvider =
           rootDirectoryProvider ?? _defaultRootDirectoryProvider,
       _nowProvider = nowProvider ?? DateTime.now;

  final Future<Directory> Function() _rootDirectoryProvider;
  final DateTime Function() _nowProvider;
  final int retentionDays;
  final int maxBytesPerFile;

  static Future<Directory> _defaultRootDirectoryProvider() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'audit'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> append(AuditEvent event) async {
    final file = await _resolveDailyFile();
    await file.writeAsString('${jsonEncode(event.toJson())}\n', mode: FileMode.append);
    await _cleanupOldFiles();
  }

  Future<List<AuditEvent>> readEvents({required String runId}) async {
    final root = await _rootDirectoryProvider();
    if (!await root.exists()) return const <AuditEvent>[];
    final events = <AuditEvent>[];
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final lines = await entity.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, Object?>;
          final event = AuditEvent.fromJson(json);
          if (event.runId == runId) events.add(event);
        } catch (_) {
          // Ignore malformed tail lines.
        }
      }
    }
    events.sort((a, b) => a.ts.compareTo(b.ts));
    return events;
  }

  Future<File> _resolveDailyFile() async {
    final root = await _rootDirectoryProvider();
    await root.create(recursive: true);
    final now = _nowProvider();
    final filename =
        'audit-${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}.jsonl';
    final file = File(p.join(root.path, filename));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<void> _cleanupOldFiles() async {
    final root = await _rootDirectoryProvider();
    if (!await root.exists()) return;
    final cutoff = _nowProvider().subtract(Duration(days: retentionDays));
    await for (final entity in root.list()) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }
}
```

```dart
// lib/audit/storage/latest_audit_index_store.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';

class LatestAuditIndexStore {
  Future<void> save(AuditRunSummary summary) async {
    final file = await _indexFile();
    await file.writeAsString(jsonEncode(_toJson(summary)));
  }

  Future<AuditRunSummary?> readLatest() async {
    final file = await _indexFile();
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final json = jsonDecode(raw) as Map<String, Object?>;
    return _fromJson(json);
  }

  Future<File> _indexFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'audit'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'latest_run_index.json'));
  }

  Map<String, Object?> _toJson(AuditRunSummary summary) => {
    'run_id': summary.runId,
    'operation': summary.operation.wireName,
    'started_at': summary.startedAt.toIso8601String(),
    'completed_at': summary.completedAt.toIso8601String(),
    'verdict': summary.verdict.name,
    'reason_codes': summary.reasonCodes,
    'error_count': summary.errorCount,
    'missing_count': summary.missingCount,
    'incomplete_count': summary.incompleteCount,
    'unknown_state_count': summary.unknownStateCount,
    'updated_stock_count': summary.updatedStockCount,
    'total_records': summary.totalRecords,
    'elapsed_ms': summary.elapsedMs,
    'stage_durations_ms': summary.stageDurationsMs,
  };

  AuditRunSummary _fromJson(Map<String, Object?> json) {
    final operation = AuditOperationType.values.firstWhere(
      (value) => value.wireName == json['operation'],
    );
    final verdict = AuditVerdict.values.firstWhere(
      (value) => value.name == json['verdict'],
    );
    return AuditRunSummary(
      runId: json['run_id']! as String,
      operation: operation,
      startedAt: DateTime.parse(json['started_at']! as String),
      completedAt: DateTime.parse(json['completed_at']! as String),
      verdict: verdict,
      reasonCodes: List<String>.from(json['reason_codes']! as List),
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
      missingCount: (json['missing_count'] as num?)?.toInt() ?? 0,
      incompleteCount: (json['incomplete_count'] as num?)?.toInt() ?? 0,
      unknownStateCount: (json['unknown_state_count'] as num?)?.toInt() ?? 0,
      updatedStockCount: (json['updated_stock_count'] as num?)?.toInt() ?? 0,
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      stageDurationsMs: Map<String, int>.from(json['stage_durations_ms'] as Map? ?? const {}),
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/audit/storage/audit_log_store_test.dart test/audit/storage/latest_audit_index_store_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/audit/storage/audit_log_store.dart \
  lib/audit/storage/latest_audit_index_store.dart \
  test/audit/storage/audit_log_store_test.dart \
  test/audit/storage/latest_audit_index_store_test.dart
git commit -m "feat: add on-device audit log and latest index stores"
```

---

### Task 4: 实现 AuditOperationRunner（统一生命周期 + 事件采集）

**Files:**
- Create: `lib/audit/services/audit_operation_runner.dart`
- Test: `test/audit/services/audit_operation_runner_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/services/audit_operation_runner.dart';

void main() {
  test('runner should create run and emit completed summary', () async {
    final memory = InMemoryAuditSink();
    final runner = AuditOperationRunner(
      sink: memory,
      nowProvider: () => DateTime(2026, 2, 16, 11),
    );

    final summary = await runner.run(
      operation: AuditOperationType.dailyForceRefetch,
      body: (ctx) async {
        ctx.stageStarted('fetch');
        ctx.stageProgress('fetch', current: 1, total: 2);
        ctx.stageCompleted('fetch');
      },
    );

    expect(summary.runId, isNotEmpty);
    expect(memory.events.any((e) => e.eventType.name == 'runStarted'), isTrue);
    expect(memory.events.any((e) => e.eventType.name == 'runCompleted'), isTrue);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/audit/services/audit_operation_runner_test.dart -r expanded`  
Expected: FAIL with missing `AuditOperationRunner`.

**Step 3: Write minimal implementation**

```dart
import 'package:uuid/uuid.dart';
import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/services/audit_verdict_engine.dart';
import 'package:stock_rtwatcher/audit/storage/audit_log_store.dart';
import 'package:stock_rtwatcher/audit/storage/latest_audit_index_store.dart';

abstract class AuditSink {
  Future<void> append(AuditEvent event);
  Future<void> saveLatest(AuditRunSummary summary);
}

class FileAuditSink implements AuditSink {
  FileAuditSink(this.logStore, this.indexStore);
  final AuditLogStore logStore;
  final LatestAuditIndexStore indexStore;

  @override
  Future<void> append(AuditEvent event) => logStore.append(event);

  @override
  Future<void> saveLatest(AuditRunSummary summary) => indexStore.save(summary);
}

class AuditOperationContext {
  AuditOperationContext({
    required this.runId,
    required this.operation,
    required this.nowProvider,
    required this.eventBuffer,
  });

  final String runId;
  final AuditOperationType operation;
  final DateTime Function() nowProvider;
  final List<AuditEvent> eventBuffer;

  void stageStarted(String stage) => _emit(AuditEventType.stageStarted, {'stage': stage});
  void stageProgress(String stage, {required int current, required int total}) =>
      _emit(AuditEventType.stageProgress, {'stage': stage, 'current': current, 'total': total});
  void stageCompleted(String stage) =>
      _emit(AuditEventType.stageCompleted, {'stage': stage});
  void record(AuditEventType type, Map<String, Object?> payload) => _emit(type, payload);

  void _emit(AuditEventType type, Map<String, Object?> payload) {
    eventBuffer.add(
      AuditEvent(
        ts: nowProvider(),
        runId: runId,
        operation: operation,
        eventType: type,
        payload: payload,
      ),
    );
  }
}

class AuditOperationRunner {
  AuditOperationRunner({
    required this.sink,
    DateTime Function()? nowProvider,
    AuditVerdictEngine? verdictEngine,
  }) : _nowProvider = nowProvider ?? DateTime.now,
       _verdictEngine = verdictEngine ?? AuditVerdictEngine();

  final AuditSink sink;
  final DateTime Function() _nowProvider;
  final AuditVerdictEngine _verdictEngine;
  final _uuid = const Uuid();

  Future<AuditRunSummary> run({
    required AuditOperationType operation,
    required Future<void> Function(AuditOperationContext ctx) body,
  }) async {
    final runId = _uuid.v4();
    final startedAt = _nowProvider();
    final events = <AuditEvent>[];
    final ctx = AuditOperationContext(
      runId: runId,
      operation: operation,
      nowProvider: _nowProvider,
      eventBuffer: events,
    );
    ctx.record(AuditEventType.runStarted, const {});

    try {
      await body(ctx);
    } catch (error) {
      ctx.record(AuditEventType.errorRaised, {'message': '$error'});
      rethrow;
    } finally {
      final completedAt = _nowProvider();
      ctx.record(AuditEventType.runCompleted, const {});
      for (final event in events) {
        await sink.append(event);
      }
      final summary = _verdictEngine.evaluate(
        runId: runId,
        operation: operation,
        startedAt: startedAt,
        completedAt: completedAt,
        events: events,
      );
      await sink.saveLatest(summary);
      return summary;
    }
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/audit/services/audit_operation_runner_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/audit/services/audit_operation_runner.dart \
  test/audit/services/audit_operation_runner_test.dart
git commit -m "feat: add audit operation runner lifecycle"
```

---

### Task 5: 实现本地导出服务（最新 run 与最近 7 天）

**Files:**
- Create: `lib/audit/services/audit_export_service.dart`
- Test: `test/audit/services/audit_export_service_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/services/audit_export_service.dart';

void main() {
  test('export latest run creates zip artifact', () async {
    final temp = await Directory.systemTemp.createTemp('audit-export');
    final service = AuditExportService(
      auditRootProvider: () async => temp,
      outputDirectoryProvider: () async => temp,
      nowProvider: () => DateTime(2026, 2, 16, 12),
    );

    final file = await service.exportLatestRun(runId: 'run-1');
    expect(await file.exists(), isTrue);
    expect(file.path.endsWith('.zip'), isTrue);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/audit/services/audit_export_service_test.dart -r expanded`  
Expected: FAIL with missing `AuditExportService`.

**Step 3: Write minimal implementation**

```dart
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AuditExportService {
  AuditExportService({
    Future<Directory> Function()? auditRootProvider,
    Future<Directory> Function()? outputDirectoryProvider,
    DateTime Function()? nowProvider,
  }) : _auditRootProvider = auditRootProvider ?? _defaultAuditRoot,
       _outputDirectoryProvider = outputDirectoryProvider ?? _defaultAuditRoot,
       _nowProvider = nowProvider ?? DateTime.now;

  final Future<Directory> Function() _auditRootProvider;
  final Future<Directory> Function() _outputDirectoryProvider;
  final DateTime Function() _nowProvider;

  static Future<Directory> _defaultAuditRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'audit'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> exportLatestRun({required String runId}) async {
    final root = await _auditRootProvider();
    final outDir = await _outputDirectoryProvider();
    final now = _nowProvider();
    final outName =
        'audit-latest-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.zip';
    final outFile = File(p.join(outDir.path, outName));

    final encoder = ZipFileEncoder();
    encoder.create(outFile.path);
    await for (final entity in root.list()) {
      if (entity is File &&
          (entity.path.endsWith('.jsonl') || entity.path.endsWith('latest_run_index.json'))) {
        encoder.addFile(entity);
      }
    }
    encoder.close();
    return outFile;
  }

  Future<File> exportRecentDays({int days = 7}) async {
    final root = await _auditRootProvider();
    final outDir = await _outputDirectoryProvider();
    final now = _nowProvider();
    final outFile = File(p.join(outDir.path, 'audit-last-${days}d-${now.millisecondsSinceEpoch}.zip'));
    final cutoff = now.subtract(Duration(days: days));

    final encoder = ZipFileEncoder();
    encoder.create(outFile.path);
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isAfter(cutoff)) {
        encoder.addFile(entity);
      }
    }
    encoder.close();
    return outFile;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/audit/services/audit_export_service_test.dart -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/audit/services/audit_export_service.dart \
  test/audit/services/audit_export_service_test.dart
git commit -m "feat: add local audit export service"
```

---

### Task 6: 组装 AuditService 并注入 Provider（主应用 + 测试夹具）

**Files:**
- Create: `lib/audit/services/audit_service.dart`
- Modify: `lib/main.dart`
- Modify: `integration_test/support/data_management_fixtures.dart`
- Modify: `test/screens/data_management_screen_test.dart`
- Test: `test/audit/services/audit_service_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/audit/services/audit_service.dart';

void main() {
  test('audit service should expose latest summary stream', () async {
    final service = AuditService.forTest();
    final summaries = <String>[];
    final sub = service.latestSummaryStream.listen((summary) {
      if (summary != null) summaries.add(summary.runId);
    });

    await service.refreshLatest();
    await sub.cancel();
    expect(summaries, isEmpty);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/audit/services/audit_service_test.dart -r expanded`  
Expected: FAIL with missing `AuditService`.

**Step 3: Write minimal implementation**

```dart
// lib/audit/services/audit_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/services/audit_export_service.dart';
import 'package:stock_rtwatcher/audit/services/audit_operation_runner.dart';
import 'package:stock_rtwatcher/audit/services/audit_verdict_engine.dart';
import 'package:stock_rtwatcher/audit/storage/audit_log_store.dart';
import 'package:stock_rtwatcher/audit/storage/latest_audit_index_store.dart';

class AuditService extends ChangeNotifier {
  AuditService({
    AuditOperationRunner? runner,
    LatestAuditIndexStore? indexStore,
    AuditExportService? exportService,
  }) : _indexStore = indexStore ?? LatestAuditIndexStore(),
       _runner =
           runner ??
           AuditOperationRunner(
             sink: FileAuditSink(AuditLogStore(), LatestAuditIndexStore()),
             verdictEngine: AuditVerdictEngine(),
           ),
       _exportService = exportService ?? AuditExportService();

  final AuditOperationRunner _runner;
  final LatestAuditIndexStore _indexStore;
  final AuditExportService _exportService;
  final StreamController<AuditRunSummary?> _latestController =
      StreamController<AuditRunSummary?>.broadcast();
  AuditRunSummary? _latest;

  AuditRunSummary? get latest => _latest;
  Stream<AuditRunSummary?> get latestSummaryStream => _latestController.stream;
  AuditOperationRunner get runner => _runner;
  AuditExportService get exporter => _exportService;

  Future<void> refreshLatest() async {
    _latest = await _indexStore.readLatest();
    _latestController.add(_latest);
    notifyListeners();
  }

  static AuditService forTest() {
    return AuditService(
      runner: AuditOperationRunner(
        sink: FileAuditSink(AuditLogStore(), LatestAuditIndexStore()),
      ),
      indexStore: LatestAuditIndexStore(),
      exportService: AuditExportService(),
    );
  }
}
```

Also wire in:

1. `lib/main.dart`: add `ChangeNotifierProvider<AuditService>(create: (_) => AuditService()..refreshLatest())`.
2. `integration_test/support/data_management_fixtures.dart`: provide fake `AuditService` (or real test-safe service) in `MultiProvider`.
3. `test/screens/data_management_screen_test.dart`: include the same provider in test harness.

**Step 4: Run test to verify it passes**

Run: `flutter test test/audit/services/audit_service_test.dart test/screens/data_management_screen_test.dart -r compact`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/audit/services/audit_service.dart \
  lib/main.dart \
  integration_test/support/data_management_fixtures.dart \
  test/screens/data_management_screen_test.dart \
  test/audit/services/audit_service_test.dart
git commit -m "feat: wire audit service through app and test providers"
```

---

### Task 7: 先接入 daily force refetch 审计事件（最小垂直切片）

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Test: `test/screens/data_management_screen_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('daily force refetch should write latest audit summary', (tester) async {
  final context = await launchDataManagementWithFixture(tester);
  final driver = DataManagementDriver(tester);

  await driver.tapDailyForceRefetch();
  await driver.expectProgressDialogVisible();
  await driver.waitForProgressDialogClosedWithWatchdog(context.createWatchdog());

  await tester.pumpAndSettle();
  expect(find.textContaining('Latest Audit'), findsOneWidget);
  expect(find.textContaining('PASS'), findsWidgets);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "daily force refetch should write latest audit summary" -r expanded`  
Expected: FAIL because no audit UI and no audit write path yet.

**Step 3: Write minimal implementation**

In `lib/screens/data_management_screen.dart`:

1. Read `AuditService` from context at start of `_forceRefetchDailyData`.
2. Wrap core daily flow with `auditService.runner.run(...)`.
3. Emit stage events and factual events:
   - `stage_started` / `stage_progress` / `stage_completed`
   - `completeness_state`
   - `indicator_recompute_result`
   - `fetch_result` and `error_raised`.
4. Call `await auditService.refreshLatest()` on completion.

Minimal integration snippet:

```dart
final auditService = context.read<AuditService>();
await auditService.runner.run(
  operation: AuditOperationType.dailyForceRefetch,
  body: (audit) async {
    audit.stageStarted('daily_force_refetch');
    await provider.forceRefetchDailyBars(
      onProgress: (stage, current, total) {
        audit.stageProgress(stage, current: current, total: total);
      },
    );
    audit.record(AuditEventType.fetchResult, const {
      'updated_stock_count': 0,
      'total_records': 0,
    });
    audit.stageCompleted('daily_force_refetch');
  },
);
await auditService.refreshLatest();
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "daily force refetch should write latest audit summary" -r expanded`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart \
  test/screens/data_management_screen_test.dart
git commit -m "feat: audit daily force refetch operation"
```

---

### Task 8: 接入 historical/weekly/weekly-macd 审计事件并补严格失败原因

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `integration_test/support/data_management_fixtures.dart`
- Test: `test/screens/data_management_screen_test.dart`
- Test: `integration_test/features/data_management_offline_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('failed historical fetch should produce FAIL latest audit', (tester) async {
  final context = await launchDataManagementWithFixture(
    tester,
    preset: DataManagementFixturePreset.failedFetch,
  );
  final driver = DataManagementDriver(tester);

  await driver.tapHistoricalFetchMissing();
  await driver.expectProgressDialogVisible();
  await driver.waitForProgressDialogClosedWithWatchdog(context.createWatchdog());

  await tester.pumpAndSettle();
  expect(find.textContaining('FAIL'), findsWidgets);
  expect(find.textContaining('runtime_error'), findsWidgets);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "failed historical fetch should produce FAIL latest audit" -r expanded`  
Expected: FAIL because historical/weekly paths are not audited yet.

**Step 3: Write minimal implementation**

In `lib/screens/data_management_screen.dart`:

1. Wrap `_fetchHistoricalKline` in audit runner.
2. Wrap `_fetchWeeklyKline` in audit runner.
3. Wrap weekly MACD recompute trigger flow in audit runner.
4. Emit strict-fail evidence events:
   - verification counts (`missing_count`, `incomplete_count`)
   - unknown completeness state when observed
   - runtime errors in catch blocks.
5. Refresh latest summary after each audited operation.

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/screens/data_management_screen_test.dart -r compact
flutter test integration_test/features/data_management_offline_test.dart -d macos -r compact
```

Expected: PASS; offline integration still green.

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart \
  integration_test/support/data_management_fixtures.dart \
  test/screens/data_management_screen_test.dart \
  integration_test/features/data_management_offline_test.dart
git commit -m "feat: audit all data-management operations with strict failure reasons"
```

---

### Task 9: 实现 Diagnostic Console UI（$frontend-design：高信号控制台风格）

**Files:**
- Create: `lib/widgets/data_management_audit_console.dart`
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `lib/theme/app_colors.dart`
- Modify: `lib/theme/app_text_styles.dart`
- Test: `test/widgets/data_management_audit_console_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/widgets/data_management_audit_console.dart';

void main() {
  testWidgets('shows FAIL rail and reason chips', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DataManagementAuditConsole(
            title: 'Latest Audit',
            verdictLabel: 'FAIL',
            operationLabel: 'daily_force_refetch',
            completedAtLabel: '2026-02-16 12:01:03',
            reasonCodes: ['unknown_state', 'missing_after_fetch'],
            metricsLabel: 'errors 1 · missing 2 · elapsed 16305ms',
          ),
        ),
      ),
    );

    expect(find.text('Latest Audit'), findsOneWidget);
    expect(find.text('FAIL'), findsOneWidget);
    expect(find.text('unknown_state'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/data_management_audit_console_test.dart -r expanded`  
Expected: FAIL with missing widget file.

**Step 3: Write minimal implementation**

Build a dedicated widget matching Diagnostic Console direction:

1. Left verdict rail (pass/fail accent color).
2. Center summary (operation/time/reasons/metrics).
3. Right action buttons (`View Details`, `Export Latest`).

Minimal skeleton:

```dart
class DataManagementAuditConsole extends StatelessWidget {
  const DataManagementAuditConsole({
    super.key,
    required this.title,
    required this.verdictLabel,
    required this.operationLabel,
    required this.completedAtLabel,
    required this.reasonCodes,
    required this.metricsLabel,
    this.onViewDetails,
    this.onExportLatest,
  });
  // ...
}
```

Then render this widget at top of `DataManagementScreen`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widgets/data_management_audit_console_test.dart test/screens/data_management_screen_test.dart -r compact`  
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/widgets/data_management_audit_console.dart \
  lib/screens/data_management_screen.dart \
  lib/theme/app_colors.dart \
  lib/theme/app_text_styles.dart \
  test/widgets/data_management_audit_console_test.dart \
  test/screens/data_management_screen_test.dart
git commit -m "feat: add diagnostic audit console to data management screen"
```

---

### Task 10: 实现导出交互（Latest / Last 7 Days）与详情弹层

**Files:**
- Modify: `lib/screens/data_management_screen.dart`
- Modify: `integration_test/support/data_management_driver.dart`
- Test: `test/screens/data_management_screen_test.dart`
- Test: `integration_test/features/data_management_offline_test.dart`

**Step 1: Write the failing test**

```dart
testWidgets('export latest audit action should show success snackbar', (tester) async {
  final context = await launchDataManagementWithFixture(tester);
  final driver = DataManagementDriver(tester);

  await driver.tapDailyForceRefetch();
  await driver.waitForProgressDialogClosedWithWatchdog(context.createWatchdog());

  await driver.tapExportLatestAudit();
  await driver.expectSnackBarContains('审计日志已导出');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/screens/data_management_screen_test.dart --plain-name "export latest audit action should show success snackbar" -r expanded`  
Expected: FAIL because export UI action not implemented.

**Step 3: Write minimal implementation**

1. Add actions to Diagnostic Console:
   - `Export Latest Audit`
   - menu item `Export Last 7 Days`.
2. Trigger `auditService.exporter.exportLatestRun(...)` and `exportRecentDays(days: 7)`.
3. Show snackbar with exported path on success.
4. Add detail sheet showing reason list + metrics.

**Step 4: Run test to verify it passes**

Run:

```bash
flutter test test/screens/data_management_screen_test.dart -r compact
flutter test integration_test/features/data_management_offline_test.dart -d macos -r compact
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib/screens/data_management_screen.dart \
  integration_test/support/data_management_driver.dart \
  test/screens/data_management_screen_test.dart \
  integration_test/features/data_management_offline_test.dart
git commit -m "feat: add audit export actions and details sheet"
```

---

### Task 11: 回归验证与文档补充

**Files:**
- Modify: `README.md`
- Create: `docs/reports/data-management-audit-export-verification-2026-02-16.md`

**Step 1: Write the failing test/checklist**

Add a verification checklist in report draft requiring:

1. all new audit unit tests pass,
2. data management widget/integration suites pass,
3. latest audit UI shows deterministic verdict for pass and fail presets.

**Step 2: Run verification commands**

Run:

```bash
flutter test test/audit -r compact
flutter test test/widgets/data_management_audit_console_test.dart -r compact
flutter test test/screens/data_management_screen_test.dart -r compact
flutter test integration_test/features/data_management_offline_test.dart -d macos -r compact
```

Expected: all PASS.

**Step 3: Write minimal docs implementation**

1. `README.md`: add short section "Data Management Audit Export" with capabilities and location.
2. `docs/reports/data-management-audit-export-verification-2026-02-16.md`: include command outputs summary and known limitations.

**Step 4: Re-run targeted checks for changed docs references**

Run: `rg -n "Data Management Audit Export|Latest Audit|Export Latest Audit" README.md docs/reports/data-management-audit-export-verification-2026-02-16.md`  
Expected: 3+ matched lines confirming docs update.

**Step 5: Commit**

```bash
git add README.md \
  docs/reports/data-management-audit-export-verification-2026-02-16.md
git commit -m "docs: add audit export usage and verification report"
```

---

## 最终验收门槛

1. 每个 V1 范围内 Data Management 操作都写入结构化审计事件。
2. `Latest Audit` 在 UI 可见并给出严格可靠性 PASS/FAIL。
3. FAIL 场景展示明确 reason code（例如 `unknown_state`、`missing_after_fetch`、`runtime_error`）。
4. `Export Latest Audit` 与 `Export Last 7 Days` 可用。
5. 延迟指标被记录，但不会单独触发 FAIL（符合“可靠性优先”）。

## 风险与防回归注意事项

1. 审计写入失败不可阻断主业务；需在审计路径 swallow + 标记 warning。
2. 避免通过 UI 文案解析业务状态；统一使用结构化 payload。
3. 先做 daily 垂直切片，再扩展到 historical/weekly，避免大爆炸改动。
4. 避免在单个 task 混入无关性能优化，保持 commit 可回滚、可追责。

