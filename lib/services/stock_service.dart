import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

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
  final TdxPool _pool;

  StockService(this._pool);

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
    final szCount = await _pool.getSecurityCount(0);
    for (var start = 0; start < szCount; start += 1000) {
      final batch = await _pool.getSecurityList(0, start);
      stocks.addAll(batch.where((s) => s.isValidAStock));
    }

    // 获取上海市场股票 (market=1)
    final shCount = await _pool.getSecurityCount(1);
    for (var start = 0; start < shCount; start += 1000) {
      final batch = await _pool.getSecurityList(1, start);
      stocks.addAll(batch.where((s) => s.isValidAStock));
    }

    return stocks;
  }

  /// 批量获取股票监控数据 (并行)
  Future<List<StockMonitorData>> batchGetMonitorData(
    List<Stock> stocks, {
    void Function(int current, int total)? onProgress,
  }) async {
    // 并行获取所有股票的1分钟K线
    final allBars = await _pool.batchGetSecurityBars(
      stocks: stocks,
      category: klineType1Min,
      start: 0,
      count: 240, // 一天最多240根1分钟K线
      onProgress: onProgress,
    );

    // 过滤当日数据并计算量比
    final today = DateTime.now();
    final results = <StockMonitorData>[];

    for (var i = 0; i < stocks.length; i++) {
      final bars = allBars[i];

      // 只保留当日的K线
      final todayBars = bars.where((bar) =>
          bar.datetime.year == today.year &&
          bar.datetime.month == today.month &&
          bar.datetime.day == today.day).toList();

      if (todayBars.isEmpty) continue;

      final ratio = calculateRatio(todayBars);

      results.add(StockMonitorData(
        stock: stocks[i],
        ratio: ratio,
      ));
    }

    return results;
  }
}
