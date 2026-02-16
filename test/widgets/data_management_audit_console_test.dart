import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
