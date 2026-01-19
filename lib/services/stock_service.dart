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

  // 最大有效量比阈值 (超过此值认为是涨停/跌停/异常)
  static const double maxValidRatio = 50.0;
  // 最小K线数量 (少于此值认为是停盘或数据不足)
  static const int minBarsCount = 10;

  /// 计算量比 (涨量/跌量)
  /// 返回上涨K线成交量之和与下跌K线成交量之和的比值
  /// 返回 null 表示数据无效 (涨停/跌停/停盘等)
  static double? calculateRatio(List<KLine> bars) {
    // K线数量太少，可能是停盘或刚开盘
    if (bars.length < minBarsCount) {
      return null;
    }

    double upVolume = 0;
    double downVolume = 0;
    int upCount = 0;
    int downCount = 0;

    for (final bar in bars) {
      if (bar.isUp) {
        upVolume += bar.volume;
        upCount++;
      } else if (bar.isDown) {
        downVolume += bar.volume;
        downCount++;
      }
      // 平盘K线 (open == close) 不计入
    }

    // 没有下跌K线 (可能是涨停)
    if (downVolume == 0 || downCount == 0) {
      return null;
    }

    // 没有上涨K线 (可能是跌停)
    if (upVolume == 0 || upCount == 0) {
      return null;
    }

    final ratio = upVolume / downVolume;

    // 量比过高，可能是接近涨停/跌停
    if (ratio > maxValidRatio || ratio < 1 / maxValidRatio) {
      return null;
    }

    return ratio;
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

      // 跳过无效数据 (涨停/跌停/停盘等)
      if (ratio == null) continue;

      results.add(StockMonitorData(
        stock: stocks[i],
        ratio: ratio,
      ));
    }

    return results;
  }
}
