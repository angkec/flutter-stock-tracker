import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/data_management_driver.dart';

void main() {
  testWidgets(
    'waitForProgressDialogTextContainsOrClosed returns true when keyword appears',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(
                        title: Text('拉取历史数据'),
                        content: Text('速率 2.0只/秒 · 预计剩余 8s'),
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();

      final driver = DataManagementDriver(tester);
      final observed = await driver.waitForProgressDialogTextContainsOrClosed(
        '速率',
        timeout: const Duration(seconds: 1),
        waitAppearTimeout: const Duration(milliseconds: 800),
      );
      expect(observed, isTrue);
    },
  );

  testWidgets(
    'waitForProgressDialogTextContainsOrClosed returns false when dialog closes early',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(
                        title: Text('拉取历史数据'),
                        content: Text('准备中...'),
                      ),
                    );
                    Future<void>.delayed(const Duration(milliseconds: 120), () {
                      if (context.mounted && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    });
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();

      final driver = DataManagementDriver(tester);
      final stopwatch = Stopwatch()..start();
      final observed = await driver.waitForProgressDialogTextContainsOrClosed(
        '速率',
        timeout: const Duration(seconds: 5),
        waitAppearTimeout: const Duration(milliseconds: 800),
      );
      stopwatch.stop();

      expect(observed, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );
}
