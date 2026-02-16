import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/testing/progress_watchdog.dart';

class DataManagementDriver {
  DataManagementDriver(this.tester);

  final WidgetTester tester;

  Future<void> ensureCardVisible(String cardTitle) async {
    final titleFinder = find.text(cardTitle);
    if (titleFinder.evaluate().isNotEmpty) {
      return;
    }

    final listView = find.byType(ListView);
    if (listView.evaluate().isEmpty) {
      throw StateError(
        'No ListView found when trying to locate card: $cardTitle',
      );
    }

    for (var i = 0; i < 12; i++) {
      await tester.drag(listView.first, const Offset(0, -260));
      await tester.pumpAndSettle();
      if (titleFinder.evaluate().isNotEmpty) {
        return;
      }
    }

    for (var i = 0; i < 12; i++) {
      await tester.drag(listView.first, const Offset(0, 260));
      await tester.pumpAndSettle();
      if (titleFinder.evaluate().isNotEmpty) {
        return;
      }
    }

    throw StateError('Unable to scroll card into view: $cardTitle');
  }

  Future<void> tapHistoricalFetchMissing({
    bool allowForceFallback = false,
  }) async {
    await ensureCardVisible('历史分钟K线');
    final deadline = DateTime.now().add(const Duration(seconds: 4));

    while (DateTime.now().isBefore(deadline)) {
      final missingButton = _buttonInCard('历史分钟K线', '拉取缺失');
      if (missingButton.evaluate().isNotEmpty) {
        await tester.tap(missingButton.first);
        await tester.pump();
        return;
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    if (allowForceFallback) {
      final forceButton = _buttonInCard('历史分钟K线', '强制重拉');
      if (forceButton.evaluate().isNotEmpty) {
        await tester.tap(forceButton.first);
        await tester.pump();
        await _confirmForceRefetch();
        return;
      }
    }

    final labels = _cardButtonLabels('历史分钟K线');
    throw StateError(
      'Historical missing-fetch button not found. labels=$labels',
    );
  }

  Future<void> tapWeeklyFetchMissing() async {
    await _tapCardButton('周K数据', '拉取缺失');
  }

  Future<void> tapWeeklyForceRefetch() async {
    await _tapCardButton('周K数据', '强制重拉');
    await _confirmForceRefetch();
  }

  Future<void> tapDailyForceRefetch() async {
    await _tapCardButton('日K数据', '强制拉取');
    await _confirmForceRefetch();
  }

  Future<void> tapHistoricalRecheck() async {
    await _tapCardButton('历史分钟K线', '重新检测');
  }

  Future<void> tapWeeklyMacdSettings() async {
    await _tapCardButton('周线MACD参数设置', '进入');
    await tester.pumpAndSettle();
    expect(find.text('周线MACD设置'), findsOneWidget);
  }

  Future<void> tapWeeklyMacdRecompute() async {
    Finder recomputeButton = find.byKey(
      const ValueKey('macd_recompute_weekly'),
    );
    if (recomputeButton.evaluate().isEmpty) {
      recomputeButton = find.text('重算周线MACD');
    }

    if (recomputeButton.evaluate().isEmpty) {
      final listView = find.byType(ListView);
      for (var i = 0; i < 16; i++) {
        await tester.drag(listView.first, const Offset(0, -260));
        await tester.pumpAndSettle();
        recomputeButton = find.byKey(const ValueKey('macd_recompute_weekly'));
        if (recomputeButton.evaluate().isNotEmpty) {
          break;
        }
        recomputeButton = find.text('重算周线MACD');
        if (recomputeButton.evaluate().isNotEmpty) {
          break;
        }
      }
    }

    expect(recomputeButton, findsOneWidget);
    await tester.ensureVisible(recomputeButton.first);
    await tester.tap(recomputeButton.first, warnIfMissed: false);
    await tester.pump();
  }

  Future<void> expectProgressDialogVisible() async {
    expect(find.text('拉取历史数据'), findsOneWidget);
  }

  Future<void> expectMacdRecomputeDialogVisible(String scopeLabel) async {
    expect(find.text('重算$scopeLabel MACD'), findsOneWidget);
  }

  Future<void> waitForProgressDialogClosedWithWatchdog(
    ProgressWatchdog watchdog, {
    Duration hardTimeout = const Duration(seconds: 60),
  }) async {
    await waitForDialogClosedWithWatchdog(
      watchdog,
      dialogTitle: '拉取历史数据',
      hardTimeout: hardTimeout,
    );
  }

  Future<void> waitForMacdRecomputeDialogClosedWithWatchdog(
    ProgressWatchdog watchdog, {
    String scopeLabel = '周线',
    Duration hardTimeout = const Duration(minutes: 10),
  }) async {
    await waitForDialogClosedWithWatchdog(
      watchdog,
      dialogTitle: '重算$scopeLabel MACD',
      hardTimeout: hardTimeout,
    );
  }

  Future<void> waitForMacdRecomputeCompletionWithWatchdog(
    ProgressWatchdog watchdog, {
    String scopeLabel = '周线',
    Duration waitAppearTimeout = const Duration(seconds: 3),
    Duration hardTimeout = const Duration(minutes: 10),
  }) async {
    final title = '重算$scopeLabel MACD';
    final appearDeadline = DateTime.now().add(waitAppearTimeout);
    while (!_isDialogVisible(title) &&
        DateTime.now().isBefore(appearDeadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (_isDialogVisible(title)) {
      await waitForDialogClosedWithWatchdog(
        watchdog,
        dialogTitle: title,
        hardTimeout: hardTimeout,
      );
    }
  }

  Future<void> waitForProgressDialogTextContains(
    String keyword, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await waitForDialogTextContains(
      dialogTitle: '拉取历史数据',
      keyword: keyword,
      timeout: timeout,
    );
  }

  Future<bool> waitForProgressDialogTextContainsOrClosed(
    String keyword, {
    Duration timeout = const Duration(seconds: 30),
    Duration waitAppearTimeout = const Duration(seconds: 3),
  }) async {
    return waitForDialogTextContainsOrClosed(
      dialogTitle: '拉取历史数据',
      keyword: keyword,
      timeout: timeout,
      waitAppearTimeout: waitAppearTimeout,
    );
  }

  Future<bool> waitForDialogVisible(
    String dialogTitle, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      if (_resolveDialogByTitle(dialogTitle) != null) {
        return true;
      }
    }
    return false;
  }

  Future<bool> waitForMacdRecomputeDialogVisible({
    String scopeLabel = '周线',
    Duration timeout = const Duration(seconds: 3),
  }) async {
    return waitForDialogVisible('重算$scopeLabel MACD', timeout: timeout);
  }

  Future<void> waitForMacdRecomputeDialogTextContains(
    String keyword, {
    String scopeLabel = '周线',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await waitForDialogTextContains(
      dialogTitle: '重算$scopeLabel MACD',
      keyword: keyword,
      timeout: timeout,
    );
  }

  Future<bool> waitForMacdRecomputeDialogTextContainsOrClosed(
    String keyword, {
    String scopeLabel = '周线',
    Duration timeout = const Duration(seconds: 30),
    Duration waitAppearTimeout = const Duration(seconds: 3),
  }) async {
    return waitForDialogTextContainsOrClosed(
      dialogTitle: '重算$scopeLabel MACD',
      keyword: keyword,
      timeout: timeout,
      waitAppearTimeout: waitAppearTimeout,
    );
  }

  Future<void> waitForDialogTextContains({
    required String dialogTitle,
    required String keyword,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      final titleFinder = find.text(dialogTitle);
      if (titleFinder.evaluate().isEmpty) {
        continue;
      }

      final dialog = find.ancestor(
        of: titleFinder.first,
        matching: find.byType(AlertDialog),
      );
      if (dialog.evaluate().isEmpty) {
        continue;
      }

      final keywordFinder = find.descendant(
        of: dialog.first,
        matching: find.textContaining(keyword),
      );
      if (keywordFinder.evaluate().isNotEmpty) {
        return;
      }
    }

    throw TimeoutException(
      'Did not observe dialog text in time: dialogTitle=$dialogTitle, keyword=$keyword',
    );
  }

  Future<bool> waitForDialogTextContainsOrClosed({
    required String dialogTitle,
    required String keyword,
    Duration timeout = const Duration(seconds: 30),
    Duration waitAppearTimeout = const Duration(seconds: 3),
  }) async {
    final appearDeadline = DateTime.now().add(waitAppearTimeout);
    Finder? dialog;
    while (DateTime.now().isBefore(appearDeadline)) {
      await tester.pump(const Duration(milliseconds: 200));
      dialog = _resolveDialogByTitle(dialogTitle);
      if (dialog != null) {
        break;
      }
    }
    if (dialog == null) {
      return false;
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final activeDialog = _resolveDialogByTitle(dialogTitle);
      if (activeDialog == null) {
        return false;
      }
      final keywordFinder = find.descendant(
        of: activeDialog,
        matching: find.textContaining(keyword),
      );
      if (keywordFinder.evaluate().isNotEmpty) {
        return true;
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    return false;
  }

  Finder? _resolveDialogByTitle(String dialogTitle) {
    final titleFinder = find.text(dialogTitle);
    if (titleFinder.evaluate().isEmpty) {
      return null;
    }
    final dialog = find.ancestor(
      of: titleFinder.first,
      matching: find.byType(AlertDialog),
    );
    if (dialog.evaluate().isEmpty) {
      return null;
    }
    return dialog.first;
  }

  Future<void> waitForDialogClosedWithWatchdog(
    ProgressWatchdog watchdog, {
    required String dialogTitle,
    Duration hardTimeout = const Duration(seconds: 60),
  }) async {
    final startAt = DateTime.now();

    while (_isDialogVisible(dialogTitle)) {
      await tester.pump(const Duration(milliseconds: 200));

      final signal = _readBusinessSignal(dialogTitle);
      if (signal != null && signal.isNotEmpty) {
        watchdog.markProgress(signal);
      }
      watchdog.assertNotStalled();

      final elapsed = DateTime.now().difference(startAt);
      if (elapsed > hardTimeout) {
        throw TimeoutException(
          'Progress dialog did not close in time. elapsed=$elapsed',
        );
      }
    }

    await tester.pumpAndSettle();
  }

  Future<void> expectSnackBarContains(String text) async {
    await tester.pump();
    expect(find.textContaining(text), findsWidgets);
  }

  Future<bool> isHistoricalPrimaryActionEnabled() async {
    await ensureCardVisible('历史分钟K线');
    var button = _buttonInCard('历史分钟K线', '拉取缺失');
    if (button.evaluate().isEmpty) {
      button = _buttonInCard('历史分钟K线', '强制重拉');
    }
    if (button.evaluate().isEmpty) {
      return false;
    }
    final widget = tester.widget<ButtonStyleButton>(button.first);
    return widget.enabled;
  }

  Future<void> _tapCardButton(String cardTitle, String label) async {
    await ensureCardVisible(cardTitle);
    final button = _buttonInCard(cardTitle, label);
    expect(button, findsAtLeastNWidgets(1));
    await tester.tap(button.first);
    await tester.pump();
  }

  Finder _buttonInCard(String cardTitle, String label) {
    final tile = find.widgetWithText(ListTile, cardTitle);
    final card = find.ancestor(of: tile.first, matching: find.byType(Card));
    final button = find.descendant(
      of: card.first,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! ButtonStyleButton) {
          return false;
        }
        final child = widget.child;
        if (child is Text) {
          return child.data == label;
        }
        return false;
      }),
    );
    return button;
  }

  Future<void> _confirmForceRefetch() async {
    expect(find.text('确认强制拉取'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '确定'));
    await tester.pump();
  }

  bool _isDialogVisible(String title) {
    return find.text(title).evaluate().isNotEmpty;
  }

  String? _readBusinessSignal(String dialogTitle) {
    final titleFinder = find.text(dialogTitle);
    if (titleFinder.evaluate().isEmpty) {
      return null;
    }

    final dialog = find.ancestor(
      of: titleFinder.first,
      matching: find.byType(AlertDialog),
    );
    if (dialog.evaluate().isEmpty) {
      return null;
    }

    final texts = find
        .descendant(of: dialog.first, matching: find.byType(Text))
        .evaluate()
        .map((element) => element.widget)
        .whereType<Text>()
        .map((text) => text.data ?? '')
        .where((text) => text.trim().isNotEmpty)
        .toList(growable: false);

    return texts.join('|');
  }

  List<String> _cardButtonLabels(String cardTitle) {
    final tile = find.widgetWithText(ListTile, cardTitle);
    final card = find.ancestor(of: tile.first, matching: find.byType(Card));
    return find
        .descendant(of: card.first, matching: find.byType(ButtonStyleButton))
        .evaluate()
        .map((element) => element.widget)
        .whereType<ButtonStyleButton>()
        .map((button) => button.child)
        .whereType<Text>()
        .map((text) => text.data ?? '')
        .toList(growable: false);
  }
}
