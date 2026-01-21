import 'package:stock_rtwatcher/models/daily_ratio.dart';
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
  final bool isPullback;       // 是否为高质量回踩

  StockMonitorData({
    required this.stock,
    required this.ratio,
    required this.changePercent,
    this.industry,
    this.isPullback = false,
  });

  /// 创建带有回踩标记的副本
  StockMonitorData copyWith({bool? isPullback}) {
    return StockMonitorData(
      stock: stock,
      ratio: ratio,
      changePercent: changePercent,
      industry: industry,
      isPullback: isPullback ?? this.isPullback,
    );
  }

  Map<String, dynamic> toJson() => {
    'stock': stock.toJson(),
    'ratio': ratio,
    'changePercent': changePercent,
    'industry': industry,
    'isPullback': isPullback,
  };

  factory StockMonitorData.fromJson(Map<String, dynamic> json) => StockMonitorData(
    stock: Stock.fromJson(json['stock'] as Map<String, dynamic>),
    ratio: (json['ratio'] as num).toDouble(),
    changePercent: (json['changePercent'] as num).toDouble(),
    industry: json['industry'] as String?,
    isPullback: json['isPullback'] as bool? ?? false,
  );
}

/// 监控数据结果（包含数据日期）
class MonitorDataResult {
  final List<StockMonitorData> data;
  final DateTime dataDate;  // 实际数据日期

  MonitorDataResult({required this.data, required this.dataDate});
}

/// 股票服务
class StockService {
  final TdxPool _pool;

  StockService(this._pool);

  // 最大有效量比阈值 (超过此值认为是涨停/跌停/异常)
  static const double maxValidRatio = 50.0;

  /// 格式化日期为 "YYYY-MM-DD" 字符串
  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 解析 "YYYY-MM-DD" 字符串为 DateTime
  static DateTime _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

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
  /// 返回 MonitorDataResult，包含数据和实际数据日期
  /// 如果今天无数据，会自动回退到最近的交易日
  Future<MonitorDataResult> batchGetMonitorData(
    List<Stock> stocks, {
    IndustryService? industryService,
    void Function(int current, int total)? onProgress,
    void Function(List<StockMonitorData> results)? onData,
  }) async {
    final today = DateTime.now();
    final allDates = <String>{};  // 收集所有日期（用于回退）
    final stockBarsMap = <int, List<KLine>>{};  // 暂存所有K线（用于回退）
    final results = <StockMonitorData>[];
    var completed = 0;
    final total = stocks.length;
    var lastReportedCount = 0;
    const reportThreshold = 50;

    // 第一遍：边下载边处理今天的数据，同时收集所有日期用于可能的回退
    await _pool.batchGetSecurityBarsStreaming(
      stocks: stocks,
      category: klineType1Min,
      start: 0,
      count: 240,
      onStockBars: (index, bars) {
        completed++;
        onProgress?.call(completed, total);

        // 收集所有日期和数据（用于回退）
        stockBarsMap[index] = bars;
        for (final bar in bars) {
          allDates.add(_formatDate(bar.datetime));
        }

        // 立即处理今天的数据
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
          final sorted = List<StockMonitorData>.from(results)
            ..sort((a, b) => b.ratio.compareTo(a.ratio));
          onData?.call(sorted);
        }
      },
    );

    // 如果今天有数据，直接返回
    if (results.isNotEmpty) {
      results.sort((a, b) => b.ratio.compareTo(a.ratio));
      if (results.length > lastReportedCount) {
        onData?.call(results);
      }
      return MonitorDataResult(data: results, dataDate: today);
    }

    // 今天没数据，回退到最近的日期重新处理
    final sortedDates = allDates.toList()..sort((a, b) => b.compareTo(a));
    if (sortedDates.isEmpty) {
      return MonitorDataResult(data: [], dataDate: today);
    }

    final fallbackDate = sortedDates.first;
    lastReportedCount = 0;

    for (final entry in stockBarsMap.entries) {
      final index = entry.key;
      final bars = entry.value;

      final targetBars = bars.where((bar) => _formatDate(bar.datetime) == fallbackDate).toList();
      if (targetBars.isEmpty) continue;

      final ratio = calculateRatio(targetBars);
      if (ratio == null) continue;

      final changePercent = calculateChangePercent(targetBars, stocks[index].preClose);

      results.add(StockMonitorData(
        stock: stocks[index],
        ratio: ratio,
        changePercent: changePercent ?? 0.0,
        industry: industryService?.getIndustry(stocks[index].code),
      ));

      if (results.length >= lastReportedCount + reportThreshold) {
        lastReportedCount = results.length;
        final sorted = List<StockMonitorData>.from(results)
          ..sort((a, b) => b.ratio.compareTo(a.ratio));
        onData?.call(sorted);
      }
    }

    results.sort((a, b) => b.ratio.compareTo(a.ratio));
    if (results.length > lastReportedCount) {
      onData?.call(results);
    }

    return MonitorDataResult(data: results, dataDate: _parseDate(fallbackDate));
  }

  /// 获取 K 线数据
  /// [stock] 股票
  /// [category] K线类型 (klineTypeDaily=4, klineTypeWeekly=5)
  /// [count] 获取数量
  Future<List<KLine>> getKLines({
    required Stock stock,
    required int category,
    int count = 30,
  }) async {
    final client = _pool.firstClient;
    if (client == null) throw StateError('Not connected');
    return client.getSecurityBars(
      market: stock.market,
      code: stock.code,
      category: category,
      start: 0,
      count: count,
    );
  }

  /// 获取量比历史（最近 N 天）
  /// [stock] 股票
  /// [days] 天数（默认 20 天）
  Future<List<DailyRatio>> getRatioHistory({
    required Stock stock,
    int days = 20,
  }) async {
    final client = _pool.firstClient;
    if (client == null) throw StateError('Not connected');

    // 每天约 240 根分钟线，请求足够的数据
    // 分批请求，每次最多 800 根
    final allBars = <KLine>[];
    final totalBars = days * 240;
    var fetched = 0;

    while (fetched < totalBars) {
      final count = (totalBars - fetched).clamp(0, 800);
      final bars = await client.getSecurityBars(
        market: stock.market,
        code: stock.code,
        category: klineType1Min,
        start: fetched,
        count: count,
      );
      if (bars.isEmpty) break;
      allBars.addAll(bars);
      fetched += bars.length;
      if (bars.length < count) break; // 没有更多数据
    }

    // 按日期分组
    final Map<String, List<KLine>> grouped = {};
    for (final bar in allBars) {
      final dateKey = '${bar.datetime.year}-${bar.datetime.month.toString().padLeft(2, '0')}-${bar.datetime.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []).add(bar);
    }

    // 计算每天的量比
    final results = <DailyRatio>[];
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a)); // 降序

    for (final dateKey in sortedKeys.take(days)) {
      final dayBars = grouped[dateKey]!;
      final ratio = calculateRatio(dayBars);
      final parts = dateKey.split('-');
      results.add(DailyRatio(
        date: DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
        ratio: ratio,
      ));
    }

    return results;
  }
}
