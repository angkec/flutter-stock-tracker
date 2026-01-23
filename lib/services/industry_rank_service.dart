import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/industry_rank.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

/// 行业排名服务
/// 计算每日行业聚合量比（Σ涨量/Σ跌量）并排名
class IndustryRankService extends ChangeNotifier {
  static const String _storageKey = 'industry_rank_cache_v1';
  static const String _configKey = 'industry_rank_config';
  static const int _maxCacheDays = 30;

  /// 历史排名数据: { "YYYY-MM-DD": { "行业名": IndustryRankRecord } }
  Map<String, Map<String, IndustryRankRecord>> _historyData = {};

  /// 今日实时排名
  Map<String, IndustryRankRecord> _todayRanks = {};

  /// 配置
  IndustryRankConfig _config = const IndustryRankConfig();

  bool _isLoading = false;

  // Getters
  Map<String, Map<String, IndustryRankRecord>> get historyData =>
      Map.unmodifiable(_historyData);
  Map<String, IndustryRankRecord> get todayRanks =>
      Map.unmodifiable(_todayRanks);
  IndustryRankConfig get config => _config;
  bool get isLoading => _isLoading;

  /// 获取某行业的排名历史（最近N天）
  IndustryRankHistory? getRankHistory(String industry, int days) {
    final records = <IndustryRankRecord>[];

    // 收集历史记录
    final sortedDates = _historyData.keys.toList()..sort();
    final recentDates = sortedDates.length > days
        ? sortedDates.sublist(sortedDates.length - days)
        : sortedDates;

    for (final date in recentDates) {
      final dayData = _historyData[date];
      if (dayData != null && dayData.containsKey(industry)) {
        records.add(dayData[industry]!);
      }
    }

    // 添加今日数据
    if (_todayRanks.containsKey(industry)) {
      records.add(_todayRanks[industry]!);
    }

    if (records.isEmpty) return null;

    return IndustryRankHistory(
      industryName: industry,
      records: records,
    );
  }

  /// 获取所有行业的排名历史（最近N天），按当前排名排序
  List<IndustryRankHistory> getAllRankHistories(int days) {
    final industries = <String>{};

    // 收集所有行业名称
    for (final dayData in _historyData.values) {
      industries.addAll(dayData.keys);
    }
    industries.addAll(_todayRanks.keys);

    final histories = <IndustryRankHistory>[];
    for (final industry in industries) {
      final history = getRankHistory(industry, days);
      if (history != null && history.records.isNotEmpty) {
        histories.add(history);
      }
    }

    // 按当前排名排序
    histories.sort((a, b) {
      final aRank = a.currentRank ?? 999;
      final bRank = b.currentRank ?? 999;
      return aRank.compareTo(bRank);
    });

    return histories;
  }

  /// 计算今日实时排名
  /// 使用 StockMonitorData 中的 upVolume/downVolume
  void calculateTodayRanks(List<StockMonitorData> stocks) {
    if (stocks.isEmpty) return;

    final today = DateTime.now();
    final todayKey = _dateKey(today);

    // 按行业汇总涨跌量
    final industryVolumes = <String, ({double up, double down})>{};
    for (final stock in stocks) {
      final industry = stock.industry;
      if (industry == null || industry.isEmpty) continue;
      if (stock.upVolume <= 0 && stock.downVolume <= 0) continue;

      final current = industryVolumes[industry];
      industryVolumes[industry] = (
        up: (current?.up ?? 0) + stock.upVolume,
        down: (current?.down ?? 0) + stock.downVolume,
      );
    }

    // 计算每个行业的聚合量比
    final industryRatios = <String, double>{};
    for (final entry in industryVolumes.entries) {
      if (entry.value.down > 0) {
        final ratio = entry.value.up / entry.value.down;
        if (ratio <= StockService.maxValidRatio &&
            ratio >= 1 / StockService.maxValidRatio) {
          industryRatios[entry.key] = ratio;
        }
      }
    }

    // 排名（量比降序）
    final sortedIndustries = industryRatios.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final newRanks = <String, IndustryRankRecord>{};
    for (var i = 0; i < sortedIndustries.length; i++) {
      final entry = sortedIndustries[i];
      newRanks[entry.key] = IndustryRankRecord(
        date: todayKey,
        ratio: entry.value,
        rank: i + 1,
      );
    }
    _todayRanks = newRanks;

    notifyListeners();
  }

