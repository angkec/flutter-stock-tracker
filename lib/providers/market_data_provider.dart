import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/config/debug_config.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/market_snapshot_store.dart';
import 'package:stock_rtwatcher/data/storage/power_system_cache_store.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/daily_kline_read_service.dart';
import 'package:stock_rtwatcher/services/daily_kline_sync_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/power_system_indicator_service.dart';
import 'package:stock_rtwatcher/services/industry_ema_breadth_service.dart';
import 'package:stock_rtwatcher/services/china_trading_calendar_service.dart';

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
  final ChinaTradingCalendarService _tradingCalendarService;
  final DateTime Function() _nowProvider;
  final DailyKlineCacheStore _dailyKlineCacheStore;
  final MarketSnapshotStore _marketSnapshotStore;
  late final DailyKlineReadService _dailyKlineReadService;
  late final DailyKlineSyncService _dailyKlineSyncService;
  PullbackService? _pullbackService;
  BreakoutService? _breakoutService;
  MacdIndicatorService? _macdService;
  AdxIndicatorService? _adxService;
  EmaIndicatorService? _emaService;
  PowerSystemIndicatorService? _powerSystemService;
  IndustryEmaBreadthService? _industryEmaBreadthService;
  PowerSystemCacheStore? _powerSystemCacheStore;

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

  // Cache keys
  static const String _dailyBarsCacheKey = 'daily_bars_cache_v1';
  static const String _marketDataCacheKey = 'market_data_cache';
  static const int _dailyCacheTargetBars = 260;
  static const int _breakoutDetectMaxConcurrency = 6;
  static const String _minuteDataCacheKey = 'minute_data_cache_v1';
  static const String _minuteDataDateKey = 'minute_data_date';
  static const Duration _calendarRemoteRefreshTimeout = Duration(seconds: 3);

  // Watchlist codes for priority sorting
  Set<String> _watchlistCodes = {};

  // 缓存日K数据用于重算回踩
  Map<String, List<KLine>> _dailyBarsCache = {};
  int _dailyBarsDiskCacheCount = 0;
  int _dailyBarsDiskCacheBytes = 0;
  DailySyncCompletenessState _lastDailySyncCompletenessState =
      DailySyncCompletenessState.unknownRetry;
  DailyKlineReadReport? _lastDailySyncReadReport;

  // 分时数据计数（不保留完整对象，避免 Android OOM）
  int _minuteDataCount = 0;

  MarketDataProvider({
    required TdxPool pool,
    required StockService stockService,
    required IndustryService industryService,
    DailyKlineCacheStore? dailyBarsFileStorage,
    DailyKlineCheckpointStore? dailyKlineCheckpointStore,
    DailyKlineReadService? dailyKlineReadService,
    DailyKlineSyncService? dailyKlineSyncService,
    MarketSnapshotStore? marketSnapshotStore,
    ChinaTradingCalendarService? tradingCalendarService,
    DateTime Function()? nowProvider,
  }) : _pool = pool,
       _stockService = stockService,
       _industryService = industryService,
       _tradingCalendarService =
           tradingCalendarService ?? const ChinaTradingCalendarService(),
       _nowProvider = nowProvider ?? DateTime.now,
       _dailyKlineCacheStore = dailyBarsFileStorage ?? DailyKlineCacheStore(),
       _marketSnapshotStore = marketSnapshotStore ?? MarketSnapshotStore() {
    final checkpointStore =
        dailyKlineCheckpointStore ?? DailyKlineCheckpointStore();
    _dailyKlineReadService =
        dailyKlineReadService ??
        DailyKlineReadService(cacheStore: _dailyKlineCacheStore);
    _dailyKlineSyncService =
        dailyKlineSyncService ??
        DailyKlineSyncService(
          checkpointStore: checkpointStore,
          cacheStore: _dailyKlineCacheStore,
          fetcher: _fetchDailyBarsFromPool,
        );
    _powerSystemCacheStore = PowerSystemCacheStore();
  }

  Future<Map<String, List<KLine>>> _fetchDailyBarsFromPool({
    required List<Stock> stocks,
    required int count,
    required DailyKlineSyncMode mode,
    void Function(int current, int total)? onProgress,
  }) async {
    final barsByStockCode = <String, List<KLine>>{};
    var completed = 0;
    final total = stocks.length;

    await _pool.batchGetSecurityBarsStreaming(
      stocks: stocks,
      category: klineTypeDaily,
      start: 0,
      count: count,
      onStockBars: (stockIndex, bars) {
        final stockCode = stocks[stockIndex].code;
        barsByStockCode[stockCode] = bars;
        completed++;
        onProgress?.call(completed, total);
      },
    );

    return barsByStockCode;
  }

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
  DailySyncCompletenessState get lastDailySyncCompletenessState =>
      _lastDailySyncCompletenessState;
  String get lastDailySyncCompletenessStateWire =>
      _lastDailySyncCompletenessState.wireValue;
  DailyKlineReadReport? get lastDailySyncReadReport => _lastDailySyncReadReport;
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

  /// 设置ADX指标服务（用于日/周线ADX计算与缓存）
  void setAdxService(AdxIndicatorService service) {
    _adxService = service;
  }

  /// 设置EMA指标服务（用于日/周线EMA计算与缓存）
  void setEmaService(EmaIndicatorService service) {
    _emaService = service;
  }

  /// 设置Power System指标服务（用于日/周线状态缓存）
  void setPowerSystemService(PowerSystemIndicatorService service) {
    _powerSystemService = service;
  }

  /// 设置行业EMA广度服务（用于行业EMA广度计算与缓存）
  void setIndustryEmaBreadthService(IndustryEmaBreadthService service) {
    _industryEmaBreadthService = service;
  }

  /// 获取行业EMA广度服务
  IndustryEmaBreadthService? get industryEmaBreadthService =>
      _industryEmaBreadthService;

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
    await _loadCachedTradingCalendarBestEffort();

    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString('market_data_time');
      final dateStr = prefs.getString('market_data_date');
      final minuteDataDate = prefs.getString(_minuteDataDateKey);
      final hasMinuteMetadata =
          timeStr != null || dateStr != null || minuteDataDate != null;
      final snapshotJson = hasMinuteMetadata
          ? await _marketSnapshotStore.loadJson()
          : null;
      final legacyJson = prefs.getString(_marketDataCacheKey);

      if (legacyJson != null) {
        _allData = _parseMarketDataJson(legacyJson);
        _updateTime = timeStr;
        if (dateStr != null) {
          _dataDate = DateTime.tryParse(dateStr);
        } else if (minuteDataDate != null) {
          _dataDate = DateTime.tryParse(minuteDataDate);
        }
        notifyListeners();

        // One-time migration from legacy SharedPreferences payload.
        await _marketSnapshotStore.saveJson(legacyJson);
        await prefs.remove(_marketDataCacheKey);
      } else if (snapshotJson != null) {
        _allData = _parseMarketDataJson(snapshotJson);
        _updateTime = timeStr;
        if (dateStr != null) {
          _dataDate = DateTime.tryParse(dateStr);
        } else if (minuteDataDate != null) {
          _dataDate = DateTime.tryParse(minuteDataDate);
        }
        notifyListeners();
      }

      // Daily bars are no longer persisted in SharedPreferences because
      // a one-year payload can trigger Android SharedPreferences/OOM crashes.
      // Keep an explicit migration cleanup for legacy payload.
      if (prefs.containsKey(_dailyBarsCacheKey)) {
        await prefs.remove(_dailyBarsCacheKey);
      }

      // Load minute cache metadata
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
      await _marketSnapshotStore.saveJson(json.encode(jsonList));
      await _saveCacheMetadataOnly(prefs: prefs);
    } catch (e) {
      debugPrint('Failed to save cache: $e');
    }
  }

  Future<void> _saveCacheMetadataOnly({SharedPreferences? prefs}) async {
    final targetPrefs = prefs ?? await SharedPreferences.getInstance();
    if (_updateTime != null) {
      await targetPrefs.setString('market_data_time', _updateTime!);
    }
    if (_dataDate != null) {
      final dateIso = _dataDate!.toIso8601String();
      await targetPrefs.setString('market_data_date', dateIso);
      await targetPrefs.setString(_minuteDataDateKey, dateIso);
    }
    await targetPrefs.setInt(_minuteDataCacheKey, _minuteDataCount);
    // Ensure legacy heavy payloads are not retained in SharedPreferences.
    await targetPrefs.remove(_dailyBarsCacheKey);
    await targetPrefs.remove(_marketDataCacheKey);
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

    unawaited(_refreshRemoteTradingCalendarBestEffort());

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
            await _detectPullbacks();
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

        if (_adxService != null && _dailyBarsCache.isNotEmpty) {
          try {
            await _prewarmDailyAdx();
          } catch (e) {
            debugPrint('ADX prewarm failed: $e');
          }
        }

        if (_emaService != null && _dailyBarsCache.isNotEmpty) {
          try {
            await _prewarmDailyEma();
          } catch (e) {
            debugPrint('EMA prewarm failed: $e');
          }
        }

        if (_powerSystemService != null && _dailyBarsCache.isNotEmpty) {
          try {
            await _prewarmDailyPowerSystem();
          } catch (e) {
            debugPrint('Power System prewarm failed: $e');
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

      if (_macdService != null && _dailyBarsCache.isNotEmpty) {
        try {
          await _prewarmDailyMacd();
        } catch (e) {
          debugPrint('MACD prewarm failed: $e');
        }
      }

      if (_adxService != null && _dailyBarsCache.isNotEmpty) {
        try {
          await _prewarmDailyAdx();
        } catch (e) {
          debugPrint('ADX prewarm failed: $e');
        }
      }

      if (_emaService != null && _dailyBarsCache.isNotEmpty) {
        try {
          await _prewarmDailyEma();
        } catch (e) {
          debugPrint('EMA prewarm failed: $e');
        }
      }

      if (_powerSystemService != null && _dailyBarsCache.isNotEmpty) {
        try {
          await _prewarmDailyPowerSystem();
        } catch (e) {
          debugPrint('Power System prewarm failed: $e');
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
    Set<String>? indicatorTargetStockCodes,
  }) async {
    await syncDailyBarsForceFull(
      onProgress: onProgress,
      indicatorTargetStockCodes: indicatorTargetStockCodes,
    );
  }

  Future<void> syncDailyBarsIncremental({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    await _syncDailyBars(
      mode: DailyKlineSyncMode.incremental,
      onProgress: onProgress,
      indicatorTargetStockCodes: indicatorTargetStockCodes,
    );
  }

  Future<void> syncDailyBarsForceFull({
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    await _syncDailyBars(
      mode: DailyKlineSyncMode.forceFull,
      onProgress: onProgress,
      indicatorTargetStockCodes: indicatorTargetStockCodes,
    );
  }

  Future<void> _syncDailyBars({
    required DailyKlineSyncMode mode,
    void Function(String stage, int current, int total)? onProgress,
    Set<String>? indicatorTargetStockCodes,
  }) async {
    if (_allData.isEmpty) return;

    final totalStocks = _allData.length <= 0 ? 1 : _allData.length;
    if (kDebugMode) {
      debugPrint(
        '[DailySync] start mode=$mode stocks=$totalStocks '
        'targetBars=$_dailyCacheTargetBars '
        'indicatorTargets=${indicatorTargetStockCodes?.length ?? 0}',
      );
    }
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

    final stocks = _allData.map((item) => item.stock).toList(growable: false);
    _lastDailySyncCompletenessState = DailySyncCompletenessState.unknownRetry;

    resetStageTimer();
    final syncResult = await _dailyKlineSyncService.sync(
      mode: mode,
      stocks: stocks,
      targetBars: _dailyCacheTargetBars,
      onProgress: (stage, current, total) {
        if (!stage.startsWith('1/4') && !stage.startsWith('2/4')) {
          return;
        }
        final safeTotal = total <= 0 ? totalStocks : total;
        final safeCurrent = current.clamp(0, safeTotal);
        onProgress?.call(stage, safeCurrent, safeTotal);
      },
    );
    _lastDailySyncCompletenessState = syncResult.completenessState;
    if (kDebugMode) {
      debugPrint(
        '[DailySync] sync finished completeness=$_lastDailySyncCompletenessState '
        'failures=${syncResult.failureStockCodes.length}',
      );
    }

    if (syncResult.failureStockCodes.isNotEmpty) {
      throw StateError(
        '部分股票日K拉取失败(${syncResult.failureStockCodes.length}): '
        '${syncResult.failureStockCodes.take(8).join(', ')}',
      );
    }

    _lastDailySyncReadReport = null;
    if (kDebugMode) {
      debugPrint(
        '[DailySync] reload daily bars start '
        'stocks=${stocks.length} '
        'anchorDate=${_dataDate ?? DateTime.now()} '
        'targetBars=$_dailyCacheTargetBars',
      );
    }
    DailyKlineReadReport readReport;
    try {
      readReport = await _reloadDailyBarsWithReport(
        stockCodes: stocks.map((stock) => stock.code).toList(growable: false),
        anchorDate: _dataDate ?? DateTime.now(),
        targetBars: _dailyCacheTargetBars,
      );
    } catch (error, stackTrace) {
      debugPrint('[DailySync] reload daily bars failed: $error');
      if (kDebugMode) {
        debugPrint('$stackTrace');
      }
      rethrow;
    }
    if (kDebugMode) {
      debugPrint(
        '[DailySync] reload daily bars done '
        'cacheSize=${_dailyBarsCache.length} '
        'missing=${readReport.missingCount} '
        'corrupted=${readReport.corruptedCount} '
        'insufficient=${readReport.insufficientCount}',
      );
    }

    stageStopwatch.stop();
    final fetchAndPersistMs = stageStopwatch.elapsedMilliseconds;

    final normalizedIndicatorTargets = indicatorTargetStockCodes == null
        ? null
        : indicatorTargetStockCodes
              .where((code) => _dailyBarsCache.containsKey(code))
              .toSet();
    final indicatorTotal = normalizedIndicatorTargets == null
        ? totalStocks
        : normalizedIndicatorTargets.length;

    if (kDebugMode) {
      debugPrint(
        '[DailySync] indicators start '
        'targets=$indicatorTotal '
        'cacheSize=${_dailyBarsCache.length} '
        'breakout=${_breakoutService != null} '
        'macd=${_macdService != null} '
        'adx=${_adxService != null} '
        'ema=${_emaService != null}',
      );
    }

    resetStageTimer();
    onProgress?.call(
      '3/4 计算指标...',
      0,
      indicatorTotal <= 0 ? 1 : indicatorTotal,
    );
    final breakoutStopwatch = Stopwatch()..start();
    try {
      await _detectBreakouts(
        targetStockCodes: normalizedIndicatorTargets,
        onProgress: (current, total) {
          final safeTotal = total <= 0
              ? (indicatorTotal <= 0 ? 1 : indicatorTotal)
              : total;
          final safeCurrent = current.clamp(0, safeTotal);
          onProgress?.call('3/4 计算指标...', safeCurrent, safeTotal);
        },
      );
    } catch (error, stackTrace) {
      debugPrint('[DailySync] detectBreakouts failed: $error');
      if (kDebugMode) {
        debugPrint('$stackTrace');
      }
      rethrow;
    } finally {
      breakoutStopwatch.stop();
    }
    if (kDebugMode) {
      debugPrint(
        '[DailySync] detectBreakouts done ms=${breakoutStopwatch.elapsedMilliseconds}',
      );
    }

    final prewarmStopwatch = Stopwatch()..start();
    try {
      await _prewarmDailyIndicatorsConcurrently(
        stockCodes: normalizedIndicatorTargets,
        onProgress: (current, total) {
          final fallbackTotal = indicatorTotal <= 0 ? 1 : indicatorTotal;
          final safeTotal = total <= 0 ? fallbackTotal : total;
          final safeCurrent = current.clamp(0, safeTotal);
          onProgress?.call('3/4 计算指标...', safeCurrent, safeTotal);
        },
      );
    } catch (error, stackTrace) {
      debugPrint('[DailySync] prewarm indicators failed: $error');
      if (kDebugMode) {
        debugPrint('$stackTrace');
      }
      rethrow;
    } finally {
      prewarmStopwatch.stop();
    }
    if (kDebugMode) {
      debugPrint(
        '[DailySync] prewarm indicators done ms=${prewarmStopwatch.elapsedMilliseconds}',
      );
    }
    stageStopwatch.stop();
    final indicatorsMs = stageStopwatch.elapsedMilliseconds;

    resetStageTimer();
    onProgress?.call('4/4 保存缓存元数据...', 0, 1);
    await _saveCacheMetadataOnly();
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

    final now = _nowProvider();
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

    // 非交易日（周末/节假日）：允许复用最近一个交易日缓存。
    if (!_tradingCalendarService.isTradingDay(today)) {
      final latestTradingDay = _tradingCalendarService
          .latestTradingDayOnOrBefore(today);
      if (latestTradingDay != null && dataDate == latestTradingDay) {
        return true;
      }

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

  Future<void> _loadCachedTradingCalendarBestEffort() async {
    try {
      await _tradingCalendarService.loadCachedCalendar();
    } catch (e) {
      debugPrint('Failed to load cached trading calendar: $e');
    }
  }

  Future<void> _refreshRemoteTradingCalendarBestEffort() async {
    try {
      await _tradingCalendarService.refreshRemoteCalendar().timeout(
        _calendarRemoteRefreshTimeout,
      );
    } catch (e) {
      debugPrint('Failed to refresh remote trading calendar: $e');
    }
  }

  /// 检测高质量回踩（只读日K文件缓存，不触发网络）
  Future<void> _detectPullbacks() async {
    if (_pullbackService == null || _allData.isEmpty) return;

    final stocks = _allData.map((item) => item.stock).toList(growable: false);
    final stockCodeSet = stocks.map((stock) => stock.code).toSet();
    _dailyBarsCache.removeWhere((code, _) => !stockCodeSet.contains(code));

    await _reloadDailyBarsOrThrow(
      stockCodes: stocks.map((item) => item.code).toList(growable: false),
      anchorDate: _dataDate ?? DateTime.now(),
      targetBars: _dailyCacheTargetBars,
    );

    _applyPullbackDetection();
    await _applyPowerSystemUpDetection();
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
    Set<String>? stockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_macdService == null || _dailyBarsCache.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[DailyPrewarm][MACD] skip: service=${_macdService != null} '
          'cacheSize=${_dailyBarsCache.length}',
        );
      }
      return;
    }

    final payload = <String, List<KLine>>{};
    for (final entry in _dailyBarsCache.entries) {
      if (stockCodes != null && !stockCodes.contains(entry.key)) {
        continue;
      }
      if (entry.value.isNotEmpty) {
        payload[entry.key] = entry.value;
      }
    }
    if (payload.isEmpty) {
      if (kDebugMode) {
        debugPrint('[DailyPrewarm][MACD] payload empty');
      }
      return;
    }
    if (kDebugMode) {
      final barsCount = payload.values.fold<int>(
        0,
        (sum, bars) => sum + bars.length,
      );
      debugPrint(
        '[DailyPrewarm][MACD] payload entries=${payload.length} bars=$barsCount',
      );
    }

    await _macdService!.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
      onProgress: onProgress,
    );
  }

  Future<void> _prewarmDailyAdx({
    Set<String>? stockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_adxService == null || _dailyBarsCache.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[DailyPrewarm][ADX] skip: service=${_adxService != null} '
          'cacheSize=${_dailyBarsCache.length}',
        );
      }
      return;
    }

    final payload = <String, List<KLine>>{};
    for (final entry in _dailyBarsCache.entries) {
      if (stockCodes != null && !stockCodes.contains(entry.key)) {
        continue;
      }
      if (entry.value.isNotEmpty) {
        payload[entry.key] = entry.value;
      }
    }
    if (payload.isEmpty) {
      if (kDebugMode) {
        debugPrint('[DailyPrewarm][ADX] payload empty');
      }
      return;
    }
    if (kDebugMode) {
      final barsCount = payload.values.fold<int>(
        0,
        (sum, bars) => sum + bars.length,
      );
      debugPrint(
        '[DailyPrewarm][ADX] payload entries=${payload.length} bars=$barsCount',
      );
    }

    await _adxService!.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
      onProgress: onProgress,
    );
  }

  Future<void> _prewarmDailyEma({
    Set<String>? stockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_emaService == null || _dailyBarsCache.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[DailyPrewarm][EMA] skip: service=${_emaService != null} '
          'cacheSize=${_dailyBarsCache.length}',
        );
      }
      return;
    }

    final payload = <String, List<KLine>>{};
    for (final entry in _dailyBarsCache.entries) {
      if (stockCodes != null && !stockCodes.contains(entry.key)) {
        continue;
      }
      if (entry.value.isNotEmpty) {
        payload[entry.key] = entry.value;
      }
    }
    if (payload.isEmpty) {
      if (kDebugMode) {
        debugPrint('[DailyPrewarm][EMA] payload empty');
      }
      return;
    }
    if (kDebugMode) {
      final barsCount = payload.values.fold<int>(
        0,
        (sum, bars) => sum + bars.length,
      );
      debugPrint(
        '[DailyPrewarm][EMA] payload entries=${payload.length} bars=$barsCount',
      );
    }

    await _emaService!.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
      onProgress: onProgress,
    );
  }

  Future<void> _prewarmDailyPowerSystem({
    Set<String>? stockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_powerSystemService == null || _dailyBarsCache.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[DailyPrewarm][PowerSystem] skip: service=${_powerSystemService != null} '
          'cacheSize=${_dailyBarsCache.length}',
        );
      }
      return;
    }

    final payload = <String, List<KLine>>{};
    for (final entry in _dailyBarsCache.entries) {
      if (stockCodes != null && !stockCodes.contains(entry.key)) {
        continue;
      }
      if (entry.value.isNotEmpty) {
        payload[entry.key] = entry.value;
      }
    }
    if (payload.isEmpty) {
      if (kDebugMode) {
        debugPrint('[DailyPrewarm][PowerSystem] payload empty');
      }
      return;
    }

    await _powerSystemService!.prewarmFromBars(
      dataType: KLineDataType.daily,
      barsByStockCode: payload,
      onProgress: onProgress,
    );
  }

  Future<void> _prewarmDailyIndicatorsConcurrently({
    Set<String>? stockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    final hasMacd = _macdService != null && _dailyBarsCache.isNotEmpty;
    final hasAdx = _adxService != null && _dailyBarsCache.isNotEmpty;
    final hasEma = _emaService != null && _dailyBarsCache.isNotEmpty;
    final hasPowerSystem =
        _powerSystemService != null && _dailyBarsCache.isNotEmpty;
    if (kDebugMode) {
      debugPrint(
        '[DailyPrewarm] start '
        'hasMacd=$hasMacd hasAdx=$hasAdx hasEma=$hasEma hasPowerSystem=$hasPowerSystem '
        'cacheSize=${_dailyBarsCache.length} '
        'stockCodes=${stockCodes?.length ?? 0}',
      );
    }
    if (!hasMacd && !hasAdx && !hasEma && !hasPowerSystem) {
      if (kDebugMode) {
        debugPrint('[DailyPrewarm] skip: no indicators available');
      }
      return;
    }

    var macdCurrent = 0;
    var macdTotal = 0;
    var adxCurrent = 0;
    var adxTotal = 0;
    var emaCurrent = 0;
    var emaTotal = 0;
    var powerCurrent = 0;
    var powerTotal = 0;

    void emitProgress() {
      final safeMacdTotal = hasMacd ? (macdTotal <= 0 ? 1 : macdTotal) : 0;
      final safeAdxTotal = hasAdx ? (adxTotal <= 0 ? 1 : adxTotal) : 0;
      final safeEmaTotal = hasEma ? (emaTotal <= 0 ? 1 : emaTotal) : 0;
      final safePowerTotal = hasPowerSystem
          ? (powerTotal <= 0 ? 1 : powerTotal)
          : 0;
      final total =
          safeMacdTotal + safeAdxTotal + safeEmaTotal + safePowerTotal;
      if (total <= 0) {
        onProgress?.call(1, 1);
        return;
      }
      final current =
          macdCurrent.clamp(0, safeMacdTotal) +
          adxCurrent.clamp(0, safeAdxTotal) +
          emaCurrent.clamp(0, safeEmaTotal) +
          powerCurrent.clamp(0, safePowerTotal);
      onProgress?.call(current.clamp(0, total), total);
    }

    final jobs = <Future<void>>[];
    if (hasMacd) {
      jobs.add(
        _prewarmDailyMacd(
          stockCodes: stockCodes,
          onProgress: (current, total) {
            macdCurrent = current;
            macdTotal = total;
            emitProgress();
          },
        ),
      );
    }
    if (hasAdx) {
      jobs.add(
        _prewarmDailyAdx(
          stockCodes: stockCodes,
          onProgress: (current, total) {
            adxCurrent = current;
            adxTotal = total;
            emitProgress();
          },
        ),
      );
    }
    if (hasEma) {
      jobs.add(
        _prewarmDailyEma(
          stockCodes: stockCodes,
          onProgress: (current, total) {
            emaCurrent = current;
            emaTotal = total;
            emitProgress();
          },
        ),
      );
    }
    if (hasPowerSystem) {
      jobs.add(
        _prewarmDailyPowerSystem(
          stockCodes: stockCodes,
          onProgress: (current, total) {
            powerCurrent = current;
            powerTotal = total;
            emitProgress();
          },
        ),
      );
    }

    emitProgress();
    await Future.wait(jobs);
    emitProgress();
    if (kDebugMode) {
      debugPrint('[DailyPrewarm] done');
    }
  }

  Future<void> _restoreDailyBarsFromFile(
    List<String> stockCodes, {
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    if (stockCodes.isEmpty) return;

    try {
      final loaded = await _dailyKlineReadService.readOrThrow(
        stockCodes: stockCodes,
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

  Future<DailyKlineReadReport> _reloadDailyBarsWithReport({
    required List<String> stockCodes,
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    if (stockCodes.isEmpty) {
      _dailyBarsCache.clear();
      final report = const DailyKlineReadReport(
        totalStocks: 0,
        missingStockCodes: <String>[],
        corruptedStockCodes: <String>[],
        insufficientStockCodes: <String>[],
      );
      _lastDailySyncReadReport = report;
      return report;
    }

    final result = await _dailyKlineReadService.readWithReport(
      stockCodes: stockCodes,
      anchorDate: DateTime(anchorDate.year, anchorDate.month, anchorDate.day),
      targetBars: targetBars,
    );
    _dailyBarsCache = result.barsByStockCode;
    _lastDailySyncReadReport = result.report;
    await _refreshDailyBarsDiskStats();
    notifyListeners();
    return result.report;
  }

  Future<void> _reloadDailyBarsOrThrow({
    required List<String> stockCodes,
    required DateTime anchorDate,
    required int targetBars,
  }) async {
    if (stockCodes.isEmpty) {
      _dailyBarsCache.clear();
      return;
    }

    final loaded = await _dailyKlineReadService.readOrThrow(
      stockCodes: stockCodes,
      anchorDate: DateTime(anchorDate.year, anchorDate.month, anchorDate.day),
      targetBars: targetBars,
    );
    _dailyBarsCache = loaded;
    await _refreshDailyBarsDiskStats();
    notifyListeners();
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

  /// 重新计算动力系统双涨标记
  Future<void> recalculatePowerSystemUp({
    void Function(int current, int total)? onProgress,
  }) async {
    await _applyPowerSystemUpDetection(onProgress: onProgress);
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

  /// 应用动力系统双涨检测
  /// 检测日K和周K的最后状态都是上涨(state=1)的股票
  Future<void> _applyPowerSystemUpDetection({
    void Function(int current, int total)? onProgress,
  }) async {
    if (_powerSystemCacheStore == null || _allData.isEmpty) {
      return;
    }

    final updatedData = List<StockMonitorData>.from(_allData, growable: false);
    final total = updatedData.length;
    var completed = 0;

    for (var i = 0; i < total; i++) {
      final data = updatedData[i];
      final stockCode = data.stock.code;

      final dailyFuture = _powerSystemCacheStore!.loadSeries(
        stockCode: stockCode,
        dataType: KLineDataType.daily,
      );
      final weeklyFuture = _powerSystemCacheStore!.loadSeries(
        stockCode: stockCode,
        dataType: KLineDataType.weekly,
      );

      final results = await Future.wait<PowerSystemCacheSeries?>([
        dailyFuture,
        weeklyFuture,
      ]);
      final dailySeries = results[0];
      final weeklySeries = results[1];

      var isPowerSystemUp = false;
      if (dailySeries != null && dailySeries.points.isNotEmpty) {
        if (weeklySeries != null && weeklySeries.points.isNotEmpty) {
          final dailyLastState = dailySeries.points.last.state;
          final weeklyLastState = weeklySeries.points.last.state;
          isPowerSystemUp = (dailyLastState == 1) && (weeklyLastState == 1);
        }
      }

      updatedData[i] = data.copyWith(isPowerSystemUp: isPowerSystemUp);
      completed++;
      onProgress?.call(completed, total);
    }

    _allData = updatedData;
    notifyListeners();
  }

  /// 检测突破回踩
  Future<void> _detectBreakouts({
    Set<String>? targetStockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_breakoutService == null ||
        _allData.isEmpty ||
        _dailyBarsCache.isEmpty) {
      return;
    }
    await _applyBreakoutDetection(
      targetStockCodes: targetStockCodes,
      onProgress: onProgress,
    );
  }

  /// 重算突破回踩（使用缓存的日K数据，不重新下载）
  /// 返回 null 表示成功，否则返回缺失数据的描述
  /// [onProgress] 进度回调，参数为 (当前进度, 总数)
  Future<String?> recalculateBreakouts({
    Set<String>? targetStockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_breakoutService == null) {
      return '突破服务未初始化';
    }
    if (_allData.isEmpty) {
      return '缺失分钟数据，请先刷新';
    }
    try {
      await _reloadDailyBarsOrThrow(
        stockCodes: _allData
            .map((item) => item.stock.code)
            .toList(growable: false),
        anchorDate: _dataDate ?? DateTime.now(),
        targetBars: _dailyCacheTargetBars,
      );
    } on DailyKlineReadException catch (error) {
      return '日K读取失败: ${error.message}';
    }
    await _applyBreakoutDetection(
      targetStockCodes: targetStockCodes,
      onProgress: onProgress,
    );
    return null;
  }

  /// 应用突破回踩检测逻辑
  /// [onProgress] 进度回调，参数为 (当前进度, 总数)
  Future<void> _applyBreakoutDetection({
    Set<String>? targetStockCodes,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_breakoutService == null) return;

    final selectedIndexes = <int>[];
    if (targetStockCodes == null) {
      for (var index = 0; index < _allData.length; index++) {
        selectedIndexes.add(index);
      }
    } else {
      for (var index = 0; index < _allData.length; index++) {
        if (targetStockCodes.contains(_allData[index].stock.code)) {
          selectedIndexes.add(index);
        }
      }
    }

    final total = selectedIndexes.length;
    if (total <= 0) return;

    final updatedData = List<StockMonitorData>.from(_allData, growable: false);
    var nextIndex = 0;
    var completed = 0;
    final workerCount = math.min(_breakoutDetectMaxConcurrency, total);
    if (kDebugMode) {
      debugPrint(
        '[Breakout] start total=$total workers=$workerCount '
        'targetCodes=${targetStockCodes?.length ?? 0}',
      );
    }

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        if (index >= total) {
          return;
        }
        nextIndex++;

        final dataIndex = selectedIndexes[index];
        final data = _allData[dataIndex];
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

        updatedData[dataIndex] = data.copyWith(
          isPullback: data.isPullback,
          isBreakout: isBreakout,
        );
        completed++;
        onProgress?.call(completed, total);
        if (kDebugMode && completed % 200 == 0) {
          debugPrint('[Breakout] progress $completed/$total');
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => runWorker()),
    );

    _allData = updatedData;
    notifyListeners();
    if (kDebugMode) {
      debugPrint('[Breakout] done completed=$completed');
    }
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
    _allData = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_minuteDataCacheKey);
    await prefs.remove(_minuteDataDateKey);
    await prefs.remove(_marketDataCacheKey);
    try {
      await _marketSnapshotStore.clear();
    } catch (e) {
      debugPrint('Failed to clear minute snapshot file cache: $e');
    }
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
