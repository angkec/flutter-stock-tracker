# Industry Rank Trend Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add daily industry ranking by aggregate minute-K volume ratio with sparkline trend visualization, hot zone and recovery zone color indicators.

**Architecture:** Extend StockMonitorData with raw up/down volumes, create IndustryRankService for aggregate ratio computation and rank storage, add IndustryRankList widget with sparklines and color zones to the existing IndustryScreen.

**Tech Stack:** Flutter, Provider, SharedPreferences, CustomPaint (SparklineChart reuse)

---

### Task 1: Create IndustryRank Data Model

**Files:**
- Create: `lib/models/industry_rank.dart`

**Step 1: Write the model file**

```dart
/// 行业排名配置
class IndustryRankConfig {
  /// 热门区排名阈值（前N名）
  final int hotZoneTopN;

  /// 回升区排名范围上限
  final int recoveryZoneMaxRank;

  /// 回升区量比增幅阈值（百分比，如30表示30%）
  final double recoveryRatioGrowthPercent;

  /// 回升区回看天数
  final int recoveryLookbackDays;

  /// 当前查看的天数
  final int displayDays;

  const IndustryRankConfig({
    this.hotZoneTopN = 5,
    this.recoveryZoneMaxRank = 20,
    this.recoveryRatioGrowthPercent = 30.0,
    this.recoveryLookbackDays = 5,
    this.displayDays = 10,
  });

  IndustryRankConfig copyWith({
    int? hotZoneTopN,
    int? recoveryZoneMaxRank,
    double? recoveryRatioGrowthPercent,
    int? recoveryLookbackDays,
    int? displayDays,
  }) {
    return IndustryRankConfig(
      hotZoneTopN: hotZoneTopN ?? this.hotZoneTopN,
      recoveryZoneMaxRank: recoveryZoneMaxRank ?? this.recoveryZoneMaxRank,
      recoveryRatioGrowthPercent: recoveryRatioGrowthPercent ?? this.recoveryRatioGrowthPercent,
      recoveryLookbackDays: recoveryLookbackDays ?? this.recoveryLookbackDays,
      displayDays: displayDays ?? this.displayDays,
    );
  }

  Map<String, dynamic> toJson() => {
    'hotZoneTopN': hotZoneTopN,
    'recoveryZoneMaxRank': recoveryZoneMaxRank,
    'recoveryRatioGrowthPercent': recoveryRatioGrowthPercent,
    'recoveryLookbackDays': recoveryLookbackDays,
    'displayDays': displayDays,
  };

  factory IndustryRankConfig.fromJson(Map<String, dynamic> json) => IndustryRankConfig(
    hotZoneTopN: json['hotZoneTopN'] as int? ?? 5,
    recoveryZoneMaxRank: json['recoveryZoneMaxRank'] as int? ?? 20,
    recoveryRatioGrowthPercent: (json['recoveryRatioGrowthPercent'] as num?)?.toDouble() ?? 30.0,
    recoveryLookbackDays: json['recoveryLookbackDays'] as int? ?? 5,
    displayDays: json['displayDays'] as int? ?? 10,
  );
}

/// 某个行业某天的排名记录
class IndustryRankRecord {
  final String date; // "YYYY-MM-DD"
  final double ratio; // 行业聚合量比 (Σ涨量 / Σ跌量)
  final int rank; // 当天排名（1-based，1=最高）

  const IndustryRankRecord({
    required this.date,
    required this.ratio,
    required this.rank,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'ratio': ratio,
    'rank': rank,
  };

  factory IndustryRankRecord.fromJson(Map<String, dynamic> json) => IndustryRankRecord(
    date: json['date'] as String,
    ratio: (json['ratio'] as num).toDouble(),
    rank: json['rank'] as int,
  );
}

/// 某个行业的排名历史
class IndustryRankHistory {
  final String industryName;
  final List<IndustryRankRecord> records; // 按日期升序

  const IndustryRankHistory({
    required this.industryName,
    required this.records,
  });

  /// 当前排名（最新记录）
  int? get currentRank => records.isNotEmpty ? records.last.rank : null;

  /// 当前量比
  double? get currentRatio => records.isNotEmpty ? records.last.ratio : null;

  /// 排名变化（正数=上升，负数=下降）
  /// 与第一条记录相比
  int get rankChange {
    if (records.length < 2) return 0;
    return records.first.rank - records.last.rank; // first较大表示当前较小=上升
  }

  /// 获取排名序列（用于sparkline，Y轴倒置所以取负数）
  List<double> get rankSeries =>
      records.map((r) => -r.rank.toDouble()).toList();

  /// 判断是否在热门区
  bool isInHotZone(int topN) {
    final rank = currentRank;
    return rank != null && rank <= topN;
  }

  /// 判断是否在回升区
  bool isInRecoveryZone(IndustryRankConfig config) {
    if (records.length < 2) return false;
    final rank = currentRank;
    if (rank == null || rank <= config.hotZoneTopN) return false;
    if (rank > config.recoveryZoneMaxRank) return false;

    // 检查量比是否在增长
    final lookback = config.recoveryLookbackDays.clamp(1, records.length - 1);
    final lookbackIndex = records.length - 1 - lookback;
    if (lookbackIndex < 0) return false;

    final oldRatio = records[lookbackIndex].ratio;
    if (oldRatio <= 0) return false;

    final currentR = records.last.ratio;
    final growth = (currentR - oldRatio) / oldRatio * 100;
    return growth >= config.recoveryRatioGrowthPercent;
  }
}
```

