import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

/// 在 isolate 中解压并解析 JSON
Future<Map<String, dynamic>> _decompressAndParse(List<int> compressed) async {
  final decompressed = gzip.decode(compressed);
  final jsonStr = utf8.decode(decompressed);
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

/// 在 isolate 中序列化并压缩 JSON
Future<List<int>> _serializeAndCompress(Map<String, dynamic> data) async {
  final jsonStr = jsonEncode(data);
  final bytes = utf8.encode(jsonStr);
  return gzip.encode(bytes);
}

/// 归并两个已排序的 KLine 列表，O(n+m)
/// 返回可修改的 growable list
List<KLine> _mergeSortedLists(List<KLine> a, List<KLine> b) {
  if (a.isEmpty) return List<KLine>.from(b, growable: true);
  if (b.isEmpty) return List<KLine>.from(a, growable: true);

  final result = <KLine>[];
  var i = 0, j = 0;

  while (i < a.length && j < b.length) {
    if (a[i].datetime.compareTo(b[j].datetime) <= 0) {
      result.add(a[i++]);
    } else {
      result.add(b[j++]);
    }
  }

  while (i < a.length) {
    result.add(a[i++]);
  }
  while (j < b.length) {
    result.add(b[j++]);
  }

  return result;
}

/// 历史分钟K线数据服务
/// 统一管理原始分钟K线，支持增量拉取
class HistoricalKlineService extends ChangeNotifier {
  static const String _storageKey = 'historical_kline_cache_v1'; // 旧版 SharedPreferences key
  static const String _oldFileName = 'historical_kline_v1.json'; // 旧版未压缩文件
  static const String _fileName = 'historical_kline_v2.json.gz'; // K线数据压缩文件
  static const String _metaFileName = 'historical_kline_meta.json'; // 元数据文件
  static const int _maxCacheDays = 30;

  /// 获取缓存文件路径
  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// 获取元数据文件路径
  Future<File> _getMetaFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_metaFileName');
  }

  /// 获取旧版缓存文件路径（用于迁移）
  Future<File> _getOldCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_oldFileName');
  }

  /// 存储：按股票代码索引
  /// stockCode -> List<KLine> (按时间升序排列)
  Map<String, List<KLine>> _stockBars = {};

  /// 已完整拉取的日期集合
  Set<String> _completeDates = {};

  /// 最后拉取时间
  DateTime? _lastFetchTime;

  /// 数据版本号（每次数据变更时递增）
  int _dataVersion = 0;

  /// 股票数量（元数据，不需要加载完整数据）
  int _stockCount = 0;

  /// K线数据是否已加载到内存
  bool _klineDataLoaded = false;

  /// 预计算的每日每行业汇总（用于快速计算趋势/排名）
  /// { "2026-01-21": { "半导体": {up: 1000, down: 500}, ... } }
  Map<String, Map<String, ({double up, double down})>> _dailyIndustrySummary = {};

  /// 是否正在加载
  bool _isLoading = false;

  // Getters
  bool get isLoading => _isLoading;
  DateTime? get lastFetchTime => _lastFetchTime;
  Set<String> get completeDates => Set.unmodifiable(_completeDates);
  int get stockCount => _klineDataLoaded ? _stockBars.length : _stockCount;
  int get dataVersion => _dataVersion;
  bool get klineDataLoaded => _klineDataLoaded;

  /// 格式化日期为 "YYYY-MM-DD" 字符串
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 解析 "YYYY-MM-DD" 字符串为 DateTime
  static DateTime parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  /// 设置某只股票的K线数据（用于测试）
  @visibleForTesting
  void setStockBars(String stockCode, List<KLine> bars) {
    _stockBars[stockCode] = bars..sort((a, b) => a.datetime.compareTo(b.datetime));
  }

  /// 获取某只股票所有日期的涨跌量汇总
  /// 返回 { dateKey: (up: upVolume, down: downVolume) }
  Map<String, ({double up, double down})> getDailyVolumes(String stockCode) {
    final bars = _stockBars[stockCode];
    if (bars == null || bars.isEmpty) return {};

    final result = <String, ({double up, double down})>{};

    for (final bar in bars) {
      final dateKey = formatDate(bar.datetime);
      final current = result[dateKey];

      double upAdd = 0;
      double downAdd = 0;
      if (bar.isUp) {
        upAdd = bar.volume;
      } else if (bar.isDown) {
        downAdd = bar.volume;
      }

      result[dateKey] = (
        up: (current?.up ?? 0) + upAdd,
        down: (current?.down ?? 0) + downAdd,
      );
    }

    return result;
  }

  /// 添加已完成日期（用于测试）
  @visibleForTesting
  void addCompleteDate(String dateKey) {
    _completeDates.add(dateKey);
  }

  /// 估算最近N个交易日（排除周末）
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

  int _lastReportedMissing = -1;

  /// 获取缺失天数
  int getMissingDays() {
    final today = DateTime.now();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);

    int missing = 0;
    final missingKeys = <String>[];
    for (final day in tradingDays) {
      final key = formatDate(day);
      if (!_completeDates.contains(key)) {
        missing++;
        if (missingKeys.length < 5) missingKeys.add(key);
      }
    }

    // 只在值变化时输出日志
    if (missing != _lastReportedMissing) {
      _lastReportedMissing = missing;
      debugPrint('[HistoricalKline] getMissingDays: $missing 天缺失, completeDates=${_completeDates.length}, 前5个缺失: $missingKeys');
    }
    return missing;
  }

  /// 获取缺失的日期列表
  List<String> getMissingDateKeys() {
    final today = DateTime.now();
    final tradingDays = _estimateTradingDays(today, _maxCacheDays);

    final missing = <String>[];
    for (final day in tradingDays) {
      final key = formatDate(day);
      if (!_completeDates.contains(key)) {
        missing.add(key);
      }
    }
    return missing;
  }

  /// 序列化元数据（轻量，启动时加载）
  Map<String, dynamic> serializeMetadata() {
    return {
      'version': 1,
      'dataVersion': _dataVersion,
      'lastFetchTime': _lastFetchTime?.toIso8601String(),
      'completeDates': _completeDates.toList(),
      'stockCount': _stockBars.length,
    };
  }

  /// 序列化K线数据（重量，按需加载）
  Map<String, dynamic> serializeKlineData() {
    final stocks = <String, dynamic>{};
    for (final entry in _stockBars.entries) {
      stocks[entry.key] = entry.value.map((bar) => bar.toJson()).toList();
    }
    return {
      'version': 1,
      'dataVersion': _dataVersion,
      'stocks': stocks,
    };
  }

  /// 序列化缓存数据（兼容旧版）
  Map<String, dynamic> serializeCache() {
    final stocks = <String, dynamic>{};
    for (final entry in _stockBars.entries) {
      stocks[entry.key] = entry.value.map((bar) => bar.toJson()).toList();
    }

    return {
      'version': 1,
      'dataVersion': _dataVersion,
      'lastFetchTime': _lastFetchTime?.toIso8601String(),
      'completeDates': _completeDates.toList(),
      'stocks': stocks,
    };
  }

  /// 反序列化元数据（轻量）
  void deserializeMetadata(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    if (version != 1) {
      debugPrint('[HistoricalKline] metadata: 版本不匹配，跳过');
      return;
    }

    _dataVersion = json['dataVersion'] as int? ?? 0;
    final lastFetchStr = json['lastFetchTime'] as String?;
    _lastFetchTime = lastFetchStr != null ? DateTime.parse(lastFetchStr) : null;

    final dates = json['completeDates'] as List<dynamic>?;
    _completeDates = dates?.map((e) => e as String).toSet() ?? {};
    _stockCount = json['stockCount'] as int? ?? 0;

    debugPrint('[HistoricalKline] metadata: dataVersion=$_dataVersion, completeDates=${_completeDates.length}, stockCount=$_stockCount');
  }

  /// 反序列化K线数据（重量，按需调用）
  void deserializeKlineData(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    if (version != 1) {
      debugPrint('[HistoricalKline] klineData: 版本不匹配，跳过');
      return;
    }

    final stocks = json['stocks'] as Map<String, dynamic>?;
    if (stocks != null) {
      _stockBars = {};
      for (final entry in stocks.entries) {
        final barsList = entry.value as List<dynamic>;
        _stockBars[entry.key] = barsList
            .map((e) => KLine.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.datetime.compareTo(b.datetime));
      }
    }
    _klineDataLoaded = true;
    debugPrint('[HistoricalKline] klineData: 读取 stockBars=${_stockBars.length} 只');

    _cleanupOldData();
  }

  /// 反序列化缓存数据（兼容旧版，包含元数据和K线）
  void deserializeCache(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 0;
    debugPrint('[HistoricalKline] deserialize: version=$version');
    if (version != 1) {
      debugPrint('[HistoricalKline] deserialize: 版本不匹配，跳过');
      return;
    }

    _dataVersion = json['dataVersion'] as int? ?? 0;
    final lastFetchStr = json['lastFetchTime'] as String?;
    _lastFetchTime = lastFetchStr != null ? DateTime.parse(lastFetchStr) : null;

    final dates = json['completeDates'] as List<dynamic>?;
    _completeDates = dates?.map((e) => e as String).toSet() ?? {};
    debugPrint('[HistoricalKline] deserialize: 读取 completeDates=${_completeDates.length} 天: $_completeDates');

    final stocks = json['stocks'] as Map<String, dynamic>?;
    if (stocks != null) {
      _stockBars = {};
      for (final entry in stocks.entries) {
        final barsList = entry.value as List<dynamic>;
        _stockBars[entry.key] = barsList
            .map((e) => KLine.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.datetime.compareTo(b.datetime));
      }
    }
    _stockCount = _stockBars.length;
    _klineDataLoaded = true;
    debugPrint('[HistoricalKline] deserialize: 读取 stockBars=${_stockBars.length} 只');

    _cleanupOldData();
  }

  /// 清理超过30天的旧数据
  void _cleanupOldData() {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxCacheDays));
    final cutoffKey = formatDate(cutoff);
    debugPrint('[HistoricalKline] cleanup: cutoffKey=$cutoffKey');

    final beforeDates = _completeDates.length;
    // 清理过期日期
    _completeDates.removeWhere((key) => key.compareTo(cutoffKey) < 0);
    debugPrint('[HistoricalKline] cleanup: completeDates $beforeDates -> ${_completeDates.length}');

    // 清理过期K线
    for (final entry in _stockBars.entries) {
      entry.value.removeWhere((bar) => formatDate(bar.datetime).compareTo(cutoffKey) < 0);
    }
    final beforeStocks = _stockBars.length;
    _stockBars.removeWhere((_, bars) => bars.isEmpty);
    debugPrint('[HistoricalKline] cleanup: stockBars $beforeStocks -> ${_stockBars.length}');
  }

  /// 从本地缓存加载（只加载元数据，K线数据按需加载）
  Future<void> load() async {
    debugPrint('[HistoricalKline] 开始加载元数据...');
    try {
      // 优先从元数据文件加载（快速）
      final metaFile = await _getMetaFile();
      if (await metaFile.exists()) {
        final metaStr = await metaFile.readAsString();
        final metaJson = jsonDecode(metaStr) as Map<String, dynamic>;
        deserializeMetadata(metaJson);
        debugPrint('[HistoricalKline] 元数据加载完成');
        notifyListeners();
        return;
      }

      // 如果没有元数据文件，尝试从旧格式迁移
      await _migrateFromOldFormat();
    } catch (e, stack) {
      debugPrint('[HistoricalKline] 加载缓存失败: $e');
      debugPrint('Stack: $stack');
    }
  }

  /// 从旧格式迁移数据
  Future<void> _migrateFromOldFormat() async {
    final file = await _getCacheFile();

    // 尝试从压缩文件迁移
    if (await file.exists()) {
      final compressed = await file.readAsBytes();
      final sizeMB = (compressed.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('[HistoricalKline] 从旧压缩文件迁移: $sizeMB MB');

      final json = await compute(_decompressAndParse, compressed);
      deserializeCache(json);

      // 保存新格式（分离元数据）
      await save();
      debugPrint('[HistoricalKline] 迁移完成，已保存新格式');
      notifyListeners();
      return;
    }

    // 尝试从旧版未压缩文件迁移
    final oldFile = await _getOldCacheFile();
    if (await oldFile.exists()) {
      debugPrint('[HistoricalKline] 发现旧版缓存文件，开始迁移...');
      final jsonStr = await oldFile.readAsString();
      final sizeMB = (jsonStr.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('[HistoricalKline] 旧文件大小: $sizeMB MB');

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      deserializeCache(json);

      // 保存新格式并删除旧文件
      await save();
      await oldFile.delete();
      debugPrint('[HistoricalKline] 已迁移到新格式，旧文件已删除');
      notifyListeners();
      return;
    }

    // 尝试从旧版 SharedPreferences 迁移
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      final sizeMB = (jsonStr.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('[HistoricalKline] 从 SharedPreferences 迁移: $sizeMB MB');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      deserializeCache(json);

      // 保存新格式并删除旧数据
      await save();
      await prefs.remove(_storageKey);
      debugPrint('[HistoricalKline] 已迁移到新格式，旧数据已删除');
      notifyListeners();
    } else {
      debugPrint('[HistoricalKline] 无缓存数据');
    }
  }

  /// 按需加载K线数据（计算趋势/排名时调用）
  Future<void> loadKlineData() async {
    if (_klineDataLoaded) {
      debugPrint('[HistoricalKline] K线数据已加载');
      return;
    }

    debugPrint('[HistoricalKline] 开始加载K线数据...');
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final compressed = await file.readAsBytes();
        final sizeMB = (compressed.length / 1024 / 1024).toStringAsFixed(2);
        debugPrint('[HistoricalKline] 从压缩文件读取K线: $sizeMB MB');

        final json = await compute(_decompressAndParse, compressed);
        deserializeKlineData(json);
        debugPrint('[HistoricalKline] K线数据加载完成: ${_stockBars.length} 只股票');
      } else {
        debugPrint('[HistoricalKline] K线数据文件不存在');
      }
    } catch (e, stack) {
      debugPrint('[HistoricalKline] 加载K线数据失败: $e');
      debugPrint('Stack: $stack');
    }
  }

  /// 保存到本地缓存
  Future<void> save() async {
    // 递增数据版本号
    _dataVersion++;
    _stockCount = _stockBars.length;

    try {
      // 保存元数据（小文件，快速）
      final metaFile = await _getMetaFile();
      await metaFile.writeAsString(jsonEncode(serializeMetadata()));
      debugPrint('[HistoricalKline] 元数据已保存: dataVersion=$_dataVersion');

      // 保存K线数据（压缩大文件）
      final file = await _getCacheFile();
      final data = serializeKlineData();
      debugPrint('[HistoricalKline] 准备压缩保存K线, stockCount=$_stockCount');

      final compressed = await compute(_serializeAndCompress, data);
      final sizeMB = (compressed.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('[HistoricalKline] 压缩后大小: $sizeMB MB');

      await file.writeAsBytes(compressed);
      debugPrint('[HistoricalKline] K线数据保存成功');
    } catch (e, stack) {
      debugPrint('[HistoricalKline] 保存失败: $e');
      debugPrint('Stack: $stack');
    }
  }

  /// 清空缓存
  Future<void> clear() async {
    _stockBars = {};
    _completeDates = {};
    _lastFetchTime = null;
    _dataVersion = 0;
    _stockCount = 0;
    _klineDataLoaded = false;
    notifyListeners();

    try {
      // 删除元数据文件
      final metaFile = await _getMetaFile();
      if (await metaFile.exists()) {
        await metaFile.delete();
        debugPrint('[HistoricalKline] 元数据文件已删除');
      }

      // 删除K线数据文件
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
        debugPrint('[HistoricalKline] K线数据文件已删除');
      }

      // 删除旧版未压缩文件
      final oldFile = await _getOldCacheFile();
      if (await oldFile.exists()) {
        await oldFile.delete();
        debugPrint('[HistoricalKline] 旧版缓存文件已删除');
      }

      // 清理旧版 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_storageKey)) {
        await prefs.remove(_storageKey);
        debugPrint('[HistoricalKline] SharedPreferences 旧数据已删除');
      }
    } catch (e) {
      debugPrint('[HistoricalKline] 清空缓存失败: $e');
    }
  }

  /// 增量拉取缺失的日期
  /// 返回本次拉取的天数
  /// onProgress: (current, total, stage) - stage: 'fetch' | 'process'
  Future<int> fetchMissingDays(
    TdxPool pool,
    List<Stock> stocks,
    void Function(int current, int total, String stage)? onProgress,
  ) async {
    if (stocks.isEmpty || _isLoading) return 0;

    final missingDates = getMissingDateKeys();
    debugPrint('[HistoricalKline] 缺失日期: ${missingDates.length} 天, $missingDates');
    if (missingDates.isEmpty) return 0;

    _isLoading = true;
    notifyListeners();

    try {
      final connected = await pool.ensureConnected();
      if (!connected) throw Exception('无法连接到服务器');

      // 计算需要拉取的页数
      // 每页800条，每天约240条，每页约3.3天
      // 为安全起见，每缺3天拉1页
      final pagesToFetch = (missingDates.length / 3).ceil().clamp(1, 6);
      const int barsPerPage = 800;

      final stockList = stocks;
      final fetchTotal = stockList.length * pagesToFetch;
      debugPrint('[HistoricalKline] 开始拉取: ${stockList.length} 只股票, $pagesToFetch 页');

      // 收集所有K线数据
      final allBars = List<List<KLine>>.generate(stockList.length, (_) => []);

      for (var page = 0; page < pagesToFetch; page++) {
        final start = page * barsPerPage;
        final pageBars = await pool.batchGetSecurityBars(
          stocks: stockList,
          category: klineType1Min,
          start: start,
          count: barsPerPage,
          onProgress: (current, total) {
            final completed = page * stockList.length + current;
            onProgress?.call(completed, fetchTotal, 'fetch');
          },
        );

        var nonEmptyCount = 0;
        var totalBarsThisPage = 0;
        for (var i = 0; i < pageBars.length; i++) {
          if (pageBars[i].isNotEmpty) {
            allBars[i].addAll(pageBars[i]);
            nonEmptyCount++;
            totalBarsThisPage += pageBars[i].length;
          }
        }
        debugPrint('[HistoricalKline] 第 ${page + 1} 页: $nonEmptyCount 只有数据, 共 $totalBarsThisPage 条');
      }

      // 统计拉取结果
      var totalFetchedBars = 0;
      var stocksWithData = 0;
      DateTime? earliestBar, latestBar;
      for (final bars in allBars) {
        if (bars.isNotEmpty) {
          stocksWithData++;
          totalFetchedBars += bars.length;
          for (final bar in bars) {
            if (earliestBar == null || bar.datetime.isBefore(earliestBar)) {
              earliestBar = bar.datetime;
            }
            if (latestBar == null || bar.datetime.isAfter(latestBar)) {
              latestBar = bar.datetime;
            }
          }
        }
      }
      debugPrint('[HistoricalKline] 拉取完成: $stocksWithData 只有数据, 共 $totalFetchedBars 条');
      debugPrint('[HistoricalKline] 数据范围: $earliestBar ~ $latestBar');

      // 在主线程处理数据合并，定期让出 UI 线程
      final todayKey = formatDate(DateTime.now());
      final dateCounts = <String, int>{}; // 统计每个日期有多少只股票
      const yieldInterval = 50; // 每处理 50 只股票让出一次

      for (var i = 0; i < stockList.length; i++) {
        final stockCode = stockList[i].code;
        final bars = allBars[i];

        if (bars.isNotEmpty) {
          final existing = _stockBars[stockCode] ?? [];
          final existingTimes = existing.isEmpty
              ? <int>{}
              : existing.map((b) => b.datetime.millisecondsSinceEpoch).toSet();

          // 过滤：去重 + 排除今天 + 排除无效日期
          final filteredBars = <KLine>[];
          final stockDates = <String>{}; // 这只股票贡献的日期（去重）
          for (final b in bars) {
            // 排除无效日期 (TDX 解析失败返回 2000-01-01)
            if (b.datetime.year < 2020 || b.datetime.year > 2030) continue;

            final dateKey = formatDate(b.datetime);
            if (dateKey != todayKey &&
                !existingTimes.contains(b.datetime.millisecondsSinceEpoch)) {
              filteredBars.add(b);
              stockDates.add(dateKey);
            }
          }

          // 统计：每只股票对每个日期贡献 1
          for (final dateKey in stockDates) {
            dateCounts[dateKey] = (dateCounts[dateKey] ?? 0) + 1;
          }

          if (filteredBars.isNotEmpty) {
            filteredBars.sort((a, b) => a.datetime.compareTo(b.datetime));
            _stockBars[stockCode] = _mergeSortedLists(existing, filteredBars);
          }
        }

        // 定期让出主线程 + 更新进度
        if (i % yieldInterval == 0) {
          onProgress?.call(i, stockList.length, 'process');
          await Future.delayed(Duration.zero);
        }
      }

      debugPrint('[HistoricalKline] 新日期统计:');
      final sortedDateCounts = dateCounts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in sortedDateCounts) {
        final threshold = stockList.length * 0.1;
        final complete = entry.value > threshold ? '✓' : '✗';
        debugPrint('  ${entry.key}: ${entry.value} 只 (阈值 ${threshold.toInt()}) $complete');
      }

      for (final entry in dateCounts.entries) {
        if (entry.value > stockList.length * 0.1) {
          _completeDates.add(entry.key);
        }
      }

      debugPrint('[HistoricalKline] 已完成日期: ${_completeDates.length} 天');
      debugPrint('[HistoricalKline] completeDates: $_completeDates');

      _lastFetchTime = DateTime.now();
      _cleanupOldData();

      debugPrint('[HistoricalKline] 清理后 completeDates: ${_completeDates.length} 天');

      await save();
      debugPrint('[HistoricalKline] 保存完成, stockBars: ${_stockBars.length} 只');

      return dateCounts.length;
    } catch (e, stack) {
      debugPrint('Failed to fetch historical kline data: $e');
      debugPrint('Stack trace: $stack');
      return 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 获取数据覆盖范围
  ({String? earliest, String? latest}) getDateRange() {
    if (_completeDates.isEmpty) return (earliest: null, latest: null);
    final sorted = _completeDates.toList()..sort();
    return (earliest: sorted.first, latest: sorted.last);
  }

  /// 获取缓存大小（估算字节数）
  int getCacheSize() {
    int count = 0;
    for (final bars in _stockBars.values) {
      count += bars.length;
    }
    // 每条K线约80字节
    return count * 80;
  }

  /// 格式化缓存大小
  String get cacheSizeFormatted {
    final bytes = getCacheSize();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
