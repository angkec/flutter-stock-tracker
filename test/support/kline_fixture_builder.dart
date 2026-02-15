import 'package:stock_rtwatcher/models/kline.dart';

List<KLine> buildDailyBarsForTwoWeeks() {
  final dates = <DateTime>[
    DateTime(2026, 2, 2),
    DateTime(2026, 2, 3),
    DateTime(2026, 2, 4),
    DateTime(2026, 2, 5),
    DateTime(2026, 2, 6),
    DateTime(2026, 2, 9),
    DateTime(2026, 2, 10),
    DateTime(2026, 2, 11),
    DateTime(2026, 2, 12),
    DateTime(2026, 2, 13),
  ];

  return List<KLine>.generate(dates.length, (index) {
    final open = 10 + index * 0.2;
    return KLine(
      datetime: dates[index],
      open: open,
      close: open + 0.1,
      high: open + 0.2,
      low: open - 0.2,
      volume: 1000 + index * 100,
      amount: 10000 + index * 1000,
    );
  });
}

List<KLine> buildWeeklyBars() {
  final dates = <DateTime>[DateTime(2026, 2, 6), DateTime(2026, 2, 13)];

  return List<KLine>.generate(dates.length, (index) {
    final open = 10.0 + index;
    return KLine(
      datetime: dates[index],
      open: open,
      close: open + 0.8,
      high: open + 1,
      low: open - 0.5,
      volume: 10000 + index * 2000,
      amount: 100000 + index * 30000,
    );
  });
}

List<KLine> buildDailyBars({required int count, DateTime? startDate}) {
  final start = startDate ?? DateTime(2026, 1, 1);
  return List<KLine>.generate(count, (index) {
    final date = start.add(Duration(days: index));
    final open = 10 + index * 0.1;
    return KLine(
      datetime: date,
      open: open,
      close: open + 0.05,
      high: open + 0.15,
      low: open - 0.15,
      volume: 1000 + index * 10,
      amount: 10000 + index * 100,
    );
  });
}