**Step 2: Commit**

```bash
git add lib/models/industry_rank.dart
git commit -m "feat: add industry rank data models"
```

---

### Task 2: Extend StockMonitorData with Raw Volumes

**Files:**
- Modify: `lib/services/stock_service.dart:10-56` (StockMonitorData class)
- Modify: `lib/services/stock_service.dart:89-132` (calculateRatio method)

**Step 1: Add upVolume/downVolume fields to StockMonitorData**

In `lib/services/stock_service.dart`, add two fields to `StockMonitorData`:

```dart
class StockMonitorData {
  final Stock stock;
  final double ratio;
  final double changePercent;
  final String? industry;
  final bool isPullback;
  final bool isBreakout;
  final double upVolume;    // ADD: 涨量（上涨K线成交量之和）
  final double downVolume;  // ADD: 跌量（下跌K线成交量之和）

  StockMonitorData({
    required this.stock,
    required this.ratio,
    required this.changePercent,
    this.industry,
    this.isPullback = false,
    this.isBreakout = false,
    this.upVolume = 0,     // ADD
    this.downVolume = 0,   // ADD
  });
```

Update `copyWith`, `toJson`, `fromJson` to include the new fields.

**Step 2: Create a calculateRatioWithVolumes static method**

Add a new static method that returns both the ratio and raw volumes:

```dart
/// 计算量比并返回原始涨跌量
/// 返回 (ratio, upVolume, downVolume)，null表示数据无效
static ({double ratio, double upVolume, double downVolume})? calculateRatioWithVolumes(List<KLine> bars) {
  if (bars.length < minBarsCount) return null;

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
  }

  if (downVolume == 0 || downCount == 0) return null;
  if (upVolume == 0 || upCount == 0) return null;

  final ratio = upVolume / downVolume;
  if (ratio > maxValidRatio || ratio < 1 / maxValidRatio) return null;

  return (ratio: ratio, upVolume: upVolume, downVolume: downVolume);
}
```

**Step 3: Update batchGetMonitorData to use new method and pass volumes**

In `batchGetMonitorData` (around line 287), replace:
```dart
final ratio = calculateRatio(targetBars);
if (ratio == null) { ... }
```
with:
```dart
final result = calculateRatioWithVolumes(targetBars);
if (result == null) { ... }
```

And update the `StockMonitorData` construction (around line 301):
```dart
results.add(StockMonitorData(
  stock: stocks[index],
  ratio: result.ratio,
  upVolume: result.upVolume,
  downVolume: result.downVolume,
  changePercent: changePercent ?? 0.0,
  industry: industryService?.getIndustry(stocks[index].code),
));
```

**Step 4: Update existing calculateRatio to delegate**

Keep `calculateRatio` as a convenience wrapper:
```dart
static double? calculateRatio(List<KLine> bars) {
  final result = calculateRatioWithVolumes(bars);
  return result?.ratio;
}
```

**Step 5: Run build to verify no errors**

```bash
cd /Users/ankerc/Projects/stock-rtwatcher-flutter && flutter analyze
```

**Step 6: Commit**

```bash
git add lib/services/stock_service.dart
git commit -m "feat: extend StockMonitorData with raw up/down volumes"
```

---

### Task 3: Create IndustryRankService

**Files:**
- Create: `lib/services/industry_rank_service.dart`

**Step 1: Write the service**

