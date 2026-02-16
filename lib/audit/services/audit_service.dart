import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/audit/models/audit_run_summary.dart';
import 'package:stock_rtwatcher/audit/services/audit_export_service.dart';
import 'package:stock_rtwatcher/audit/services/audit_operation_runner.dart';
import 'package:stock_rtwatcher/audit/storage/audit_log_store.dart';
import 'package:stock_rtwatcher/audit/storage/latest_audit_index_store.dart';

typedef ReadLatestAuditSummary = Future<AuditRunSummary?> Function();

class AuditService extends ChangeNotifier {
  AuditService({
    AuditOperationRunner? runner,
    AuditExportService? exporter,
    LatestAuditIndexStore? latestIndexStore,
    ReadLatestAuditSummary? readLatest,
  }) : _latestIndexStore = latestIndexStore ?? LatestAuditIndexStore(),
       _runner =
           runner ??
           AuditOperationRunner(
             sink: FileAuditSink(
               logStore: AuditLogStore(),
               indexStore: latestIndexStore,
             ),
           ),
       _exporter = exporter ?? AuditExportService(),
       _readLatest = readLatest;

  final AuditOperationRunner _runner;
  final AuditExportService _exporter;
  final LatestAuditIndexStore _latestIndexStore;
  final ReadLatestAuditSummary? _readLatest;
  final StreamController<AuditRunSummary?> _latestSummaryController =
      StreamController<AuditRunSummary?>.broadcast();

  AuditRunSummary? _latest;

  AuditOperationRunner get runner => _runner;
  AuditExportService get exporter => _exporter;
  AuditRunSummary? get latest => _latest;
  Stream<AuditRunSummary?> get latestSummaryStream =>
      _latestSummaryController.stream;

  Future<void> refreshLatest() async {
    AuditRunSummary? latest = _latest;
    try {
      latest = await (_readLatest?.call() ?? _latestIndexStore.readLatest());
    } catch (error) {
      debugPrint('[AuditService] refreshLatest failed: $error');
    }
    _latest = latest;
    if (!_latestSummaryController.isClosed) {
      _latestSummaryController.add(latest);
    }
    notifyListeners();
  }

  static AuditService forTest({
    required AuditOperationRunner runner,
    required AuditExportService exporter,
    required ReadLatestAuditSummary readLatest,
  }) {
    return AuditService(
      runner: runner,
      exporter: exporter,
      readLatest: readLatest,
    );
  }

  @override
  void dispose() {
    _latestSummaryController.close();
    super.dispose();
  }
}