  /// 从缓存加载历史数据
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载历史数据
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _historyData = _deserializeHistory(json);
        _cleanupOldData();
      }

      // 加载配置
      final configStr = prefs.getString(_configKey);
      if (configStr != null) {
        _config = IndustryRankConfig.fromJson(
          jsonDecode(configStr) as Map<String, dynamic>,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load industry rank cache: $e');
    }
  }

  /// 更新配置
  Future<void> updateConfig(IndustryRankConfig newConfig) async {
    _config = newConfig;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(newConfig.toJson()));
    } catch (e) {
      debugPrint('Failed to save industry rank config: $e');
    }
  }

  /// 拉取历史排名数据
  /// 从TDX获取分钟K线数据，计算每天的行业聚合量比并排名
  Future<void> fetchHistoricalData(
    TdxPool pool,
    List<StockMonitorData> stocks,
    IndustryService industryService,
    void Function(int, int)? onProgress,
  ) async {
    if (stocks.isEmpty || _isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      final connected = await pool.ensureConnected();
      if (!connected) throw Exception('无法连接到服务器');

      // 获取所有股票的分钟K线数据
      final stockList = stocks.map((s) => s.stock).toList();
      const int barsPerPage = 800;
      const int totalPages = 4; // ~16天数据

      final allBars = List<List<KLine>>.generate(stockList.length, (_) => []);
      var totalCompleted = 0;
      final totalRequests = stockList.length * totalPages;

      for (var page = 0; page < totalPages; page++) {
        final start = page * barsPerPage;
        final pageBars = await pool.batchGetSecurityBars(
          stocks: stockList,
          category: klineType1Min,
          start: start,
          count: barsPerPage,
          onProgress: (current, total) {
            totalCompleted = page * stockList.length + current;
            onProgress?.call(totalCompleted, totalRequests);
          },
        );

        for (var i = 0; i < pageBars.length; i++) {
          if (pageBars[i].isNotEmpty) {
            allBars[i].addAll(pageBars[i]);
          }
        }
      }

      // 按日期分组，计算每个行业每天的聚合量比
      final today = DateTime.now();
      final todayKey = _dateKey(today);

      // 收集每只股票每天的涨跌量
      final stockDailyVolumes = <int, Map<String, ({double up, double down})>>{};

      for (var i = 0; i < allBars.length; i++) {
        final bars = allBars[i];
        if (bars.isEmpty) continue;

        final dailyBars = _groupBarsByDate(bars);
        for (final entry in dailyBars.entries) {
          if (entry.key == todayKey) continue;

          final dayBars = entry.value;
          if (dayBars.length < StockService.minBarsCount) continue;

          double upVol = 0, downVol = 0;
          for (final bar in dayBars) {
            if (bar.isUp) {
              upVol += bar.volume;
            } else if (bar.isDown) {
              downVol += bar.volume;
            }
          }

          if (upVol > 0 && downVol > 0) {
            stockDailyVolumes.putIfAbsent(i, () => {})[entry.key] = (up: upVol, down: downVol);
          }
        }
      }

      // 按行业汇总每天的量
      final stockCodeToIndex = <String, int>{};
      for (var i = 0; i < stocks.length; i++) {
        stockCodeToIndex[stocks[i].stock.code] = i;
      }

      // 收集所有日期
      final allDates = <String>{};
      for (final volumes in stockDailyVolumes.values) {
        allDates.addAll(volumes.keys);
      }

      // 每个日期，汇总行业量并排名
      final newHistory = <String, Map<String, IndustryRankRecord>>{};

      for (final dateKey in allDates) {
        final industryVolumes = <String, ({double up, double down})>{};

        for (final stock in stocks) {
          final industry = stock.industry;
          if (industry == null || industry.isEmpty) continue;

          final stockIndex = stockCodeToIndex[stock.stock.code];
          if (stockIndex == null) continue;

          final volumes = stockDailyVolumes[stockIndex];
          if (volumes == null || !volumes.containsKey(dateKey)) continue;

          final vol = volumes[dateKey]!;
          final current = industryVolumes[industry];
          industryVolumes[industry] = (
            up: (current?.up ?? 0) + vol.up,
            down: (current?.down ?? 0) + vol.down,
          );
        }

        // 计算量比并排名
        final industryRatios = <String, double>{};
        for (final entry in industryVolumes.entries) {
          if (entry.value.down > 0) {
            final ratio = entry.value.up / entry.value.down;
            if (ratio <= StockService.maxValidRatio &&
                ratio >= 1 / StockService.maxValidRatio) {
              industryRatios[entry.key] = ratio;
            }
          }
        }

        final sorted = industryRatios.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final dayRanks = <String, IndustryRankRecord>{};
        for (var i = 0; i < sorted.length; i++) {
          dayRanks[sorted[i].key] = IndustryRankRecord(
            date: dateKey,
            ratio: sorted[i].value,
            rank: i + 1,
          );
        }

        if (dayRanks.isNotEmpty) {
          newHistory[dateKey] = dayRanks;
        }
      }

      // 合并到现有数据（新数据覆盖旧数据）
      for (final entry in newHistory.entries) {
        _historyData[entry.key] = entry.value;
      }
      _cleanupOldData();

      await _save();
    } catch (e) {
      debugPrint('Failed to fetch industry rank data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 检查缺失天数
  int getMissingDays() {
    final today = DateTime.now();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);
    int missing = 0;
    for (final day in tradingDays) {
      final key = _dateKey(day);
      if (!_historyData.containsKey(key)) {
        missing++;
      }
    }
    return missing;
  }

  // === Private helpers ===

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, List<KLine>> _groupBarsByDate(List<KLine> bars) {
    final grouped = <String, List<KLine>>{};
    for (final bar in bars) {
      final key = _dateKey(bar.datetime);
      grouped.putIfAbsent(key, () => []).add(bar);
    }
    return grouped;
  }

  List<DateTime> _estimateTradingDays(DateTime from, int count) {
    final days = <DateTime>[];
    var current = from;
    var checked = 0;
    while (days.length < count && checked < count * 2) {
      current = current.subtract(const Duration(days: 1));
      checked++;
      if (current.weekday == DateTime.saturday || current.weekday == DateTime.sunday) {
        continue;
      }
      days.add(DateTime(current.year, current.month, current.day));
    }
    return days;
  }

  void _cleanupOldData() {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxCacheDays));
    final cutoffKey = _dateKey(cutoff);
    _historyData.removeWhere((key, _) => key.compareTo(cutoffKey) < 0);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_serializeHistory()));
    } catch (e) {
      debugPrint('Failed to save industry rank cache: $e');
    }
  }

  Map<String, dynamic> _serializeHistory() {
    final data = <String, dynamic>{};
    for (final entry in _historyData.entries) {
      data[entry.key] = entry.value.map(
        (industry, record) => MapEntry(industry, record.toJson()),
      );
    }
    return {'version': 1, 'data': data};
  }

  Map<String, Map<String, IndustryRankRecord>> _deserializeHistory(
    Map<String, dynamic> json,
  ) {
    final result = <String, Map<String, IndustryRankRecord>>{};
    final version = json['version'] as int? ?? 0;
    if (version != 1) return result;

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return result;

    for (final dateEntry in data.entries) {
      final dayData = dateEntry.value as Map<String, dynamic>;
      final dayRanks = <String, IndustryRankRecord>{};
      for (final industryEntry in dayData.entries) {
        try {
          dayRanks[industryEntry.key] = IndustryRankRecord.fromJson(
            industryEntry.value as Map<String, dynamic>,
          );
        } catch (e) {
          debugPrint('Failed to deserialize industry rank for ${industryEntry.key}: $e');
        }
      }
      if (dayRanks.isNotEmpty) {
        result[dateEntry.key] = dayRanks;
      }
    }
    return result;
  }
}
