import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/industry_rank.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';

/// Isolate 中计算行业排名的参数
class _RankComputeParams {
  /// 每股票每日涨跌量: stockCode -> dateKey -> [up, down]
  final Map<String, Map<String, List<double>>> stockVolumes;
  /// 股票行业映射: stockCode -> industry
  final Map<String, String> stockIndustries;
  /// 要计算的日期列表
  final List<String> dates;

  _RankComputeParams({
    required this.stockVolumes,
    required this.stockIndustries,
    required this.dates,
  });
}

/// Isolate 中计算行业排名
Map<String, Map<String, Map<String, dynamic>>> _computeRankInIsolate(_RankComputeParams params) {
  final result = <String, Map<String, Map<String, dynamic>>>{};

  for (final dateKey in params.dates) {
    // 按行业汇总涨跌量
    final industryVolumes = <String, List<double>>{};

    for (final entry in params.stockIndustries.entries) {
      final stockCode = entry.key;
      final industry = entry.value;

      final volumes = params.stockVolumes[stockCode]?[dateKey];
      if (volumes == null) continue;
      final up = volumes[0];
      final down = volumes[1];
      if (up <= 0 && down <= 0) continue;

      final current = industryVolumes[industry];
      if (current == null) {
        industryVolumes[industry] = [up, down];
      } else {
        industryVolumes[industry] = [current[0] + up, current[1] + down];
      }
    }

    // 计算聚合量比并排名
    final industryRatios = <String, double>{};
    for (final entry in industryVolumes.entries) {
      final down = entry.value[1];
      if (down > 0) {
        final ratio = entry.value[0] / down;
        if (ratio <= 1000 && ratio >= 0.001) {
          industryRatios[entry.key] = ratio;
        }
      }
    }

    final sorted = industryRatios.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final dayRanks = <String, Map<String, dynamic>>{};
    for (var i = 0; i < sorted.length; i++) {
      dayRanks[sorted[i].key] = {
        'date': dateKey,
        'ratio': sorted[i].value,
        'rank': i + 1,
      };
    }

    if (dayRanks.isNotEmpty) {
      result[dateKey] = dayRanks;
    }
  }

  return result;
}

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

  /// 计算时使用的K线数据版本
  int _calculatedFromVersion = -1;

  final bool _isLoading = false;

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
        _deserializeHistory(json);
        _cleanupOldData();
        debugPrint('[IndustryRank] 缓存加载完成, calculatedFromVersion=$_calculatedFromVersion, ${_historyData.length} 天');
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

  /// 清空排名缓存
  void clearCache() {
    _historyData = {};
    _todayRanks = {};
    notifyListeners();
  }

  /// 从历史K线数据重新计算排名
  Future<void> recalculateFromKlineData(
    HistoricalKlineService klineService,
    List<StockMonitorData> stocks, {
    bool force = false,
  }) async {
    if (stocks.isEmpty) return;

    // 检查是否需要重算
    final currentVersion = klineService.dataVersion;
    if (!force && _calculatedFromVersion == currentVersion && _historyData.isNotEmpty) {
      debugPrint('[IndustryRank] 数据版本未变 (v$currentVersion)，跳过重算');
      return;
    }

    debugPrint('[IndustryRank] 开始重算排名, ${stocks.length} 只股票, 数据版本 v$currentVersion');

    // 准备传给 isolate 的数据
    final stockVolumes = <String, Map<String, List<double>>>{};
    final stockIndustries = <String, String>{};

    for (final stock in stocks) {
      final industry = stock.industry;
      if (industry == null || industry.isEmpty) continue;

      stockIndustries[stock.stock.code] = industry;

      final volumes = await klineService.getDailyVolumes(stock.stock.code);
      if (volumes.isNotEmpty) {
        stockVolumes[stock.stock.code] = volumes.map(
          (dateKey, vol) => MapEntry(dateKey, [vol.up, vol.down]),
        );
      }
    }

    final dates = klineService.completeDates.toList();
    debugPrint('[IndustryRank] 准备数据完成, ${stockVolumes.length} 只股票, ${dates.length} 个日期');

    // 在 isolate 中计算
    final computeResult = await compute(
      _computeRankInIsolate,
      _RankComputeParams(
        stockVolumes: stockVolumes,
        stockIndustries: stockIndustries,
        dates: dates,
      ),
    );

    // 转换结果
    final newHistory = <String, Map<String, IndustryRankRecord>>{};
    for (final dateEntry in computeResult.entries) {
      final dateKey = dateEntry.key;
      final dayRanks = <String, IndustryRankRecord>{};

      for (final industryEntry in dateEntry.value.entries) {
        final data = industryEntry.value;
        dayRanks[industryEntry.key] = IndustryRankRecord(
          date: data['date'] as String,
          ratio: data['ratio'] as double,
          rank: data['rank'] as int,
        );
      }

      if (dayRanks.isNotEmpty) {
        newHistory[dateKey] = dayRanks;
      }
    }

    debugPrint('[IndustryRank] 计算完成, ${newHistory.length} 天有排名数据');

    _historyData = newHistory;
    _calculatedFromVersion = currentVersion;
    _cleanupOldData();
    await _save();
    debugPrint('[IndustryRank] 保存完成 (基于数据版本 v$currentVersion)');
    notifyListeners();
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
    return {
      'version': 1,
      'calculatedFromVersion': _calculatedFromVersion,
      'data': data,
    };
  }

  void _deserializeHistory(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    if (version != 1) return;

    _calculatedFromVersion = json['calculatedFromVersion'] as int? ?? -1;

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) return;

    final result = <String, Map<String, IndustryRankRecord>>{};
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
    _historyData = result;
  }
}
