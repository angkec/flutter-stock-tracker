import 'dart:developer' as developer;
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
  final bool isBreakout;       // 是否为突破
  final double upVolume;       // 上涨K线成交量之和
  final double downVolume;     // 下跌K线成交量之和

  StockMonitorData({
    required this.stock,
    required this.ratio,
    required this.changePercent,
    this.industry,
    this.isPullback = false,
    this.isBreakout = false,
    this.upVolume = 0,
    this.downVolume = 0,
  });

  /// 创建带有回踩标记的副本
  StockMonitorData copyWith({bool? isPullback, bool? isBreakout, double? upVolume, double? downVolume}) {
    return StockMonitorData(
      stock: stock,
      ratio: ratio,
      changePercent: changePercent,
      industry: industry,
      isPullback: isPullback ?? this.isPullback,
      isBreakout: isBreakout ?? this.isBreakout,
      upVolume: upVolume ?? this.upVolume,
      downVolume: downVolume ?? this.downVolume,
    );
  }

  Map<String, dynamic> toJson() => {
    'stock': stock.toJson(),
    'ratio': ratio,
    'changePercent': changePercent,
    'industry': industry,
    'isPullback': isPullback,
    'isBreakout': isBreakout,
    'upVolume': upVolume,
    'downVolume': downVolume,
  };

  factory StockMonitorData.fromJson(Map<String, dynamic> json) => StockMonitorData(
    stock: Stock.fromJson(json['stock'] as Map<String, dynamic>),
    ratio: (json['ratio'] as num).toDouble(),
    changePercent: (json['changePercent'] as num).toDouble(),
    industry: json['industry'] as String?,
    isPullback: json['isPullback'] as bool? ?? false,
    isBreakout: json['isBreakout'] as bool? ?? false,
    upVolume: (json['upVolume'] as num?)?.toDouble() ?? 0,
    downVolume: (json['downVolume'] as num?)?.toDouble() ?? 0,
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

  /// 计算量比及原始成交量 (涨量/跌量)
  /// 返回包含 ratio、upVolume、downVolume 的 record
  /// 返回 null 表示数据无效 (涨停/跌停/停盘等)
  static ({double ratio, double upVolume, double downVolume})? calculateRatioWithVolumes(List<KLine> bars) {
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

    return (ratio: ratio, upVolume: upVolume, downVolume: downVolume);
  }

  /// 计算量比 (涨量/跌量)
  /// 返回上涨K线成交量之和与下跌K线成交量之和的比值
  /// 返回 null 表示数据无效 (涨停/跌停/停盘等)
  static double? calculateRatio(List<KLine> bars) {
    final result = calculateRatioWithVolumes(bars);
    return result?.ratio;
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
  /// [onBarsData] 当获取到单只股票K线时回调，用于缓存原始数据
  /// 返回 MonitorDataResult，包含数据和实际数据日期
  /// 如果今天数据不足（<10根K线），会自动回退到最近的交易日
  Future<MonitorDataResult> batchGetMonitorData(
    List<Stock> stocks, {
    IndustryService? industryService,
    void Function(int current, int total)? onProgress,
    void Function(List<StockMonitorData> results)? onData,
    void Function(String code, List<KLine> bars)? onBarsData,
  }) async {
    // Use print for console visibility
    print('🔍 [batchGetMonitorData] Called with ${stocks.length} stocks at ${DateTime.now()}');
    developer.log('[batchGetMonitorData] Called with ${stocks.length} stocks at ${DateTime.now()}');

    final today = DateTime.now();
    final todayKey = _formatDate(today);
    final allDates = <String>{};  // 收集所有日期
    final stockBarsMap = <int, List<KLine>>{};  // 暂存所有K线
    final results = <StockMonitorData>[];
    var completed = 0;
    final total = stocks.length;
    var lastReportedCount = 0;
    const reportThreshold = 50;

    // 统计今日数据情况
    int todayValidCount = 0;  // 今日数据充足的股票数

    // 第一遍：下载数据并统计
    developer.log('[batchGetMonitorData] Starting data fetch for ${stocks.length} stocks');
    int emptyBarsCount = 0;

    await _pool.batchGetSecurityBarsStreaming(
      stocks: stocks,
      category: klineType1Min,
      start: 0,
      count: 240,
      onStockBars: (index, bars) {
        completed++;
        onProgress?.call(completed, total);

        if (bars.isEmpty) {
          emptyBarsCount++;
        }

        // 保存数据和收集日期
        stockBarsMap[index] = bars;
        for (final bar in bars) {
          allDates.add(_formatDate(bar.datetime));
        }

        // 回调原始K线数据用于缓存
        onBarsData?.call(stocks[index].code, bars);

        // 统计今日数据情况
        final todayBars = bars.where((bar) =>
            bar.datetime.year == today.year &&
            bar.datetime.month == today.month &&
            bar.datetime.day == today.day).toList();

        if (todayBars.length >= minBarsCount) {
          todayValidCount++;
        }
      },
    );

    print('🔍 [batchGetMonitorData] Fetch complete: stockBarsMap=${stockBarsMap.length}, emptyBars=$emptyBarsCount');
    developer.log('[batchGetMonitorData] Fetch complete: stockBarsMap=${stockBarsMap.length}, emptyBars=$emptyBarsCount');

    // 确定使用哪个日期的数据
    // 如果今日有效数据的股票数 < 总数的10%，则认为今日数据不足，使用回退日期
    final useFallback = todayValidCount < stocks.length * 0.1;

    print('🔍 [batchGetMonitorData] todayValidCount=$todayValidCount, total=${stocks.length}, useFallback=$useFallback');
    print('🔍 [batchGetMonitorData] allDates count=${allDates.length}, dates=${allDates.take(5)}');
    developer.log('[batchGetMonitorData] todayValidCount=$todayValidCount, total=${stocks.length}, useFallback=$useFallback');
    developer.log('[batchGetMonitorData] allDates count=${allDates.length}, dates=${allDates.take(5)}');

    String targetDate;
    DateTime resultDate;

    if (useFallback) {
      // 找到最近的有效日期（非今天）
      final sortedDates = allDates.toList()..sort((a, b) => b.compareTo(a));
      final fallbackDates = sortedDates.where((d) => d != todayKey).toList();
      print('🔍 [batchGetMonitorData] sortedDates=${sortedDates.take(5)}, fallbackDates=${fallbackDates.take(5)}');
      developer.log('[batchGetMonitorData] sortedDates=${sortedDates.take(5)}, fallbackDates=${fallbackDates.take(5)}');
      if (fallbackDates.isEmpty) {
        // 没有历史数据可用
        print('🔍 [batchGetMonitorData] No fallback dates available!');
        developer.log('[batchGetMonitorData] No fallback dates available!');
        return MonitorDataResult(data: [], dataDate: today);
      }
      targetDate = fallbackDates.first;
      resultDate = _parseDate(targetDate);
      print('🔍 [batchGetMonitorData] Using fallback date: $targetDate');
      developer.log('[batchGetMonitorData] Using fallback date: $targetDate');
    } else {
      targetDate = todayKey;
      resultDate = today;
      print('🔍 [batchGetMonitorData] Using today: $targetDate');
      developer.log('[batchGetMonitorData] Using today: $targetDate');
    }

    // 使用选定日期的数据计算
    int emptyTargetBars = 0;
    int nullRatioCount = 0;
    int processedCount = 0;

    for (final entry in stockBarsMap.entries) {
      final index = entry.key;
      final bars = entry.value;

      final targetBars = bars.where((bar) => _formatDate(bar.datetime) == targetDate).toList();
      if (targetBars.isEmpty) {
        emptyTargetBars++;
        continue;
      }

      final result = calculateRatioWithVolumes(targetBars);
      if (result == null) {
        nullRatioCount++;
        continue;
      }

      processedCount++;
      final changePercent = calculateChangePercent(targetBars, stocks[index].preClose);

      // 过滤明显异常涨跌幅（preClose 错误导致的数据异常）
      if (changePercent != null && changePercent.abs() > 30) {
        continue;
      }

      results.add(StockMonitorData(
        stock: stocks[index],
        ratio: result.ratio,
        changePercent: changePercent ?? 0.0,
        industry: industryService?.getIndustry(stocks[index].code),
        upVolume: result.upVolume,
        downVolume: result.downVolume,
      ));

      // 达到阈值时回调
      if (results.length >= lastReportedCount + reportThreshold) {
        lastReportedCount = results.length;
        final sorted = List<StockMonitorData>.from(results)
          ..sort((a, b) => b.ratio.compareTo(a.ratio));
        onData?.call(sorted);
      }
    }

    print('🔍 [batchGetMonitorData] Processing stats: emptyTargetBars=$emptyTargetBars, nullRatio=$nullRatioCount, processed=$processedCount');
    developer.log('[batchGetMonitorData] Processing stats: emptyTargetBars=$emptyTargetBars, nullRatio=$nullRatioCount, processed=$processedCount');

    results.sort((a, b) => b.ratio.compareTo(a.ratio));
    print('🔍 [batchGetMonitorData] Final results count: ${results.length}, targetDate: $targetDate, stockBarsMap=${stockBarsMap.length}');
    developer.log('[batchGetMonitorData] Final results count: ${results.length}, targetDate: $targetDate, stockBarsMap=${stockBarsMap.length}');
    if (results.length > lastReportedCount) {
      onData?.call(results);
    }

    return MonitorDataResult(data: results, dataDate: resultDate);
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
