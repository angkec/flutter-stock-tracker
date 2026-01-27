import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/config/debug_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';

/// 在隔离线程中解析股票监控数据 JSON
List<StockMonitorData> _parseMarketDataJson(String jsonStr) {
  final List<dynamic> jsonList = json.decode(jsonStr);
  return jsonList
      .map((e) => StockMonitorData.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// 在隔离线程中解析 KLine 数据 JSON
Map<String, List<KLine>> _parseKLineJson(String jsonStr) {
  final Map<String, dynamic> data = jsonDecode(jsonStr);
  return data.map((k, v) => MapEntry(
    k,
    (v as List)
        .where((item) => item is Map<String, dynamic>)
        .map((item) => KLine.fromJson(item as Map<String, dynamic>))
        .toList(),
  ));
}

enum RefreshStage {
  idle,           // 空闲
  fetchMinuteData, // 拉取分时数据
  updateDailyBars, // 更新日K数据
  analyzing,       // 分析计算
  error,          // 错误
}

class MarketDataProvider extends ChangeNotifier {
  final TdxPool _pool;
  final StockService _stockService;
  final IndustryService _industryService;
  PullbackService? _pullbackService;
  BreakoutService? _breakoutService;

  List<StockMonitorData> _allData = [];
  bool _isLoading = false;
  int _progress = 0;
  int _total = 0;
  String? _updateTime;
  DateTime? _dataDate;
  String? _errorMessage;

  // Refresh stage tracking
  RefreshStage _stage = RefreshStage.idle;
  String? _stageDescription;  // "拉取分时 32/156"
  int _stageProgress = 0;     // 当前进度
  int _stageTotal = 0;        // 总数
  String? _lastFetchDate;     // "2026-01-21" for incremental fetching

  // Cache keys
  static const String _dailyBarsCacheKey = 'daily_bars_cache_v1';
  static const String _minuteDataCacheKey = 'minute_data_cache_v1';
  static const String _minuteDataDateKey = 'minute_data_date';
  static const String _lastFetchDateKey = 'last_fetch_date';

  // Watchlist codes for priority sorting
  Set<String> _watchlistCodes = {};

  // 缓存日K数据用于重算回踩
  Map<String, List<KLine>> _dailyBarsCache = {};

  // 分时数据计数（不保留完整对象，避免 Android OOM）
  int _minuteDataCount = 0;

  // Timer for debounce saving
  Timer? _saveDebounceTimer;

  MarketDataProvider({
    required TdxPool pool,
    required StockService stockService,
    required IndustryService industryService,
  })  : _pool = pool,
        _stockService = stockService,
        _industryService = industryService;

  // Getters
  List<StockMonitorData> get allData => _allData;
  bool get isLoading => _isLoading;
  int get progress => _progress;
  int get total => _total;
  String? get updateTime => _updateTime;
  DateTime? get dataDate => _dataDate;
  String? get errorMessage => _errorMessage;
  IndustryService get industryService => _industryService;
  RefreshStage get stage => _stage;
  String? get stageDescription => _stageDescription;
  String? get lastFetchDate => _lastFetchDate;
  int get minuteDataCacheCount => _minuteDataCount;

  // Cache info getters
  int get dailyBarsCacheCount => _dailyBarsCache.length;

  /// 获取日K缓存数据（用于回测）
  Map<String, List<KLine>> get dailyBarsCache => _dailyBarsCache;

  /// 获取股票数据映射（用于回测）
  Map<String, StockMonitorData> get stockDataMap {
    return {for (final data in _allData) data.stock.code: data};
  }
  String get dailyBarsCacheSize => _formatSize(_estimateDailyBarsSize());
  String get minuteDataCacheSize => _formatSize(_minuteDataCount * 240 * 40);
  String? get industryDataCacheSize => _industryService.isLoaded
      ? _formatSize(_estimateIndustryDataSize())
      : null;
  bool get industryDataLoaded => _industryService.isLoaded;
  String get totalCacheSizeFormatted => _formatSize(_estimateTotalSize());

  /// 获取板块热度（量比>=1 和 <1 的股票数量）
  /// 返回 (hotCount, coldCount)，如果行业为空或无数据返回 null
  ({int hot, int cold})? getIndustryHeat(String? industry) {
    if (industry == null || industry.isEmpty || _allData.isEmpty) {
      return null;
    }

    int hot = 0;
    int cold = 0;

    for (final data in _allData) {
      if (data.industry == industry) {
        if (data.ratio >= 1.0) {
          hot++;
        } else {
          cold++;
        }
      }
    }

    if (hot == 0 && cold == 0) {
      return null;
    }

    return (hot: hot, cold: cold);
  }

  /// 获取板块涨跌分布
  /// 返回7个区间的股票数量: [涨停, >5%, 0~5%, 平, -5~0, <-5%, 跌停]
  List<int>? getIndustryChangeDistribution(String? industry) {
    if (industry == null || industry.isEmpty || _allData.isEmpty) {
      return null;
    }

    int limitUp = 0;    // >= 9.8%
    int up5 = 0;        // 5% ~ 9.8%
    int up0to5 = 0;     // 0 < x < 5%
    int flat = 0;       // == 0
    int down0to5 = 0;   // -5% < x < 0
    int down5 = 0;      // -9.8% < x <= -5%
    int limitDown = 0;  // <= -9.8%

    for (final data in _allData) {
      if (data.industry != industry) continue;

      final cp = data.changePercent;
      if (cp >= 9.8) {
        limitUp++;
      } else if (cp >= 5) {
        up5++;
      } else if (cp > 0) {
        up0to5++;
      } else if (cp.abs() < 0.001) {
        flat++;
      } else if (cp > -5) {
        down0to5++;
      } else if (cp > -9.8) {
        down5++;
      } else {
        limitDown++;
      }
    }

    final total = limitUp + up5 + up0to5 + flat + down0to5 + down5 + limitDown;
    if (total == 0) return null;

    return [limitUp, up5, up0to5, flat, down0to5, down5, limitDown];
  }

  /// 设置自选股代码（用于优先排序）
  void setWatchlistCodes(Set<String> codes) {
    _watchlistCodes = codes;
  }

  /// 设置回踩服务（用于检测高质量回踩）
  void setPullbackService(PullbackService service) {
    _pullbackService = service;
  }

  /// 设置突破回踩服务（用于检测突破回踩）
  void setBreakoutService(BreakoutService service) {
    _breakoutService = service;
  }

  void _updateProgress(RefreshStage stage, int current, int total) {
    _stage = stage;
    _stageProgress = current;
    _stageTotal = total;
    _stageDescription = _formatStageDescription(stage, current, total);
    notifyListeners();
  }

  String _formatStageDescription(RefreshStage stage, int current, int total) {
    switch (stage) {
      case RefreshStage.fetchMinuteData:
        return '拉取分时 $current/$total';
      case RefreshStage.updateDailyBars:
        return '更新日K $current/$total';
      case RefreshStage.analyzing:
        return '分析计算...';
      case RefreshStage.error:
        return _stageDescription ?? '刷新失败';
      case RefreshStage.idle:
        return '';
    }
  }

  /// 从缓存加载数据
  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('market_data_cache');
      final timeStr = prefs.getString('market_data_time');
      final dateStr = prefs.getString('market_data_date');

      if (jsonStr != null) {
        _allData = _parseMarketDataJson(jsonStr);
        _updateTime = timeStr;
        if (dateStr != null) {
          _dataDate = DateTime.tryParse(dateStr);
        }
        notifyListeners();
      }

      // Load daily bars cache
      final dailyBarsJson = prefs.getString(_dailyBarsCacheKey);
      if (dailyBarsJson != null) {
        try {
          _dailyBarsCache = _parseKLineJson(dailyBarsJson);
        } catch (e) {
          debugPrint('Failed to load daily bars cache: $e');
          await prefs.remove(_dailyBarsCacheKey);
        }
      }

      // Load last fetch date
      _lastFetchDate = prefs.getString(_lastFetchDateKey);

      // Clean up legacy minute data cache from SharedPreferences (no longer persisted)
      if (prefs.containsKey(_minuteDataCacheKey)) {
        await prefs.remove(_minuteDataCacheKey);
        await prefs.remove(_minuteDataDateKey);
      }
    } catch (e) {
      debugPrint('Failed to load cache: $e');
    }
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _allData.map((e) => e.toJson()).toList();
      await prefs.setString('market_data_cache', json.encode(jsonList));
      if (_updateTime != null) {
        await prefs.setString('market_data_time', _updateTime!);
      }
      if (_dataDate != null) {
        await prefs.setString('market_data_date', _dataDate!.toIso8601String());
      }
    } catch (e) {
      debugPrint('Failed to save cache: $e');
    }
  }

  /// Persist daily bars cache to SharedPreferences
  Future<void> _persistDailyBarsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _dailyBarsCache.map((k, v) => MapEntry(
        k,
        v.map((bar) => bar.toJson()).toList(),
      ));
      await prefs.setString(_dailyBarsCacheKey, jsonEncode(data));

      // Update last fetch date
      final today = DateTime.now().toString().substring(0, 10);
      await prefs.setString(_lastFetchDateKey, today);
      _lastFetchDate = today;
    } catch (e) {
      debugPrint('Failed to persist daily bars cache: $e');
    }
  }


  /// Schedule persistence with debounce
  void _schedulePersist() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _persistDailyBarsCache();
    });
  }

  /// 刷新数据
  Future<void> refresh({bool silent = false}) async {
    print('🔍 [MarketDataProvider.refresh] Called at ${DateTime.now()}, isLoading=$_isLoading');
    developer.log('[MarketDataProvider.refresh] Called at ${DateTime.now()}, isLoading=$_isLoading');
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _progress = 0;
    _total = 0;
    notifyListeners();

    try {
      // 确保连接
      final connected = await _pool.ensureConnected();
      if (!connected) {
        _stage = RefreshStage.error;
        _stageDescription = '无法连接到服务器';
        _errorMessage = '无法连接到服务器';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 获取所有股票
      print('🔍 [MarketDataProvider.refresh] Getting all stocks...');
      developer.log('[MarketDataProvider.refresh] Getting all stocks...');
      var stocks = await _stockService.getAllStocks();
      print('🔍 [MarketDataProvider.refresh] Got ${stocks.length} stocks');
      developer.log('[MarketDataProvider.refresh] Got ${stocks.length} stocks');

      // Debug 模式下限制股票数量
      stocks = DebugConfig.limitStocks(stocks);

      // Set initial stage
      if (!silent) {
        _updateProgress(RefreshStage.fetchMinuteData, 0, stocks.length);
      }

      // 按自选股优先排序
      final prioritizedStocks = <Stock>[];
      final otherStocks = <Stock>[];
      for (final stock in stocks) {
        if (_watchlistCodes.contains(stock.code)) {
          prioritizedStocks.add(stock);
        } else {
          otherStocks.add(stock);
        }
      }
      final orderedStocks = [...prioritizedStocks, ...otherStocks];

      // 清空旧数据，准备渐进式更新
      _allData = [];
      _minuteDataCount = 0;

      // 批量获取数据（渐进式更新）
      final result = await _stockService.batchGetMonitorData(
        orderedStocks,
        industryService: _industryService,
        onProgress: (current, total) {
          _progress = current;
          _total = total;
          if (!silent) {
            _updateProgress(RefreshStage.fetchMinuteData, current, total);
          }
          notifyListeners();
        },
        onData: (results) {
          _allData = results;
          notifyListeners();
        },
        onBarsData: (code, bars) {
          _minuteDataCount++;
        },
      );

      // 保存数据日期
      _dataDate = result.dataDate;
      developer.log('[MarketDataProvider.refresh] Got ${result.data.length} results, dataDate=${result.dataDate}, _allData=${_allData.length}');

      // Debug: if no results, set a temporary error message
      if (result.data.isEmpty && _allData.isEmpty) {
        _errorMessage = '调试: 获取到0条数据 (日期: ${result.dataDate})';
      }

      // Update stage to daily bars
      if (!silent) {
        _updateProgress(RefreshStage.updateDailyBars, 0, orderedStocks.length);
      }

      // 检测高质量回踩 (this fetches daily bars)
      if (_pullbackService != null && _allData.isNotEmpty) {
        try {
          await _detectPullbacks();
        } catch (e) {
          debugPrint('Pullback detection failed: $e');
        }
      }

      // 检测突破回踩
      if (_breakoutService != null && _allData.isNotEmpty) {
        try {
          await _detectBreakouts();
        } catch (e) {
          debugPrint('Breakout detection failed: $e');
        }
      }

      // Update stage to analyzing
      if (!silent) {
        _updateProgress(RefreshStage.analyzing, 0, 0);
      }

      // 更新时间
      final now = DateTime.now();
      _updateTime = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      // Reset to idle
      _stage = RefreshStage.idle;
      _stageDescription = null;
      _isLoading = false;
      _progress = 0;
      _total = 0;
      notifyListeners();

      // 保存到缓存
      await _saveToCache();
    } catch (e) {
      _stage = RefreshStage.error;
      _stageDescription = '获取数据失败';
      _errorMessage = '获取数据失败: $e';
      _isLoading = false;
      _progress = 0;
      _total = 0;
      notifyListeners();
    }
  }

  /// 检测高质量回踩（下载日K数据）
  /// 增量更新：如果当天已拉取过且缓存不为空，跳过重新拉取
  Future<void> _detectPullbacks() async {
    if (_pullbackService == null || _allData.isEmpty) return;

    // 检查是否需要重新拉取日K数据
    final today = DateTime.now().toString().substring(0, 10);
    final needFetchDaily = _lastFetchDate != today || _dailyBarsCache.isEmpty;

    if (needFetchDaily) {
      // 获取所有股票信息
      final stocks = _allData.map((d) => d.stock).toList();

      // 批量获取日K数据（15根，用于回踩检测）
      _dailyBarsCache.clear();
      var completed = 0;
      final total = stocks.length;

      await _pool.batchGetSecurityBarsStreaming(
        stocks: stocks,
        category: klineTypeDaily,
        start: 0,
        count: 60,
        onStockBars: (index, bars) {
          _dailyBarsCache[stocks[index].code] = bars;
          completed++;
          _updateProgress(RefreshStage.updateDailyBars, completed, total);
        },
      );
      // Schedule persistence of daily bars cache
      _schedulePersist();
    } else {
      // 跳过日K拉取，直接显示完成
      _updateProgress(RefreshStage.updateDailyBars, _dailyBarsCache.length, _dailyBarsCache.length);
    }

    // 使用缓存数据计算回踩
    _applyPullbackDetection();
  }

  /// 重算回踩（使用缓存的日K数据，不重新下载）
  /// 返回 null 表示成功，否则返回缺失数据的描述
  String? recalculatePullbacks() {
    if (_pullbackService == null) {
      return '回踩服务未初始化';
    }
    if (_allData.isEmpty) {
      return '缺失分钟数据，请先刷新';
    }
    if (_dailyBarsCache.isEmpty) {
      return '缺失日K数据，请先刷新';
    }
    _applyPullbackDetection();
    return null;
  }

  /// 应用回踩检测逻辑
  void _applyPullbackDetection() {
    if (_pullbackService == null) return;

    final updatedData = <StockMonitorData>[];
    for (final data in _allData) {
      final dailyBars = _dailyBarsCache[data.stock.code];
      final isPullback = dailyBars != null &&
          dailyBars.length >= 7 &&
          _pullbackService!.isPullback(dailyBars) &&
          data.ratio >= _pullbackService!.config.minMinuteRatio;

      updatedData.add(data.copyWith(isPullback: isPullback, isBreakout: data.isBreakout));
    }

    _allData = updatedData;
    notifyListeners();
  }

  /// 检测突破回踩
  Future<void> _detectBreakouts() async {
    if (_breakoutService == null || _allData.isEmpty || _dailyBarsCache.isEmpty) return;
    _applyBreakoutDetection();
  }

  /// 重算突破回踩（使用缓存的日K数据，不重新下载）
  /// 返回 null 表示成功，否则返回缺失数据的描述
  String? recalculateBreakouts() {
    if (_breakoutService == null) {
      return '突破服务未初始化';
    }
    if (_allData.isEmpty) {
      return '缺失分钟数据，请先刷新';
    }
    if (_dailyBarsCache.isEmpty) {
      return '缺失日K数据，请先刷新';
    }
    _applyBreakoutDetection();
    return null;
  }

  /// 应用突破回踩检测逻辑
  void _applyBreakoutDetection() {
    if (_breakoutService == null) return;

    final updatedData = <StockMonitorData>[];
    for (final data in _allData) {
      final dailyBars = _dailyBarsCache[data.stock.code];
      final isBreakout = dailyBars != null &&
          dailyBars.isNotEmpty &&
          _breakoutService!.isBreakoutPullback(dailyBars);

      updatedData.add(data.copyWith(isPullback: data.isPullback, isBreakout: isBreakout));
    }

    _allData = updatedData;
    notifyListeners();
  }

  // Size estimation methods
  int _estimateDailyBarsSize() {
    int total = 0;
    for (final bars in _dailyBarsCache.values) {
      total += bars.length * 50; // ~50 bytes per bar
    }
    return total;
  }

  int _estimateMinuteDataSize() {
    return _minuteDataCount * 240 * 40; // ~40 bytes per bar, ~240 bars per stock
  }

  int _estimateIndustryDataSize() {
    // Rough estimate: ~100KB for industry data
    return 100 * 1024;
  }

  int _estimateTotalSize() {
    return _estimateDailyBarsSize() +
        _estimateMinuteDataSize() +
        (_industryService.isLoaded ? _estimateIndustryDataSize() : 0);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '<1KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  // Clear cache methods
  Future<void> clearDailyBarsCache() async {
    _dailyBarsCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dailyBarsCacheKey);
    notifyListeners();
  }

  Future<void> clearMinuteDataCache() async {
    _minuteDataCount = 0;
    notifyListeners();
  }

  Future<void> clearIndustryDataCache() async {
    // IndustryService may not have clearCache, so just reload
    // For now, just notify - the industry data is loaded fresh on startup
    notifyListeners();
  }

  Future<void> clearAllCache() async {
    await clearDailyBarsCache();
    await clearMinuteDataCache();
    await clearIndustryDataCache();
  }
}
