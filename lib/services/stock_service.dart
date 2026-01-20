import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

/// 股票监控数据
class StockMonitorData {
  final Stock stock;
  final double ratio;          // 涨跌量比
  final double changePercent;  // 当日涨跌幅 (%)
  final String? industry;      // 申万行业

  StockMonitorData({
    required this.stock,
    required this.ratio,
    required this.changePercent,
    this.industry,
  });

  Map<String, dynamic> toJson() => {
    'stock': stock.toJson(),
    'ratio': ratio,
    'changePercent': changePercent,
    'industry': industry,
  };

  factory StockMonitorData.fromJson(Map<String, dynamic> json) => StockMonitorData(
    stock: Stock.fromJson(json['stock'] as Map<String, dynamic>),
    ratio: (json['ratio'] as num).toDouble(),
    changePercent: (json['changePercent'] as num).toDouble(),
    industry: json['industry'] as String?,
  );
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

  /// 计算涨跌幅
  /// 返回 (最新价 - 参考价) / 参考价 * 100
  /// 参考价优先使用昨收价，若无效则使用当日首根K线开盘价
  static double? calculateChangePercent(List<KLine> todayBars, double preClose) {
    if (todayBars.isEmpty) return null;
    // 优先使用昨收价，若无效则使用当日首根K线开盘价
    final reference = preClose > 0 ? preClose : todayBars.first.open;
    if (reference <= 0) return null;
    final lastClose = todayBars.last.close;
    return (lastClose - reference) / reference * 100;
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

  /// 批量获取股票监控数据 (并行，流式返回)
  /// [onData] 当有新的有效数据时回调，返回当前所有有效结果
  Future<List<StockMonitorData>> batchGetMonitorData(
    List<Stock> stocks, {
    IndustryService? industryService,
    void Function(int current, int total)? onProgress,
    void Function(List<StockMonitorData> results)? onData,
  }) async {
    final today = DateTime.now();
    final results = <StockMonitorData>[];
    var completed = 0;
    final total = stocks.length;

    // 用于跟踪上次回调的结果数量
    var lastReportedCount = 0;
    const reportThreshold = 50; // 每增加50个有效结果就回调一次

    // 处理单个股票的K线数据
    void processStockBars(int index, List<KLine> bars) {
      completed++;
      onProgress?.call(completed, total);

      // 只保留当日的K线
      final todayBars = bars.where((bar) =>
          bar.datetime.year == today.year &&
          bar.datetime.month == today.month &&
          bar.datetime.day == today.day).toList();

      if (todayBars.isEmpty) return;

      final ratio = calculateRatio(todayBars);
      if (ratio == null) return;

      final changePercent = calculateChangePercent(todayBars, stocks[index].preClose);

      results.add(StockMonitorData(
        stock: stocks[index],
        ratio: ratio,
        changePercent: changePercent ?? 0.0,
        industry: industryService?.getIndustry(stocks[index].code),
      ));

      // 达到阈值时回调
      if (results.length >= lastReportedCount + reportThreshold) {
        lastReportedCount = results.length;
        // 按量比排序后回调
        final sorted = List<StockMonitorData>.from(results)
          ..sort((a, b) => b.ratio.compareTo(a.ratio));
        onData?.call(sorted);
      }
    }

    // 并行获取所有股票的K线
    await _pool.batchGetSecurityBarsStreaming(
      stocks: stocks,
      category: klineType1Min,
      start: 0,
      count: 240,
      onStockBars: processStockBars,
    );

    // 最终结果排序
    results.sort((a, b) => b.ratio.compareTo(a.ratio));

    // 最后一次回调确保显示最终结果
    if (results.length > lastReportedCount) {
      onData?.call(results);
    }

    return results;
  }
}
