import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/widgets/linked_crosshair_models.dart';
import 'package:stock_rtwatcher/widgets/linked_kline_mapper.dart';

class LinkedCrosshairCoordinator extends ValueNotifier<LinkedCrosshairState?> {
  LinkedCrosshairCoordinator({
    required this.weeklyBars,
    required this.dailyBars,
  }) : super(null);

  final List<KLine> weeklyBars;
  final List<KLine> dailyBars;

  int? mappedWeeklyIndex;
  int? mappedDailyIndex;

  DateTime? get mappedWeeklyDate {
    final index = mappedWeeklyIndex;
    if (index == null || index < 0 || index >= weeklyBars.length) {
      return null;
    }
    return weeklyBars[index].datetime;
  }

  DateTime? get mappedDailyDate {
    final index = mappedDailyIndex;
    if (index == null || index < 0 || index >= dailyBars.length) {
      return null;
    }
    return dailyBars[index].datetime;
  }

  LinkedCrosshairState? stateForPane(LinkedPane pane) {
    final current = value;
    if (current == null) {
      return null;
    }

    final mappedDate = pane == LinkedPane.weekly
        ? mappedWeeklyDate
        : mappedDailyDate;
    if (mappedDate == null) {
      return current;
    }
    return current.copyWith(anchorDate: mappedDate);
  }

  void handleTouch(LinkedTouchEvent event) {
    if (event.phase == LinkedTouchPhase.end) {
      value = null;
      mappedWeeklyIndex = null;
      mappedDailyIndex = null;
      return;
    }

    if (event.pane == LinkedPane.weekly) {
      mappedWeeklyIndex =
          event.barIndex >= 0 && event.barIndex < weeklyBars.length
          ? event.barIndex
          : LinkedKlineMapper.findIndexByDate(
              bars: weeklyBars,
              date: event.date,
            );
      mappedDailyIndex = LinkedKlineMapper.findDailyIndexForWeeklyDate(
        dailyBars: dailyBars,
        weeklyDate: event.date,
      );
    } else {
      mappedDailyIndex =
          event.barIndex >= 0 && event.barIndex < dailyBars.length
          ? event.barIndex
          : LinkedKlineMapper.findIndexByDate(
              bars: dailyBars,
              date: event.date,
            );
      mappedWeeklyIndex = LinkedKlineMapper.findWeeklyIndexForDailyDate(
        weeklyBars: weeklyBars,
        dailyDate: event.date,
      );
    }

    value = LinkedCrosshairState(
      sourcePane: event.pane,
      anchorDate: event.date,
      anchorPrice: event.price,
      isLinking: true,
    );
    notifyListeners();
  }
}
