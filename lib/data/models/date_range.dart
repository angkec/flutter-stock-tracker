// lib/data/models/date_range.dart

class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange(this.start, this.end);

  bool contains(DateTime date) {
    return !date.isBefore(start) && !date.isAfter(end);
  }

  Duration get duration => end.difference(start);

  @override
  String toString() => 'DateRange($start to $end)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}
