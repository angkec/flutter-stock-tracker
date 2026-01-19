import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

/// 股票监控数据
class StockMonitorData {
  final Stock stock;
  final Quote quote;
  final double ratioDay;
  final double ratio30m;
  final bool is30mPartial;

  StockMonitorData({
    required this.stock,
    required this.quote,
    required this.ratioDay,
    required this.ratio30m,
    required this.is30mPartial,
  });
}

/// 股票服务
class StockService {
  final TdxClient _client;

  StockService(this._client);

  /// 计算量比 (涨量/跌量)
  /// 返回上涨K线成交量之和与下跌K线成交量之和的比值
  /// 如果没有下跌K线，返回999
  static double calculateRatio(List<KLine> bars) {
    double upVolume = 0;
    double downVolume = 0;

    for (final bar in bars) {
      if (bar.isUp) {
        upVolume += bar.volume;
      } else if (bar.isDown) {
        downVolume += bar.volume;
      }
      // 平盘K线 (open == close) 不计入
    }

    if (downVolume == 0) {
      return 999;
    }

    return upVolume / downVolume;
  }

  /// 获取所有A股股票
  Future<List<Stock>> getAllStocks() async {
    final stocks = <Stock>[];

    // 获取深圳市场股票 (market=0)
    final szCount = await _client.getSecurityCount(0);
    for (var start = 0; start < szCount; start += 1000) {
      final batch = await _client.getSecurityList(0, start);
      stocks.addAll(batch.where((s) => s.isValidAStock));
    }

    // 获取上海市场股票 (market=1)
    final shCount = await _client.getSecurityCount(1);
    for (var start = 0; start < shCount; start += 1000) {
      final batch = await _client.getSecurityList(1, start);
      stocks.addAll(batch.where((s) => s.isValidAStock));
    }

    return stocks;
  }

  /// 获取单只股票的监控数据
  Future<StockMonitorData> getStockMonitorData(Stock stock) async {
    // 获取实时行情
    final quotes = await _client.getSecurityQuotes([(stock.market, stock.code)]);
    if (quotes.isEmpty) {
      throw StateError('Failed to get quote for ${stock.code}');
    }
    final quote = quotes.first;

    // 获取日K线数据 (最近30根)
    final dailyBars = await _client.getSecurityBars(
      market: stock.market,
      code: stock.code,
      category: klineTypeDaily,
      start: 0,
      count: 30,
    );
    final ratioDay = calculateRatio(dailyBars);

    // 获取30分钟K线数据 (最近30根)
    final bars30m = await _client.getSecurityBars(
      market: stock.market,
      code: stock.code,
      category: klineType30Min,
      start: 0,
      count: 30,
    );
    final ratio30m = calculateRatio(bars30m);

    // 判断30分钟K线是否不完整 (交易时间内最后一根K线可能未收盘)
    final now = DateTime.now();
    final is30mPartial = bars30m.isNotEmpty &&
        _isWithinTradingHours(now) &&
        _isCurrentBar30m(bars30m.last.datetime, now);

    return StockMonitorData(
      stock: stock,
      quote: quote,
      ratioDay: ratioDay,
      ratio30m: ratio30m,
      is30mPartial: is30mPartial,
    );
  }

  /// 批量获取股票监控数据
  Future<List<StockMonitorData>> batchGetMonitorData(
    List<Stock> stocks, {
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <StockMonitorData>[];
    final total = stocks.length;

    for (var i = 0; i < total; i++) {
      try {
        final data = await getStockMonitorData(stocks[i]);
        results.add(data);
      } catch (e) {
        // 跳过获取失败的股票
      }

      onProgress?.call(i + 1, total);
    }

    return results;
  }

  /// 判断是否在交易时间内
  bool _isWithinTradingHours(DateTime time) {
    final hour = time.hour;
    final minute = time.minute;
    final timeMinutes = hour * 60 + minute;

    // 上午 9:30 - 11:30
    if (timeMinutes >= 9 * 60 + 30 && timeMinutes <= 11 * 60 + 30) {
      return true;
    }

    // 下午 13:00 - 15:00
    if (timeMinutes >= 13 * 60 && timeMinutes <= 15 * 60) {
      return true;
    }

    return false;
  }

  /// 判断给定时间是否属于当前30分钟K线
  bool _isCurrentBar30m(DateTime barTime, DateTime now) {
    // 30分钟K线的结束时间点: 10:00, 10:30, 11:00, 11:30, 13:30, 14:00, 14:30, 15:00
    final barMinutes = barTime.hour * 60 + barTime.minute;
    final nowMinutes = now.hour * 60 + now.minute;

    // 如果当前时间在该K线时间之后30分钟内，则认为是当前K线
    return nowMinutes >= barMinutes && nowMinutes < barMinutes + 30;
  }
}
