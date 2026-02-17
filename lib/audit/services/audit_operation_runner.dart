import 'dart:math';

import 'package:stock_rtwatcher/audit/models/audit_event.dart';
import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/models/audit_verdict.dart';
import 'package:stock_rtwatcher/audit/services/audit_verdict_engine.dart';
import 'package:stock_rtwatcher/audit/storage/audit_log_store.dart';
import 'package:stock_rtwatcher/audit/storage/latest_audit_index_store.dart';

abstract class AuditSink {
  Future<void> append(AuditEvent event);
  Future<void> appendAll(List<AuditEvent> events);

  Future<void> saveLatest(AuditRunSummary summary);
}

class FileAuditSink implements AuditSink {
  FileAuditSink({AuditLogStore? logStore, LatestAuditIndexStore? indexStore})
    : _logStore = logStore ?? AuditLogStore(),
      _indexStore = indexStore ?? LatestAuditIndexStore();

  final AuditLogStore _logStore;
  final LatestAuditIndexStore _indexStore;

  @override
  Future<void> append(AuditEvent event) {
    return _logStore.append(event);
  }

  @override
  Future<void> appendAll(List<AuditEvent> events) {
    return _logStore.appendAll(events);
  }

  @override
  Future<void> saveLatest(AuditRunSummary summary) {
    return _indexStore.save(summary);
  }
}

class MemoryAuditSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];
  AuditRunSummary? latestSummary;

  @override
  Future<void> append(AuditEvent event) async {
    events.add(event);
  }

  @override
  Future<void> appendAll(List<AuditEvent> input) async {
    events.addAll(input);
  }

  @override
  Future<void> saveLatest(AuditRunSummary summary) async {
    latestSummary = summary;
  }
}

class AuditOperationContext {
  AuditOperationContext({
    required this.runId,
    required this.operation,
    required DateTime Function() nowProvider,
    required void Function(AuditEvent event) appendEvent,
  }) : _nowProvider = nowProvider,
       _appendEvent = appendEvent;

  final String runId;
  final AuditOperationType operation;
  final DateTime Function() _nowProvider;
  final void Function(AuditEvent event) _appendEvent;

  void stageStarted(String stage) {
    record(AuditEventType.stageStarted, {'stage': stage});
  }

  void stageProgress(String stage, {required int current, required int total}) {
    record(AuditEventType.stageProgress, {
      'stage': stage,
      'current': current,
      'total': total,
    });
  }

  void stageCompleted(String stage, {int? durationMs}) {
    final payload = <String, Object?>{'stage': stage};
    if (durationMs != null) {
      payload['duration_ms'] = durationMs;
    }
    record(AuditEventType.stageCompleted, payload);
  }

  void record(AuditEventType eventType, Map<String, Object?> payload) {
    _appendEvent(
      AuditEvent(
        ts: _nowProvider(),
        runId: runId,
        operation: operation,
        eventType: eventType,
        payload: payload,
      ),
    );
  }
}

class AuditOperationRunner {
  AuditOperationRunner({
    required AuditSink sink,
    AuditVerdictEngine? verdictEngine,
    DateTime Function()? nowProvider,
  }) : _sink = sink,
       _verdictEngine = verdictEngine ?? AuditVerdictEngine(),
       _nowProvider = nowProvider ?? DateTime.now;

  final AuditSink _sink;
  final AuditVerdictEngine _verdictEngine;
  final DateTime Function() _nowProvider;
  final Random _random = Random();

  Future<AuditRunSummary> run({
    required AuditOperationType operation,
    required Future<void> Function(AuditOperationContext ctx) body,
  }) async {
    final runId = _newRunId();
    final startedAt = _nowProvider();
    final events = <AuditEvent>[];

    void appendEvent(AuditEvent event) {
      events.add(event);
    }

    final ctx = AuditOperationContext(
      runId: runId,
      operation: operation,
      nowProvider: _nowProvider,
      appendEvent: appendEvent,
    );

    ctx.record(AuditEventType.runStarted, const <String, Object?>{});

    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await body(ctx);
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
      ctx.record(AuditEventType.errorRaised, {'message': '$error'});
    }

    final completedAt = _nowProvider();
    ctx.record(AuditEventType.runCompleted, const <String, Object?>{});

    var summary = _verdictEngine.evaluate(
      runId: runId,
      operation: operation,
      startedAt: startedAt,
      completedAt: completedAt,
      events: events,
    );

    var hasAuditWriteFailure = false;
    try {
      await _sink.appendAll(events);
    } catch (_) {
      hasAuditWriteFailure = true;
    }
    if (hasAuditWriteFailure) {
      summary = _withAuditWriteWarning(summary);
    }

    try {
      await _sink.saveLatest(summary);
    } catch (_) {
      summary = _withAuditWriteWarning(summary);
      try {
        await _sink.saveLatest(summary);
      } catch (_) {
        // Audit persistence must never break core operation flow.
      }
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }

    return summary;
  }

  String _newRunId() {
    final now = _nowProvider();
    final suffix = _random.nextInt(1 << 20).toRadixString(16).padLeft(5, '0');
    return 'audit-${now.microsecondsSinceEpoch}-$suffix';
  }

  AuditRunSummary _withAuditWriteWarning(AuditRunSummary summary) {
    final reasonCodes = <String>{...summary.reasonCodes, 'audit_write_warning'}
      ..removeWhere((code) => code.trim().isEmpty);

    return AuditRunSummary(
      runId: summary.runId,
      operation: summary.operation,
      startedAt: summary.startedAt,
      completedAt: summary.completedAt,
      verdict: AuditVerdict.fail,
      reasonCodes: reasonCodes.toList()..sort(),
      errorCount: summary.errorCount,
      missingCount: summary.missingCount,
      incompleteCount: summary.incompleteCount,
      unknownStateCount: summary.unknownStateCount,
      updatedStockCount: summary.updatedStockCount,
      totalRecords: summary.totalRecords,
      elapsedMs: summary.elapsedMs,
      stageDurationsMs: summary.stageDurationsMs,
    );
  }
}
