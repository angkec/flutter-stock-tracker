import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

/// 股票监控数据
class StockMonitorData {
  final Stock stock;
  final double ratio; // 当日涨跌量比

  StockMonitorData({
    required this.stock,
    required this.ratio,
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
    // 获取当日1分钟K线数据 (一天最多240根: 9:30-11:30 + 13:00-15:00)
    final bars1m = await _client.getSecurityBars(
      market: stock.market,
      code: stock.code,
      category: klineType1Min,
      start: 0,
      count: 240,
    );

    // 只保留当日的K线
    final today = DateTime.now();
    final todayBars = bars1m.where((bar) =>
        bar.datetime.year == today.year &&
        bar.datetime.month == today.month &&
        bar.datetime.day == today.day).toList();

    final ratio = calculateRatio(todayBars);

    return StockMonitorData(
      stock: stock,
      ratio: ratio,
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
}
