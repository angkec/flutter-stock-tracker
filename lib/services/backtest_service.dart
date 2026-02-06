import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/backtest_config.dart';
import 'package:stock_rtwatcher/models/breakout_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// 回测服务
/// 使用 BreakoutService 的突破检测逻辑对历史数据进行回测
class BacktestService extends ChangeNotifier {
  static const String _storageKey = 'backtest_config';

  BacktestConfig _config = BacktestConfig.defaults;

  /// 当前配置
  BacktestConfig get config => _config;

  /// 从 SharedPreferences 加载配置
  Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _config = BacktestConfig.fromJson(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load backtest config: $e');
    }
  }

  /// 保存配置到 SharedPreferences
  Future<void> saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('Failed to save backtest config: $e');
    }
  }

  /// 更新配置并保存
  Future<void> updateConfig(BacktestConfig newConfig) async {
    _config = newConfig;
    notifyListeners();
    await saveConfig();
  }

  /// 重置为默认配置
  Future<void> resetToDefaults() async {
    _config = BacktestConfig.defaults;
    notifyListeners();
    await saveConfig();
  }

  /// 执行回测
  /// [dailyBarsMap] 股票代码 -> 日K数据列表（按时间升序）
  /// [stockDataMap] 股票代码 -> 股票监控数据
  /// [breakoutService] 用于复用突破检测逻辑
  /// [onProgress] 进度回调，参数为 (当前完成数, 总数)
  /// [concurrency] 并发数，默认 10
  Future<BacktestResult> runBacktest({
    required Map<String, List<KLine>> dailyBarsMap,
    required Map<String, StockMonitorData> stockDataMap,
    required BreakoutService breakoutService,
    void Function(int current, int total)? onProgress,
    int concurrency = 10,
  }) async {
    final signals = <SignalDetail>[];
    final allMaxGains = <double>[];
    final total = dailyBarsMap.length;
    var completed = 0;

    // 将股票列表分批并发处理
    final entries = dailyBarsMap.entries.toList();

    for (var i = 0; i < entries.length; i += concurrency) {
      final batch = entries.skip(i).take(concurrency).toList();

      // 并发处理这一批股票
      final batchResults = await Future.wait(
        batch.map((entry) => _processStock(
          code: entry.key,
          dailyBars: entry.value,
          stockData: stockDataMap[entry.key],
          breakoutService: breakoutService,
        )),
      );

      // 收集结果
      for (final result in batchResults) {
        if (result != null) {
          signals.addAll(result.signals);
          allMaxGains.addAll(result.maxGains);
        }
      }

      // 更新进度
      completed += batch.length;
      onProgress?.call(completed, total);

      // 让出 CPU 给 UI 线程更新
      await Future.delayed(Duration.zero);
    }

    // 计算各周期统计
    final periodStats = _calculatePeriodStats(signals);

    return BacktestResult(
      totalSignals: signals.length,
      periodStats: periodStats,
      signals: signals,
      allMaxGains: allMaxGains,
    );
  }

  /// 处理单只股票的回测
  Future<({List<SignalDetail> signals, List<double> maxGains})?> _processStock({
    required String code,
    required List<KLine> dailyBars,
    required StockMonitorData? stockData,
    required BreakoutService breakoutService,
  }) async {
    if (stockData == null || dailyBars.isEmpty) return null;

    final signals = <SignalDetail>[];
    final maxGains = <double>[];

    // 找到所有突破日
    final breakoutIndices = await breakoutService.findBreakoutDays(dailyBars, stockCode: code);

    // 对每个突破日，计算信号
    for (final breakoutIdx in breakoutIndices) {
      // 过滤无效数据（日期异常或价格异常的股票）
      final breakoutBar = dailyBars[breakoutIdx];
      if (breakoutBar.datetime.year < 2020) {
        continue;
      }
      if (breakoutBar.close <= 0 || breakoutBar.close > 10000) {
        continue;
      }

      final signalDetail = _processSignal(
        code: code,
        stockName: stockData.stock.name,
        dailyBars: dailyBars,
        breakoutIdx: breakoutIdx,
        breakoutService: breakoutService,
      );

      if (signalDetail != null) {
        signals.add(signalDetail);
        maxGains.addAll(signalDetail.maxGainByPeriod.values);
      }
    }

    return (signals: signals, maxGains: maxGains);
  }

  /// 处理单个信号
  SignalDetail? _processSignal({
    required String code,
    required String stockName,
    required List<KLine> dailyBars,
    required int breakoutIdx,
    required BreakoutService breakoutService,
  }) {
    final breakoutBar = dailyBars[breakoutIdx];
    final breakoutConfig = breakoutService.config;

    // 找到有效的回踩结束日
    int? signalIdx;
    for (int pullbackDays = breakoutConfig.minPullbackDays;
        pullbackDays <= breakoutConfig.maxPullbackDays;
        pullbackDays++) {
      final endIdx = breakoutIdx + pullbackDays;
      if (endIdx >= dailyBars.length) break;

      // 验证回踩是否有效（复用 BreakoutService 的逻辑）
      if (_isValidPullback(dailyBars, breakoutIdx, endIdx, breakoutService)) {
        signalIdx = endIdx;
        break;
      }
    }

    if (signalIdx == null) return null;

    // 计算买入价
    final buyPrice = _calculateBuyPrice(
      dailyBars: dailyBars,
      breakoutIdx: breakoutIdx,
      signalIdx: signalIdx,
    );

    if (buyPrice <= 0) return null;

    // 观察期起始 = 信号日 + 1
    final observationStartIdx = signalIdx + 1;
    if (observationStartIdx >= dailyBars.length) return null;

    // 计算各周期的最高涨幅和是否成功
    final maxGainByPeriod = <int, double>{};
    final successByPeriod = <int, bool>{};

    for (final days in _config.observationDays) {
      final endIdx = (observationStartIdx + days - 1).clamp(0, dailyBars.length - 1);

      // 如果数据不足，跳过该周期
      if (observationStartIdx > endIdx) {
        continue;
      }

      // 计算观察期内的最高价
      double maxHigh = 0;
      double maxLow = double.infinity;
      for (int i = observationStartIdx; i <= endIdx; i++) {
        if (dailyBars[i].high > maxHigh) maxHigh = dailyBars[i].high;
        if (dailyBars[i].low < maxLow) maxLow = dailyBars[i].low;
      }

      // 计算最高涨幅
      final maxGain = (maxHigh - buyPrice) / buyPrice;
      maxGainByPeriod[days] = maxGain;

      // 判断是否成功
      successByPeriod[days] = maxGain >= _config.targetGain;
    }

    // 如果没有任何周期的数据，返回 null
    if (maxGainByPeriod.isEmpty) return null;

    return SignalDetail(
      stockCode: code,
      stockName: stockName,
      breakoutDate: breakoutBar.datetime,
      signalDate: dailyBars[signalIdx].datetime,
      buyPrice: buyPrice,
      maxGainByPeriod: maxGainByPeriod,
      successByPeriod: successByPeriod,
    );
  }

  /// 验证回踩是否有效（简化版，复用 BreakoutService 的参数）
  bool _isValidPullback(
    List<KLine> dailyBars,
    int breakoutIdx,
    int endIdx,
    BreakoutService breakoutService,
  ) {
    final config = breakoutService.config;
    final breakoutBar = dailyBars[breakoutIdx];
    final pullbackBars = dailyBars.sublist(breakoutIdx + 1, endIdx + 1);

    if (pullbackBars.isEmpty) return false;

    // 计算参考价格
    final referencePrice = config.dropReferencePoint == DropReferencePoint.breakoutClose
        ? breakoutBar.close
        : breakoutBar.high;

    final lastBar = pullbackBars.last;

    // 检查总跌幅
    final totalDrop = (referencePrice - lastBar.close) / referencePrice;
    if (totalDrop > config.maxTotalDrop) return false;

    // 检查最大单日跌幅
    if (config.maxSingleDayDrop > 0) {
      for (final bar in pullbackBars) {
        final dayDrop = (referencePrice - bar.close) / referencePrice;
        if (dayDrop > config.maxSingleDayDrop) return false;
      }
    }

    // 检查最大单日涨幅
    if (config.maxSingleDayGain > 0) {
      for (final bar in pullbackBars) {
        final dayGain = (bar.close - referencePrice) / referencePrice;
        if (dayGain > config.maxSingleDayGain) return false;
      }
    }

    // 检查最大总涨幅
    if (config.maxTotalGain > 0) {
      final maxHigh = pullbackBars.map((b) => b.high).reduce((a, b) => a > b ? a : b);
      final totalGain = (maxHigh - referencePrice) / referencePrice;
      if (totalGain > config.maxTotalGain) return false;
    }

    // 检查平均量比
    final avgPullbackVolume =
        pullbackBars.map((b) => b.volume).reduce((a, b) => a + b) / pullbackBars.length;
    final avgVolumeRatio = avgPullbackVolume / breakoutBar.volume;
    if (avgVolumeRatio > config.maxAvgVolumeRatio) return false;

    return true;
  }

  /// 计算买入价
  double _calculateBuyPrice({
    required List<KLine> dailyBars,
    required int breakoutIdx,
    required int signalIdx,
  }) {
    final breakoutBar = dailyBars[breakoutIdx];
    final pullbackBars = dailyBars.sublist(breakoutIdx + 1, signalIdx + 1);

    switch (_config.buyPriceReference) {
      case BuyPriceReference.breakoutHigh:
        return breakoutBar.high;

      case BuyPriceReference.breakoutClose:
        return breakoutBar.close;

      case BuyPriceReference.pullbackAverage:
        // 成交量加权平均价 (VWAP)
        if (pullbackBars.isEmpty) return breakoutBar.close;
        double totalAmount = 0;
        double totalVolume = 0;
        for (final bar in pullbackBars) {
          // 使用 (high + low + close) / 3 作为典型价格
          final typicalPrice = (bar.high + bar.low + bar.close) / 3;
          totalAmount += typicalPrice * bar.volume;
          totalVolume += bar.volume;
        }
        return totalVolume > 0 ? totalAmount / totalVolume : breakoutBar.close;

      case BuyPriceReference.pullbackLow:
        // 回踩期间最低价
        if (pullbackBars.isEmpty) return breakoutBar.close;
        return pullbackBars.map((b) => b.low).reduce((a, b) => a < b ? a : b);
    }
  }

  /// 计算各周期统计
  List<PeriodStats> _calculatePeriodStats(List<SignalDetail> signals) {
    final periodStats = <PeriodStats>[];

    for (final days in _config.observationDays) {
      int successCount = 0;
      double totalMaxGain = 0;
      double totalMaxDrawdown = 0;
      int validCount = 0;

      for (final signal in signals) {
        final maxGain = signal.maxGainByPeriod[days];
        final success = signal.successByPeriod[days];

        if (maxGain == null || success == null) continue;

        validCount++;
        if (success) successCount++;
        totalMaxGain += maxGain;

        // 计算最大回撤（简化：使用负的最高涨幅作为回撤，当涨幅为负时）
        if (maxGain < 0) {
          totalMaxDrawdown += maxGain.abs();
        }
      }

      final successRate = validCount > 0 ? successCount / validCount : 0.0;
      final avgMaxGain = validCount > 0 ? totalMaxGain / validCount : 0.0;
      final avgMaxDrawdown = validCount > 0 ? totalMaxDrawdown / validCount : 0.0;

      periodStats.add(PeriodStats(
        days: days,
        successCount: successCount,
        successRate: successRate,
        avgMaxGain: avgMaxGain,
        avgMaxDrawdown: avgMaxDrawdown,
      ));
    }

    return periodStats;
  }
}
