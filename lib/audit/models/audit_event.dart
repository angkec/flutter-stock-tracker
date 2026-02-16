import 'dart:convert';

import 'package:stock_rtwatcher/audit/models/audit_operation_type.dart';

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

  Map<String, Object?> toJson() {
    return {
      'ts': ts.toIso8601String(),
      'run_id': runId,
      'operation': operation.wireName,
      'event_type': eventType.name,
      'payload': payload,
    };
  }

  static AuditEvent fromJson(Map<String, Object?> json) {
    final eventType = AuditEventType.values.firstWhere(
      (candidate) => candidate.name == json['event_type'],
    );
    return AuditEvent(
      ts: DateTime.parse(json['ts']! as String),
      runId: json['run_id']! as String,
      operation: AuditOperationTypeX.fromWireName(json['operation']! as String),
      eventType: eventType,
      payload: Map<String, Object?>.from((json['payload'] as Map?) ?? const {}),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! AuditEvent) {
      return false;
    }

    return ts == other.ts &&
        runId == other.runId &&
        operation == other.operation &&
        eventType == other.eventType &&
        jsonEncode(payload) == jsonEncode(other.payload);
  }

  @override
  int get hashCode {
    return Object.hash(
      ts,
      runId,
      operation,
      eventType,
      jsonEncode(payload),
    );
  }
}
