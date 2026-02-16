import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/config/debug_config.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';

/// 在隔离线程中解析股票监控数据 JSON
List<StockMonitorData> _parseMarketDataJson(String jsonStr) {
  final List<dynamic> jsonList = json.decode(jsonStr);
  return jsonList
      .map((e) => StockMonitorData.fromJson(e as Map<String, dynamic>))
      .toList();
}

enum RefreshStage {
  idle, // 空闲
  fetchMinuteData, // 拉取分时数据
  updateDailyBars, // 更新日K数据
  analyzing, // 分析计算
  error, // 错误
}

class MarketDataProvider extends ChangeNotifier {
  final TdxPool _pool;
  final StockService _stockService;
  final IndustryService _industryService;
  final DailyKlineCacheStore _dailyKlineCacheStore;
  PullbackService? _pullbackService;
  BreakoutService? _breakoutService;
  MacdIndicatorService? _macdService;

  List<StockMonitorData> _allData = [];
  bool _isLoading = false;
  int _progress = 0;
  int _total = 0;
  String? _updateTime;
  DateTime? _dataDate;
  String? _errorMessage;

  // Refresh stage tracking
  RefreshStage _stage = RefreshStage.idle;
  String? _stageDescription; // "拉取分时 32/156"
  int _stageProgress = 0; // 当前进度
  int _stageTotal = 0; // 总数
  String? _lastFetchDate; // "2026-01-21" for incremental fetching

  // Cache keys
  static const String _dailyBarsCacheKey = 'daily_bars_cache_v1';
  static const int _dailyCacheTargetBars = 260;
  static const int _breakoutDetectMaxConcurrency = 6;
  static const String _minuteDataCacheKey = 'minute_data_cache_v1';
  static const String _minuteDataDateKey = 'minute_data_date';
  static const String _lastFetchDateKey = 'last_fetch_date';

  // Watchlist codes for priority sorting
  Set<String> _watchlistCodes = {};

  // 缓存日K数据用于重算回踩
  Map<String, List<KLine>> _dailyBarsCache = {};
  int _dailyBarsDiskCacheCount = 0;
  int _dailyBarsDiskCacheBytes = 0;

  // 分时数据计数（不保留完整对象，避免 Android OOM）
  int _minuteDataCount = 0;

  MarketDataProvider({
    required TdxPool pool,
    required StockService stockService,
    required IndustryService industryService,
    DailyKlineCacheStore? dailyBarsFileStorage,
  }) : _pool = pool,
       _stockService = stockService,
       _industryService = industryService,
       _dailyKlineCacheStore = dailyBarsFileStorage ?? DailyKlineCacheStore();

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
  int get dailyBarsCacheCount =>
      math.max(_dailyBarsCache.length, _dailyBarsDiskCacheCount);

  /// 获取日K缓存数据（用于回测）
  Map<String, List<KLine>> get dailyBarsCache => _dailyBarsCache;

  /// 获取股票数据映射（用于回测）
  Map<String, StockMonitorData> get stockDataMap {
    return {for (final data in _allData) data.stock.code: data};
  }

  String get dailyBarsCacheSize => _formatSize(_effectiveDailyBarsSize);
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

    int limitUp = 0; // >= 9.8%
    int up5 = 0; // 5% ~ 9.8%
    int up0to5 = 0; // 0 < x < 5%
    int flat = 0; // == 0
    int down0to5 = 0; // -5% < x < 0
    int down5 = 0; // -9.8% < x <= -5%
    int limitDown = 0; // <= -9.8%

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