```dart
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

    _todayRanks = {};
    for (var i = 0; i < sortedIndustries.length; i++) {
      final entry = sortedIndustries[i];
      _todayRanks[entry.key] = IndustryRankRecord(
        date: todayKey,
        ratio: entry.value,
        rank: i + 1,
      );
    }

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
      // stockIndex -> { dateKey -> (upVol, downVol) }
      final stockDailyVolumes = <int, Map<String, ({double up, double down})>>{};

      for (var i = 0; i < allBars.length; i++) {
        final bars = allBars[i];
        if (bars.isEmpty) continue;

        final dailyBars = _groupBarsByDate(bars);
        for (final entry in dailyBars.entries) {
          if (entry.key == todayKey) continue; // 跳过今天

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
      // Build stock code -> index map
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
        // 按行业汇总
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
        } catch (_) {}
      }
      if (dayRanks.isNotEmpty) {
        result[dateEntry.key] = dayRanks;
      }
    }
    return result;
  }
}
```

**Step 2: Run build to verify**

```bash
cd /Users/ankerc/Projects/stock-rtwatcher-flutter && flutter analyze
```

**Step 3: Commit**

```bash
git add lib/services/industry_rank_service.dart
git commit -m "feat: add IndustryRankService for aggregate volume ratio ranking"
```

---

### Task 4: Create IndustryRankList Widget

**Files:**
- Create: `lib/widgets/industry_rank_list.dart`

**Step 1: Write the widget**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_rank.dart';
import 'package:stock_rtwatcher/screens/industry_detail_screen.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/widgets/sparkline_chart.dart';

/// 行业排名趋势列表组件
class IndustryRankList extends StatefulWidget {
  const IndustryRankList({super.key});

  @override
  State<IndustryRankList> createState() => _IndustryRankListState();
}

class _IndustryRankListState extends State<IndustryRankList> {
  static const List<int> _dayOptions = [5, 10, 20];

