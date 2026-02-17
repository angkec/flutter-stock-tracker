import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/main.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('MyApp exposes LinkedLayoutConfigService via provider tree', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    final context = tester.element(find.byType(MaterialApp));
    final service = Provider.of<LinkedLayoutConfigService>(
      context,
      listen: false,
    );

    expect(service, isNotNull);
    expect(service.config.mainMinHeight, greaterThan(0));
  });
}
