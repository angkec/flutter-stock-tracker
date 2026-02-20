import 'package:stock_rtwatcher/models/kline.dart';

class SwDailyBar {
  final String tsCode;
  final DateTime tradeDate;
  final String? name;
  final double open;
  final double high;
  final double low;
  final double close;
  final double change;
  final double pctChange;
  final double volume;
  final double amount;
  final double? pe;
  final double? pb;
  final double? floatMv;
  final double? totalMv;

  const SwDailyBar({
    required this.tsCode,
    required this.tradeDate,
    this.name,
    this.open = 0,
    this.high = 0,
    this.low = 0,
    this.close = 0,
    this.change = 0,
    this.pctChange = 0,
    this.volume = 0,
    this.amount = 0,
    this.pe,
    this.pb,
    this.floatMv,
    this.totalMv,
  });

  factory SwDailyBar.fromTushareMap(Map<String, dynamic> map) {
    return SwDailyBar(
      tsCode: map['ts_code']?.toString() ?? '',
      tradeDate: _parseDate(map['trade_date']),
      name: map['name']?.toString(),
      open: _toDouble(map['open']),
      high: _toDouble(map['high']),
      low: _toDouble(map['low']),
      close: _toDouble(map['close']),
      change: _toDouble(map['change']),
      pctChange: _toDouble(map['pct_change']),
      volume: _toDouble(map['vol']),
      amount: _toDouble(map['amount']),
      pe: _toNullableDouble(map['pe']),
      pb: _toNullableDouble(map['pb']),
      floatMv: _toNullableDouble(map['float_mv']),
      totalMv: _toNullableDouble(map['total_mv']),
    );
  }

  KLine toKLine() {
    return KLine(
      datetime: DateTime(tradeDate.year, tradeDate.month, tradeDate.day),
      open: open,
      close: close,
      high: high,
      low: low,
      volume: volume,
      amount: amount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ts_code': tsCode,
      'trade_date': _formatDate(tradeDate),
      'name': name,
      'open': open,
      'high': high,
      'low': low,
      'close': close,
      'change': change,
      'pct_change': pctChange,
      'vol': volume,
      'amount': amount,
      'pe': pe,
      'pb': pb,
      'float_mv': floatMv,
      'total_mv': totalMv,
    };
  }

  static DateTime _parseDate(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.length != 8) {
      throw FormatException('Invalid trade_date: $value');
    }
    final year = int.parse(raw.substring(0, 4));
    final month = int.parse(raw.substring(4, 6));
    final day = int.parse(raw.substring(6, 8));
    return DateTime(year, month, day);
  }

  static String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year$month$day';
  }

  static double _toDouble(dynamic value) {
    return (value as num?)?.toDouble() ?? 0;
  }

  static double? _toNullableDouble(dynamic value) {
    return (value as num?)?.toDouble();
  }
}