  @override
  Widget build(BuildContext context) {
    final rankService = context.watch<IndustryRankService>();
    final config = rankService.config;
    final histories = rankService.getAllRankHistories(config.displayDays);

    if (histories.isEmpty && !rankService.isLoading) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // 时间段切换按钮组
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Text('排名趋势', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              ..._dayOptions.map((days) => Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _DayChip(
                  days: days,
                  isSelected: config.displayDays == days,
                  onTap: () => rankService.updateConfig(
                    config.copyWith(displayDays: days),
                  ),
                ),
              )),
            ],
          ),
        ),
        // 表头
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: const Row(
            children: [
              SizedBox(width: 28, child: Text('排名', style: TextStyle(fontSize: 10))),
              SizedBox(width: 56, child: Text('行业', style: TextStyle(fontSize: 10))),
              SizedBox(width: 40, child: Text('量比', style: TextStyle(fontSize: 10))),
              Spacer(),
              SizedBox(width: 64, child: Align(
                alignment: Alignment.centerRight,
                child: Text('趋势', style: TextStyle(fontSize: 10)),
              )),
            ],
          ),
        ),
        // 排名列表
        if (rankService.isLoading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          ...histories.take(20).map((history) => _RankRow(
            history: history,
            config: config,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IndustryDetailScreen(industry: history.industryName),
              ),
            ),
          )),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  final int days;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayChip({
    required this.days,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${days}日',
          style: TextStyle(
            fontSize: 11,
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final IndustryRankHistory history;
  final IndustryRankConfig config;
  final VoidCallback onTap;

  const _RankRow({
    required this.history,
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rank = history.currentRank ?? 0;
    final ratio = history.currentRatio ?? 0.0;
    final change = history.rankChange;
    final isHot = history.isInHotZone(config.hotZoneTopN);
    final isRecovery = history.isInRecoveryZone(config);

    // 背景颜色
    Color? bgColor;
    if (isHot) {
      bgColor = Colors.orange.withValues(alpha: 0.08);
    } else if (isRecovery) {
      bgColor = Colors.cyan.withValues(alpha: 0.08);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            left: BorderSide(
              color: isHot
                  ? Colors.orange
                  : isRecovery
                      ? Colors.cyan
                      : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // 排名 + 变化
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isHot ? Colors.orange : null,
                ),
              ),
            ),
            // 行业名
            SizedBox(
              width: 56,
              child: Text(
                history.industryName,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 量比
            SizedBox(
              width: 40,
              child: Text(
                ratio.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 11,
                  color: ratio >= 1.0 ? const Color(0xFFFF4444) : const Color(0xFF00AA00),
                ),
              ),
            ),
            // 排名变化标记
            SizedBox(
              width: 28,
              child: _ChangeIndicator(change: change),
            ),
            // Sparkline
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: history.rankSeries.length >= 2
                    ? SparklineChart(
                        data: history.rankSeries,
                        width: 56,
                        height: 20,
                      )
                    : const Text('-', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeIndicator extends StatelessWidget {
  final int change;

  const _ChangeIndicator({required this.change});

  @override
  Widget build(BuildContext context) {
    if (change == 0) {
      return const Text('→', style: TextStyle(fontSize: 10, color: Colors.grey));
    }

    final isUp = change > 0;
    return Text(
      '${isUp ? "↑" : "↓"}${change.abs()}',
      style: TextStyle(
        fontSize: 9,
        color: isUp ? const Color(0xFFFF4444) : const Color(0xFF00AA00),
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/widgets/industry_rank_list.dart
git commit -m "feat: add IndustryRankList widget with sparklines and zone colors"
```

---

### Task 5: Integrate into IndustryScreen

**Files:**
- Modify: `lib/screens/industry_screen.dart`

**Step 1: Add IndustryRankService import and rank list**

Add import at top:
```dart
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/widgets/industry_rank_list.dart';
```

**Step 2: Trigger rank calculation in build or didChangeDependencies**

In `_IndustryScreenState`, add logic to call `calculateTodayRanks` when market data updates. In the `build` method, after getting `marketProvider`:

```dart
// 计算今日行业排名
final rankService = context.watch<IndustryRankService>();
if (marketProvider.allData.isNotEmpty) {
  // Use addPostFrameCallback to avoid calling during build
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      rankService.calculateTodayRanks(marketProvider.allData);
    }
  });
}
```

**Step 3: Add IndustryRankList before the existing table**

In the `body` Column (inside the `Expanded` when data is available), insert `IndustryRankList()` before the header row:

```dart
Column(
  children: [
    // 行业排名趋势（新增）
    const IndustryRankList(),
    const Divider(height: 1),
    // 表头（existing）
    Container(
      height: 32,
      ...
    ),
    // ListView（existing）
    Expanded(
      child: RefreshIndicator(
        ...
      ),
    ),
  ],
)
```

**Step 4: Add fetch button for rank data in AppBar**

Add a condition to show fetch button when rank history is empty:
```dart
// In actions list, after existing refresh button
if (rankService.historyData.isEmpty && !rankService.isLoading && marketProvider.allData.isNotEmpty)
  TextButton.icon(
    onPressed: () => _fetchRankData(rankService, marketProvider),
    icon: const Icon(Icons.trending_up, size: 18),
    label: const Text('获取排名'),
  ),
```

Add the fetch method:
```dart
Future<void> _fetchRankData(IndustryRankService rankService, MarketDataProvider marketProvider) async {
  final pool = context.read<TdxPool>();
  final industryService = context.read<IndustryService>();

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ProgressDialog(
      getProgress: () => _fetchProgress,
      getTotal: () => _fetchTotal,
    ),
  );

  try {
    await rankService.fetchHistoricalData(
      pool,
      marketProvider.allData,
      industryService,
      (current, total) {
        setState(() {
          _fetchProgress = current;
          _fetchTotal = total;
        });
      },
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('排名数据已更新')),
      );
    }
  } catch (e) {
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取排名数据失败: $e')),
      );
    }
  }
}
```

**Step 5: Run build to verify**

```bash
cd /Users/ankerc/Projects/stock-rtwatcher-flutter && flutter analyze
```

**Step 6: Commit**

```bash
git add lib/screens/industry_screen.dart
git commit -m "feat: integrate industry rank trend into IndustryScreen"
```

---

### Task 6: Register IndustryRankService in main.dart

**Files:**
- Modify: `lib/main.dart`

**Step 1: Add import**

```dart
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
```

**Step 2: Add ChangeNotifierProvider for IndustryRankService**

Add after the existing IndustryTrendService provider:

```dart
ChangeNotifierProvider(create: (_) {
  final service = IndustryRankService();
  service.load(); // 异步加载排名缓存
  return service;
}),
```

**Step 3: Run build to verify**

```bash
cd /Users/ankerc/Projects/stock-rtwatcher-flutter && flutter analyze
```

**Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register IndustryRankService in main.dart"
```

---

### Task 7: Final Integration Verification

**Step 1: Run full build**

```bash
cd /Users/ankerc/Projects/stock-rtwatcher-flutter && flutter build ios --no-codesign 2>&1 | tail -20
```

**Step 2: Fix any build errors**

Address any type errors or missing imports.

**Step 3: Final commit if fixes needed**

```bash
git add -A
git commit -m "fix: resolve build issues in industry rank feature"
```
