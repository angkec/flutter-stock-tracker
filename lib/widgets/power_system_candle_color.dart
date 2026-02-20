import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';

typedef CandleColorResolver = Color? Function(KLine bar, int globalIndex);

class PowerSystemCandleColor {
  static CandleColorResolver fromSeries(PowerSystemCacheSeries? series) {
    if (series == null || series.points.isEmpty) {
      return (bar, globalIndex) => null;
    }

    final stateByDate = <String, int>{
      for (final point in series.points) _dateKey(point.datetime): point.state,
    };

    return (bar, globalIndex) {
      final state = stateByDate[_dateKey(bar.datetime)];
      if (state == null) {
        return null;
      }
      if (state > 0) {
        return Colors.red;
      }
      if (state < 0) {
        return Colors.green;
      }
      return Colors.blue;
    };
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }
}