  /// 设置MACD指标服务（用于日/周线MACD计算与缓存）
  void setMacdService(MacdIndicatorService service) {
    _macdService = service;
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

      // Daily bars are no longer persisted in SharedPreferences because
      // a one-year payload can trigger Android SharedPreferences/OOM crashes.
      // Keep an explicit migration cleanup for legacy payload.
      if (prefs.containsKey(_dailyBarsCacheKey)) {
        await prefs.remove(_dailyBarsCacheKey);
      }

      // Load last fetch date
      _lastFetchDate = prefs.getString(_lastFetchDateKey);

      // Load minute cache metadata
      final minuteDataDate = prefs.getString(_minuteDataDateKey);
      if (minuteDataDate != null && _dataDate == null) {
        _dataDate = DateTime.tryParse(minuteDataDate);
      }

      final minuteDataCount = prefs.getInt(_minuteDataCacheKey);
      if (minuteDataCount != null && minuteDataCount > 0) {
        _minuteDataCount = minuteDataCount;
      } else if (_allData.isNotEmpty) {
        _minuteDataCount = _allData.length;
      }

      await _restoreDailyBarsForCachedData();
      await _refreshDailyBarsDiskStats(notifyIfChanged: true);
    } catch (e) {
      debugPrint('Failed to load cache: $e');
    }
  }

  Future<void> _restoreDailyBarsForCachedData() async {
    if (_allData.isEmpty) {
      return;
    }

    final stockCodes = _allData
        .map((item) => item.stock.code)
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (stockCodes.isEmpty) {
      return;
    }

    final anchorDate = _dataDate ?? DateTime.now();
    final beforeCount = _dailyBarsCache.length;
    await _restoreDailyBarsFromFile(
      stockCodes,
      anchorDate: anchorDate,
      targetBars: _dailyCacheTargetBars,
    );

    if (_dailyBarsCache.length != beforeCount) {
      notifyListeners();
    }
  }

  Future<void> _refreshDailyBarsDiskStats({
    bool notifyIfChanged = false,
  }) async {
    try {
      final stats = await _dailyKlineCacheStore.getSnapshotStats();
      final changed =
          stats.stockCount != _dailyBarsDiskCacheCount ||
          stats.totalBytes != _dailyBarsDiskCacheBytes;

      if (!changed) {
        return;
      }

      _dailyBarsDiskCacheCount = stats.stockCount;
      _dailyBarsDiskCacheBytes = stats.totalBytes;
      if (notifyIfChanged) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to refresh daily bars disk stats: $e');
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
        await prefs.setString(_minuteDataDateKey, _dataDate!.toIso8601String());
      }
      await prefs.setInt(_minuteDataCacheKey, _minuteDataCount);
      // Ensure legacy heavy payload is not retained in SharedPreferences.
      await prefs.remove(_dailyBarsCacheKey);
      if (_lastFetchDate != null) {
        await prefs.setString(_lastFetchDateKey, _lastFetchDate!);
      }
    } catch (e) {
      debugPrint('Failed to save cache: $e');
    }
  }

  /// 刷新数据
  Future<void> refresh({
    bool silent = false,
    bool forceMinuteRefetch = false,
    bool forceDailyRefetch = false,
  }) async {
    print(
      '🔍 [MarketDataProvider.refresh] Called at ${DateTime.now()}, isLoading=$_isLoading',
    );
    developer.log(
      '[MarketDataProvider.refresh] Called at ${DateTime.now()}, isLoading=$_isLoading',
    );
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

      if (!forceMinuteRefetch && _canReuseMinuteDataCache()) {
        debugPrint(
          '[MarketDataProvider] 分时缓存可复用，跳过重新拉取 ($_minuteDataCount只, dataDate=$_dataDate)',
        );

        if (!silent) {
          final totalCached = _minuteDataCount > 0
              ? _minuteDataCount
              : _allData.length;
          _updateProgress(
            RefreshStage.fetchMinuteData,
            totalCached,
            totalCached,
          );
        }

        if (_pullbackService != null && _allData.isNotEmpty) {
          try {
            await _detectPullbacks(forceRefetchDaily: forceDailyRefetch);
          } catch (e) {
            debugPrint('Pullback detection failed: $e');
          }
        }

        if (_breakoutService != null && _allData.isNotEmpty) {
          try {
            await _detectBreakouts();
          } catch (e) {
            debugPrint('Breakout detection failed: $e');
          }
        }

        if (_macdService != null && _dailyBarsCache.isNotEmpty) {
          try {
            await _prewarmDailyMacd();
          } catch (e) {
            debugPrint('MACD prewarm failed: $e');
          }
        }

        if (!silent) {
          _updateProgress(RefreshStage.analyzing, 0, 0);
        }

        final now = DateTime.now();
        _updateTime =
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}:'
            '${now.second.toString().padLeft(2, '0')}';

        _stage = RefreshStage.idle;
        _stageDescription = null;
        _isLoading = false;
        _progress = 0;
        _total = 0;
        notifyListeners();

        await _saveToCache();
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
      developer.log(
        '[MarketDataProvider.refresh] Got ${result.data.length} results, dataDate=${result.dataDate}, _allData=${_allData.length}',
      );

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
          await _detectPullbacks(forceRefetchDaily: forceDailyRefetch);
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

      if (_macdService != null && _dailyBarsCache.isNotEmpty) {
        try {
          await _prewarmDailyMacd();
        } catch (e) {
          debugPrint('MACD prewarm failed: $e');
        }
      }

      // Update stage to analyzing
      if (!silent) {
        _updateProgress(RefreshStage.analyzing, 0, 0);
      }

      // 更新时间
      final now = DateTime.now();
      _updateTime =
          '${now.hour.toString().padLeft(2, '0')}:'
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

  Future<void> forceReloadIndustryData() async {
    await _industryService.load();

    if (_allData.isNotEmpty) {
      _allData = _allData
          .map(
            (data) => StockMonitorData(
              stock: data.stock,
              ratio: data.ratio,
              changePercent: data.changePercent,
              industry: _industryService.getIndustry(data.stock.code),
              isPullback: data.isPullback,
              isBreakout: data.isBreakout,
              upVolume: data.upVolume,
              downVolume: data.downVolume,
            ),
          )
          .toList(growable: false);
    }

    notifyListeners();
    await _saveToCache();
  }

  Future<void> forceRefetchDailyBars({
    void Function(String stage, int current, int total)? onProgress,
  }) async {
    if (_allData.isEmpty) return;

    final totalStocks = _allData.length <= 0 ? 1 : _allData.length;
    final totalStopwatch = Stopwatch()..start();
    final stageStopwatch = Stopwatch();

    void resetStageTimer() {
      stageStopwatch
        ..reset()
        ..start();
    }

    resetStageTimer();
    onProgress?.call('连接数据源...', 0, 1);
    final connected = await _pool.ensureConnected();
    if (!connected) {
      throw StateError('无法连接到服务器');
    }
    onProgress?.call('连接数据源...', 1, 1);
    stageStopwatch.stop();
    final connectMs = stageStopwatch.elapsedMilliseconds;

    resetStageTimer();
    onProgress?.call('1/4 拉取日K数据...', 0, totalStocks);
    await _detectPullbacks(
      forceRefetchDaily: true,
      onDailyProgress: (current, total) {
        final safeTotal = total <= 0 ? totalStocks : total;
        final safeCurrent = current.clamp(0, safeTotal);
        onProgress?.call('1/4 拉取日K数据...', safeCurrent, safeTotal);
      },
      onDailyFilePersistProgress: (current, total) {
        final safeTotal = total <= 0 ? totalStocks : total;
        final safeCurrent = current.clamp(0, safeTotal);
        onProgress?.call('2/4 写入日K文件...', safeCurrent, safeTotal);
      },
    );
    stageStopwatch.stop();
    final fetchAndPersistMs = stageStopwatch.elapsedMilliseconds;

    resetStageTimer();
    onProgress?.call('3/4 计算指标...', 0, totalStocks);
    await _detectBreakouts(
      onProgress: (current, total) {
        final safeTotal = total <= 0 ? totalStocks : total;
        final safeCurrent = current.clamp(0, safeTotal);
        onProgress?.call('3/4 计算指标...', safeCurrent, safeTotal);
      },
    );

    await _prewarmDailyMacd(
      onProgress: (current, total) {
        final safeTotal = total <= 0 ? totalStocks : total;
        final safeCurrent = current.clamp(0, safeTotal);
        onProgress?.call('3/4 计算指标...', safeCurrent, safeTotal);
      },
    );
    stageStopwatch.stop();
    final indicatorsMs = stageStopwatch.elapsedMilliseconds;

    resetStageTimer();
    onProgress?.call('4/4 保存缓存元数据...', 0, 1);
    await _saveToCache();
    onProgress?.call('4/4 保存缓存元数据...', 1, 1);
    stageStopwatch.stop();
    final saveMetaMs = stageStopwatch.elapsedMilliseconds;

    totalStopwatch.stop();
    debugPrint(
      '[MarketDataProvider][timing] forceRefetchDailyBars '
      'connectMs=$connectMs, fetchAndPersistMs=$fetchAndPersistMs, '
      'indicatorsMs=$indicatorsMs, saveMetaMs=$saveMetaMs, '
      'totalMs=${totalStopwatch.elapsedMilliseconds}',
    );
  }

  bool _canReuseMinuteDataCache() {
    if (_allData.isEmpty || _dataDate == null) {
      return false;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dataDate = DateTime(
      _dataDate!.year,
      _dataDate!.month,
      _dataDate!.day,
    );

    // 交易日内：缓存日期即今天
    if (dataDate == today) {
      return true;
    }

    // 非交易日（周末）：允许复用最近一个工作日的缓存
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      final lastWeekday = _latestWeekday(today);
      return dataDate == lastWeekday;
    }

    return false;
  }

  DateTime _latestWeekday(DateTime day) {
    var cursor = DateTime(
      day.year,
      day.month,
      day.day,
    ).subtract(const Duration(days: 1));
    while (cursor.weekday == DateTime.saturday ||
        cursor.weekday == DateTime.sunday) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return cursor;
  }

  /// 检测高质量回踩（下载日K数据）
  /// 增量更新：如果当天已拉取过且缓存完整，跳过重新拉取
  Future<void> _detectPullbacks({
    bool forceRefetchDaily = false,
    void Function(int current, int total)? onDailyProgress,
    void Function(int current, int total)? onDailyFilePersistProgress,
  }) async {
    if (_pullbackService == null || _allData.isEmpty) return;

    // 获取所有股票信息
    final stocks = _allData.map((d) => d.stock).toList();

    // 检查是否需要重新拉取日K数据。
    // 非交易日场景下，使用分钟监控结果的 dataDate 作为“有效交易日”。
    final effectiveDate = _dataDate ?? DateTime.now();
    final effectiveDateKey =
        '${effectiveDate.year.toString().padLeft(4, '0')}-'
        '${effectiveDate.month.toString().padLeft(2, '0')}-'
        '${effectiveDate.day.toString().padLeft(2, '0')}';
    final stockCodeSet = stocks.map((stock) => stock.code).toSet();
    _dailyBarsCache.removeWhere((code, _) => !stockCodeSet.contains(code));

    final missingCodes = stocks
        .where((stock) => !_dailyBarsCache.containsKey(stock.code))
        .map((stock) => stock.code)
        .toList(growable: false);

    if (!forceRefetchDaily &&
        _lastFetchDate == effectiveDateKey &&
        missingCodes.isNotEmpty) {
      await _restoreDailyBarsFromFile(
        missingCodes,
        anchorDate: effectiveDate,
        targetBars: _dailyCacheTargetBars,
      );
    }

    final cacheIncomplete = _dailyBarsCache.length < stocks.length;
    final needFetchDaily =
        forceRefetchDaily ||
        _lastFetchDate != effectiveDateKey ||
        _dailyBarsCache.isEmpty ||
        cacheIncomplete;

    if (cacheIncomplete && _dailyBarsCache.isNotEmpty) {
      debugPrint(
        '[MarketDataProvider] 日K缓存不完整: ${_dailyBarsCache.length}/${stocks.length}，将重新拉取',
      );
    }

    if (needFetchDaily) {
      // 批量获取日K数据（约1年交易日，用于指标计算）
      _dailyBarsCache.clear();
      var completed = 0;
      final total = stocks.length;

      await _pool.batchGetSecurityBarsStreaming(
        stocks: stocks,
        category: klineTypeDaily,
        start: 0,
        count: _dailyCacheTargetBars,
        onStockBars: (index, bars) {
          _dailyBarsCache[stocks[index].code] = bars;
          completed++;
          _updateProgress(RefreshStage.updateDailyBars, completed, total);
          onDailyProgress?.call(completed, total);
        },
      );

      await _persistDailyBarsToFile(
        stockCodeSet,
        onProgress: onDailyFilePersistProgress,
      );
      _lastFetchDate = effectiveDateKey;
    } else {
      // 跳过日K拉取，直接显示完成
      _updateProgress(
        RefreshStage.updateDailyBars,
        _dailyBarsCache.length,
        _dailyBarsCache.length,
      );
      onDailyProgress?.call(
        _dailyBarsCache.length,
        _dailyBarsCache.isEmpty ? 1 : _dailyBarsCache.length,
      );
      onDailyFilePersistProgress?.call(
        _dailyBarsCache.length,
        _dailyBarsCache.isEmpty ? 1 : _dailyBarsCache.length,
      );
    }

    // 使用缓存数据计算回踩
    _applyPullbackDetection();
  }

  Future<void> _persistDailyBarsToFile(
    Set<String> stockCodeSet, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (_dailyBarsCache.isEmpty || stockCodeSet.isEmpty) return;

    final payload = <String, List<KLine>>{};
    for (final code in stockCodeSet) {
      final bars = _dailyBarsCache[code];
      if (bars != null && bars.isNotEmpty) {
        payload[code] = bars;
      }
    }
    if (payload.isEmpty) return;

    try {
      await _dailyKlineCacheStore.saveAll(payload, onProgress: onProgress);
      await _refreshDailyBarsDiskStats();
    } catch (e) {
      debugPrint('Failed to persist daily bars to file storage: $e');
    }
  }

  Future<void> _prewarmDailyMacd({
    void Function(int current, int total)? onProgress,
  }) async {
    if (_macdService == null || _dailyBarsCache.isEmpty) {
      return;
    }

    final payload = <String, List<KLine>>{};
    for (final entry in _dailyBarsCache.entries) {
      if (entry.value.isNotEmpty) {
        payload[entry.key] = entry.value;
      }
    }
    if (payload.isEmpty) {
      return;
    }

    await _macdService!.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
      onProgress: onProgress,
    );
  }

  Future<void> _restoreDailyBarsFromFile(
    List<String> stockCodes, {
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    if (stockCodes.isEmpty) return;

    try {
      final loaded = await _dailyKlineCacheStore.loadForStocks(
        stockCodes,
        anchorDate: DateTime(anchorDate.year, anchorDate.month, anchorDate.day),
        targetBars: targetBars,
      );
      if (loaded.isEmpty) return;

      for (final entry in loaded.entries) {
        _dailyBarsCache[entry.key] = entry.value;
      }
    } catch (e) {
      debugPrint('Failed to restore daily bars from file storage: $e');
    }
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
      final isPullback =
          dailyBars != null &&
          dailyBars.length >= 7 &&
          _pullbackService!.isPullback(dailyBars) &&
          data.ratio >= _pullbackService!.config.minMinuteRatio;

      updatedData.add(
        data.copyWith(isPullback: isPullback, isBreakout: data.isBreakout),
      );
    }

    _allData = updatedData;
    notifyListeners();
  }

  /// 检测突破回踩
  Future<void> _detectBreakouts({
    void Function(int current, int total)? onProgress,
  }) async {
    if (_breakoutService == null ||
        _allData.isEmpty ||
        _dailyBarsCache.isEmpty) {
      return;
    }
    await _applyBreakoutDetection(onProgress: onProgress);
  }

  /// 重算突破回踩（使用缓存的日K数据，不重新下载）
  /// 返回 null 表示成功，否则返回缺失数据的描述
  /// [onProgress] 进度回调，参数为 (当前进度, 总数)
  Future<String?> recalculateBreakouts({
    void Function(int current, int total)? onProgress,
  }) async {
    if (_breakoutService == null) {
      return '突破服务未初始化';
    }
    if (_allData.isEmpty) {
      return '缺失分钟数据，请先刷新';
    }
    if (_dailyBarsCache.isEmpty) {
      return '缺失日K数据，请先刷新';
    }
    await _applyBreakoutDetection(onProgress: onProgress);
    return null;
  }

  /// 应用突破回踩检测逻辑
  /// [onProgress] 进度回调，参数为 (当前进度, 总数)
  Future<void> _applyBreakoutDetection({
    void Function(int current, int total)? onProgress,
  }) async {
    if (_breakoutService == null) return;

    final total = _allData.length;
    if (total <= 0) return;

    final updatedData = List<StockMonitorData?>.filled(total, null);
    var nextIndex = 0;
    var completed = 0;
    final workerCount = math.min(_breakoutDetectMaxConcurrency, total);

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        if (index >= total) {
          return;
        }
        nextIndex++;

        final data = _allData[index];
        final dailyBars = _dailyBarsCache[data.stock.code];

        var isBreakout = false;
        if (dailyBars != null && dailyBars.length >= 6) {
          isBreakout = await _breakoutService!.isBreakoutPullback(
            dailyBars,
            stockCode: data.stock.code,
          );

          // 检查今日分钟量比条件
          if (isBreakout && _breakoutService!.config.minMinuteRatio > 0) {
            isBreakout = data.ratio >= _breakoutService!.config.minMinuteRatio;
          }

          // 检查是否过滤暴涨
          if (isBreakout && _breakoutService!.config.filterSurgeAfterPullback) {
            final todayGain = data.changePercent / 100;
            if (todayGain > _breakoutService!.config.surgeThreshold) {
              isBreakout = false;
            }
          }
        }

        updatedData[index] = data.copyWith(
          isPullback: data.isPullback,
          isBreakout: isBreakout,
        );
        completed++;
        onProgress?.call(completed, total);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => runWorker()),
    );

    _allData = updatedData.cast<StockMonitorData>();
    notifyListeners();
  }

  // Size estimation methods
  int get _effectiveDailyBarsSize =>
      math.max(_estimateDailyBarsSize(), _dailyBarsDiskCacheBytes);

  int _estimateDailyBarsSize() {
    int total = 0;
    for (final bars in _dailyBarsCache.values) {
      total += bars.length * 50; // ~50 bytes per bar
    }
    return total;
  }

  int _estimateMinuteDataSize() {
    return _minuteDataCount *
        240 *
        40; // ~40 bytes per bar, ~240 bars per stock
  }

  int _estimateIndustryDataSize() {
    // Rough estimate: ~100KB for industry data
    return 100 * 1024;
  }

  int _estimateTotalSize() {
    return _effectiveDailyBarsSize +
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
    _lastFetchDate = null;
    await prefs.remove(_lastFetchDateKey);

    try {
      final stockCodes = _allData
          .map((item) => item.stock.code)
          .toList(growable: false);
      await _dailyKlineCacheStore.clearForStocks(
        stockCodes,
        anchorDate: _dataDate ?? DateTime.now(),
      );
      await _refreshDailyBarsDiskStats();
    } catch (e) {
      debugPrint('Failed to clear daily bars file cache: $e');
    }

    notifyListeners();
  }

  Future<void> clearMinuteDataCache() async {
    _minuteDataCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_minuteDataCacheKey);
    await prefs.remove(_minuteDataDateKey);
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
