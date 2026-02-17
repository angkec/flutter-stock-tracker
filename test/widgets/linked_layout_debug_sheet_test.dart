import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';
import 'package:stock_rtwatcher/widgets/linked_layout_debug_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('updates config values and supports reset to defaults', (
    tester,
  ) async {
    final service = LinkedLayoutConfigService();
    await service.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<LinkedLayoutConfigService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(body: LinkedLayoutDebugSheet()),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('linked_layout_main_min_input')),
      '100',
    );
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(service.config.mainMinHeight, 100);

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    expect(service.config.mainMinHeight, 92);
  });
}
