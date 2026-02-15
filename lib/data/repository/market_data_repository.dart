import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/data_status.dart';
import '../models/data_updated_event.dart';
import '../models/data_freshness.dart';
import '../models/kline_data_type.dart';
import '../models/date_range.dart';
import '../models/fetch_result.dart';
import '../models/day_data_status.dart';
import '../storage/kline_metadata_manager.dart';
import '../storage/date_check_storage.dart';
import '../storage/minute_sync_state_storage.dart';
import '../../config/minute_sync_config.dart';
import '../../models/kline.dart';
import '../../models/quote.dart';
import '../../services/tdx_client.dart';
import 'data_repository.dart';
import 'kline_fetch_adapter.dart';
import 'minute_fetch_adapter.dart';
import 'minute_sync_planner.dart';
import 'minute_sync_writer.dart';

/// 市场数据仓库 - DataRepository 的具体实现
class MarketDataRepository implements DataRepository {
  final KLineMetadataManager _metadataManager;
  final TdxClient _tdxClient;
  final DateCheckStorage _dateCheckStorage;
  late final MinuteSyncStateStorage _minuteSyncStateStorage;
  late final MinuteFetchAdapter _minuteFetchAdapter;
  late final KlineFetchAdapter? _klineFetchAdapter;
  late final MinuteSyncPlanner _minuteSyncPlanner;
  late final MinuteSyncWriter _minuteSyncWriter;
  late final MinuteSyncConfig _minuteSyncConfig;
  late int _runtimeMinuteWriteConcurrency;
  final DateTime Function() _nowProvider;
  final StreamController<DataStatus> _statusController =
      StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _dataUpdatedController =
      StreamController<DataUpdatedEvent>.broadcast();

  // 内存缓存：Map<cacheKey, List<KLine>>
  // cacheKey = "${stockCode}_${dataType}_${startDate}_${endDate}"
  final Map<String, List<KLine>> _klineCache = {};

  // 最大缓存大小
  static const int _maxCacheSize = 100;

  // 完整分钟数据的最小K线数量（一个交易日约240根1分钟K线）
  static const int _minCompleteBars = 220;
  static const int _expectedMinuteBarsPerTradingDay = 240;
  static const double _minTradingDateCoverageRatio = 0.3;
  static const Duration _weeklyFreshnessTolerance = Duration(days: 7);
  static const String _precheckProgressStock = '__PRECHECK__';

  MarketDataRepository({
    KLineMetadataManager? metadataManager,
    TdxClient? tdxClient,
    DateCheckStorage? dateCheckStorage,
    MinuteSyncStateStorage? minuteSyncStateStorage,
    MinuteFetchAdapter? minuteFetchAdapter,
    KlineFetchAdapter? klineFetchAdapter,
    MinuteSyncPlanner? minuteSyncPlanner,
    MinuteSyncWriter? minuteSyncWriter,
    MinuteSyncConfig? minuteSyncConfig,
    DateTime Function()? nowProvider,
  }) : _metadataManager = metadataManager ?? KLineMetadataManager(),
       _tdxClient = tdxClient ?? TdxClient(),
       _dateCheckStorage = dateCheckStorage ?? DateCheckStorage(),
       _nowProvider = nowProvider ?? DateTime.now {
    final resolvedMinuteFetchAdapter =
        minuteFetchAdapter ?? _LegacyMinuteFetchAdapter(client: _tdxClient);
    _minuteSyncStateStorage =
        minuteSyncStateStorage ?? MinuteSyncStateStorage();
    _minuteFetchAdapter = resolvedMinuteFetchAdapter;
    _klineFetchAdapter =
        klineFetchAdapter ??
        (resolvedMinuteFetchAdapter is KlineFetchAdapter
            ? resolvedMinuteFetchAdapter as KlineFetchAdapter
            : null);
    _minuteSyncPlanner = minuteSyncPlanner ?? MinuteSyncPlanner();
    _minuteSyncConfig = minuteSyncConfig ?? const MinuteSyncConfig();
    _runtimeMinuteWriteConcurrency = _minuteSyncConfig.minuteWriteConcurrency;
    _minuteSyncWriter =
        minuteSyncWriter ??
        MinuteSyncWriter(
          metadataManager: _metadataManager,
          syncStateStorage: _minuteSyncStateStorage,
          maxConcurrentWrites: _runtimeMinuteWriteConcurrency,
        );

    // 初始状态：就绪
    _statusController.add(const DataReady(0));
  }

  int get minuteWriteConcurrency => _runtimeMinuteWriteConcurrency;

  void setMinuteWriteConcurrency(int value) {
    _runtimeMinuteWriteConcurrency = value < 1 ? 1 : value;
    _minuteSyncWriter.setMaxConcurrentWrites(_runtimeMinuteWriteConcurrency);
  }

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream =>
      _dataUpdatedController.stream;

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final result = <String, List<KLine>>{};

    for (final stockCode in stockCodes) {
      // 构建缓存key
      final cacheKey = _buildCacheKey(stockCode, dateRange, dataType);

      // 检查缓存
      if (_klineCache.containsKey(cacheKey)) {
        result[stockCode] = _klineCache[cacheKey]!;
        continue;
      }

      // 从存储加载
      try {
        final klines = await _metadataManager.loadKlineData(
          stockCode: stockCode,
          dataType: dataType,
          dateRange: dateRange,
        );

        // 存入缓存（带LRU驱逐）
        if (_klineCache.length >= _maxCacheSize &&
            !_klineCache.containsKey(cacheKey)) {
          // 移除最旧的缓存条目（第一个）
          final firstKey = _klineCache.keys.first;
          _klineCache.remove(firstKey);
        }
        _klineCache[cacheKey] = klines;
        result[stockCode] = klines;
      } catch (e, stackTrace) {
        // Log the error for debugging
        debugPrint('Failed to load K-line data for $stockCode: $e');
        if (kDebugMode) {
          debugPrint('Stack trace: $stackTrace');
        }

        // 加载失败，返回空列表
        result[stockCode] = [];
      }
    }

    return result;
  }

  String _buildCacheKey(
    String stockCode,
    DateRange dateRange,
    KLineDataType dataType,
  ) {
    final startMs = dateRange.start.millisecondsSinceEpoch;
    final endMs = dateRange.end.millisecondsSinceEpoch;
    return '${stockCode}_${dataType.name}_${startMs}_$endMs';
  }

  /// 清除缓存中与指定股票和数据类型相关的条目
  void _invalidateCache(String stockCode, KLineDataType dataType) {
    _klineCache.removeWhere((key, _) {
      return key.startsWith('${stockCode}_${dataType.name}_');
    });
  }

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    final result = <String, DataFreshness>{};

    for (final stockCode in stockCodes) {
      final now = _nowProvider();
      final today = DateTime(now.year, now.month, now.day);

      // 1. Check for pending dates (excluding today)
      final pendingDates = await _dateCheckStorage.getPendingDates(
        stockCode: stockCode,
        dataType: dataType,
        excludeToday: true,
        today: today,
      );

      if (pendingDates.isNotEmpty) {
        // Has incomplete historical dates -> Stale
        result[stockCode] = Stale(
          missingRange: DateRange(pendingDates.first, pendingDates.last),
        );
        continue;
      }

      // 2. Check latest checked date
      final latestCheckedDate = await _dateCheckStorage.getLatestCheckedDate(
        stockCode: stockCode,
        dataType: dataType,
      );

      if (latestCheckedDate == null) {
        // Never checked -> Missing
        result[stockCode] = const Missing();
        continue;
      }

      // 3. Prefer trading-day-aware freshness (exclude today in-progress).
      final latestCheckedDay = DateTime(
        latestCheckedDate.year,
        latestCheckedDate.month,
        latestCheckedDate.day,
      );

      final uncheckedStart = latestCheckedDay.add(const Duration(days: 1));
      final uncheckedEndDay = today.subtract(const Duration(days: 1));
      final uncheckedEnd = DateTime(
        uncheckedEndDay.year,
        uncheckedEndDay.month,
        uncheckedEndDay.day,
        23,
        59,
        59,
        999,
        999,
      );

      if (uncheckedStart.isAfter(uncheckedEnd)) {
        result[stockCode] = const Fresh();
        continue;
      }

      if (_isWeekendOnlyRange(uncheckedStart, uncheckedEndDay)) {
        result[stockCode] = const Fresh();
        continue;
      }

      final uncheckedRange = DateRange(uncheckedStart, uncheckedEnd);
      final uncheckedTradingDates = await getTradingDates(uncheckedRange);

      if (uncheckedTradingDates.isEmpty) {
        final hasReliableTradingContext = await _hasReliableTradingContext(
          uncheckedStartDay: uncheckedStart,
          uncheckedEndDay: uncheckedEndDay,
          today: today,
        );
        if (hasReliableTradingContext) {
          result[stockCode] = const Fresh();
          continue;
        }
      }

      if (_hasReliableTradingDateCoverage(
        uncheckedTradingDates,
        uncheckedRange,
      )) {
        if (uncheckedTradingDates.isNotEmpty) {
          result[stockCode] = Stale(
            missingRange: DateRange(
              uncheckedTradingDates.first,
              uncheckedTradingDates.last,
            ),
          );
        } else {
          result[stockCode] = const Fresh();
        }
        continue;
      }

      // 4. Fallback: if trading-date coverage is unreliable, keep conservative behavior.
      final daysSinceLastCheck = today.difference(latestCheckedDay).inDays;
      if (daysSinceLastCheck > 1) {
        result[stockCode] = Stale(missingRange: DateRange(uncheckedStart, now));
      } else {
        result[stockCode] = const Fresh();
      }
    }

    return result;
  }

  @override
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  }) async {
    if (stockCodes.isEmpty) {
      return {};
    }

    try {
      // 连接到 TDX 服务器
      if (!_tdxClient.isConnected) {
        final connected = await _tdxClient.autoConnect();
        if (!connected) {
          debugPrint('Failed to connect to TDX server');
          return {};
        }
      }

      // 映射股票代码到 (market, code) 元组
      // 6xx -> market 1 (沪市)
      // 0xx, 3xx -> market 0 (深市)
      final stockTuples = stockCodes.map((code) {
        final market = _mapCodeToMarket(code);
        return (market, code);
      }).toList();

      // 获取行情数据
      final quotes = await _tdxClient.getSecurityQuotes(stockTuples);

      // 转换为 Map<code, Quote>
      final result = <String, Quote>{};
      for (final quote in quotes) {
        result[quote.code] = quote;
      }

      // Log if response is partial (fewer quotes than requested)
      if (kDebugMode && result.length < stockCodes.length) {
        final missingCodes = stockCodes
            .where((code) => !result.containsKey(code))
            .toList();
        debugPrint(
          'Missing quotes for ${missingCodes.length} codes: $missingCodes',
        );
      }

      return result;
    } catch (e, stackTrace) {
      debugPrint('Failed to get quotes for ${stockCodes.length} stocks: $e');
      if (kDebugMode) {
        debugPrint('Requested codes: $stockCodes');
        debugPrint('Stack trace: $stackTrace');
      }
      return {};
    }
  }

  /// 根据股票代码映射市场
  /// 6xx -> market 1 (沪市)
  /// 0xx, 3xx -> market 0 (深市)
  int _mapCodeToMarket(String code) {
    if (code.isEmpty) return 0;
    final firstChar = code[0];
    if (firstChar == '6') {
      return 1; // 沪市
    }
    return 0; // 深市 (0xx, 3xx, 其他)
  }

  @override
  Future<int> getCurrentVersion() async {
    return await _metadataManager.getCurrentVersion();
  }

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    return _fetchDataInternal(
      stockCodes: stockCodes,
      dateRange: dateRange,
      dataType: dataType,
      onProgress: onProgress,
      skipPrecheck: false,
    );
  }

  /// 内部拉取方法，支持跳过预检查
  Future<FetchResult> _fetchDataInternal({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
    required bool skipPrecheck,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 处理空列表
    if (stockCodes.isEmpty) {
      return FetchResult(
        totalStocks: 0,
        successCount: 0,
        failureCount: 0,
        errors: {},
        totalRecords: 0,
        duration: stopwatch.elapsed,
      );
    }

    if (dataType == KLineDataType.oneMinute &&
        _minuteSyncConfig.enablePoolMinutePipeline) {
      try {
        return await _fetchMinuteDataWithPoolPipeline(
          stockCodes: stockCodes,
          dateRange: dateRange,
          onProgress: onProgress,
          stopwatch: stopwatch,
        );
      } catch (error, stackTrace) {
        debugPrint('minute pool pipeline failed: $error');
        if (kDebugMode) {
          debugPrint('minute pool pipeline stack: $stackTrace');
        }
        if (!_minuteSyncConfig.minutePipelineFallbackToLegacyOnError) {
          rethrow;
        }
      }
    }

    if (dataType == KLineDataType.daily && _klineFetchAdapter != null) {
      try {
        return await _fetchHigherTimeframeDataWithPoolPipeline(
          stockCodes: stockCodes,
          dateRange: dateRange,
          dataType: KLineDataType.daily,
          totalStocksForResult: stockCodes.length,
          skippedStocksCount: 0,
          onProgress: onProgress,
          stopwatch: stopwatch,
        );
      } catch (error, stackTrace) {
        debugPrint('daily pool pipeline failed: $error');
        if (kDebugMode) {
          debugPrint('daily pool pipeline stack: $stackTrace');
        }
      }
    }

    if (dataType == KLineDataType.weekly &&
        skipPrecheck &&
        _klineFetchAdapter != null) {
      try {
        return await _fetchHigherTimeframeDataWithPoolPipeline(
          stockCodes: stockCodes,
          dateRange: dateRange,
          dataType: KLineDataType.weekly,
          totalStocksForResult: stockCodes.length,
          skippedStocksCount: 0,
          onProgress: onProgress,
          stopwatch: stopwatch,
        );
      } catch (error, stackTrace) {
        debugPrint('weekly refetch pool pipeline failed: $error');
        if (kDebugMode) {
          debugPrint('weekly refetch pool pipeline stack: $stackTrace');
        }
      }
    }

    // ============ 预检查：过滤掉已完整的股票 ============
    final stocksNeedingFetch = <String>[];
    final skippedStocks = <String>[];

    if (!skipPrecheck && dataType == KLineDataType.oneMinute) {
      final tradingDates = await getTradingDates(dateRange);
      if (!_hasReliableTradingDateCoverage(tradingDates, dateRange)) {
        // 交易日样本为空或过稀时，不能预检查短路，否则会误判为“无需拉取”。
        stocksNeedingFetch.addAll(stockCodes);
        debugPrint(
          'fetchMissingData: trading dates unavailable/sparse, '
          'skip precheck and fetch all ${stockCodes.length} stocks',
        );
      } else {
        for (final stockCode in stockCodes) {
          final missingInfo = await _findMissingMinuteDatesInternal(
            stockCode: stockCode,
            dateRange: dateRange,
            verifyCachedComplete: true,
          );

          // datesToFetch = missingDates + incompleteDates
          final datesToFetch = [
            ...missingInfo.missingDates,
            ...missingInfo.incompleteDates,
          ];

          if (datesToFetch.isNotEmpty) {
            stocksNeedingFetch.add(stockCode);
          } else {
            skippedStocks.add(stockCode);
          }
        }

        debugPrint(
          'fetchMissingData: ${skippedStocks.length} stocks skipped (already complete), '
          '${stocksNeedingFetch.length} stocks need fetching',
        );
      }
    } else if (!skipPrecheck && dataType == KLineDataType.weekly) {
      final coverageRanges = await _metadataManager.getCoverageRanges(
        stockCodes: stockCodes,
        dataType: dataType,
      );

      for (var index = 0; index < stockCodes.length; index++) {
        final stockCode = stockCodes[index];
        final coverage = coverageRanges[stockCode];

        _statusController.add(
          DataFetching(
            current: index + 1,
            total: stockCodes.length,
            currentStock: _precheckProgressStock,
          ),
        );
        onProgress?.call(index + 1, stockCodes.length);

        final hasCoverage = _hasCoverageForDateRange(
          startDate: coverage?.startDate,
          endDate: coverage?.endDate,
          dateRange: dateRange,
          freshnessTolerance: _weeklyFreshnessTolerance,
        );

        if (hasCoverage) {
          skippedStocks.add(stockCode);
        } else {
          stocksNeedingFetch.add(stockCode);
        }
      }

      debugPrint(
        'fetchMissingData(weekly): ${skippedStocks.length} stocks skipped (covered), '
        '${stocksNeedingFetch.length} stocks need fetching',
      );

      if (stocksNeedingFetch.isNotEmpty && _klineFetchAdapter != null) {
        try {
          return await _fetchHigherTimeframeDataWithPoolPipeline(
            stockCodes: stocksNeedingFetch,
            dateRange: dateRange,
            dataType: dataType,
            totalStocksForResult: stockCodes.length,
            skippedStocksCount: skippedStocks.length,
            onProgress: onProgress,
            stopwatch: stopwatch,
          );
        } catch (error, stackTrace) {
          debugPrint('weekly pool pipeline failed: $error');
          if (kDebugMode) {
            debugPrint('weekly pool pipeline stack: $stackTrace');
          }
        }
      }

      if (stocksNeedingFetch.isEmpty) {
        stopwatch.stop();
        return FetchResult(
          totalStocks: stockCodes.length,
          successCount: stockCodes.length,
          failureCount: 0,
          errors: {},
          totalRecords: 0,
          duration: stopwatch.elapsed,
        );
      }
    } else {
      // 跳过预检查或日线数据 - 拉取所有股票
      stocksNeedingFetch.addAll(stockCodes);
    }

    // 如果所有股票都已完整，直接返回成功
    if (stocksNeedingFetch.isEmpty) {
      stopwatch.stop();
      return FetchResult(
        totalStocks: stockCodes.length,
        successCount: stockCodes.length,
        failureCount: 0,
        errors: {},
        totalRecords: 0,
        duration: stopwatch.elapsed,
      );
    }

    // ============ 预检查结束 ============

    final total = stocksNeedingFetch.length;

    // 发出 DataFetching 状态
    _statusController.add(
      DataFetching(
        current: 0,
        total: total,
        currentStock: stocksNeedingFetch.first,
      ),
    );

    // 连接到 TDX 服务器
    if (!_tdxClient.isConnected) {
      final connected = await _tdxClient.autoConnect();
      if (!connected) {
        debugPrint('fetchMissingData: 无法连接到 TDX 服务器');
        stopwatch.stop();

        // 需要拉取的股票都视为失败
        final errors = <String, String>{};
        for (final code in stocksNeedingFetch) {
          errors[code] = '无法连接到 TDX 服务器';
        }

        _statusController.add(
          DataReady(await _metadataManager.getCurrentVersion()),
        );

        return FetchResult(
          totalStocks: total,
          successCount: 0,
          failureCount: total,
          errors: errors,
          totalRecords: 0,
          duration: stopwatch.elapsed,
        );
      }
    }

    // 跟踪成功和失败
    var successCount = 0;
    var failureCount = 0;
    var totalRecords = 0;
    final errors = <String, String>{};
    final updatedStockCodes = <String>[];
    var completedCount = 0;

    // 并发控制：同时最多 10 个请求（滑动窗口模式）
    const maxConcurrent = 10;

    // 处理单只股票的函数
    Future<void> processStock(String stockCode) async {
      try {
        // 获取 K 线数据
        final klines = await _fetchKlinesForStock(
          stockCode: stockCode,
          dateRange: dateRange,
          dataType: dataType,
        );

        if (klines.isNotEmpty) {
          // 保存数据
          await _metadataManager.saveKlineData(
            stockCode: stockCode,
            newBars: klines,
            dataType: dataType,
          );

          // 清除缓存
          _invalidateCache(stockCode, dataType);

          // 分钟数据拉取成功后，立即刷新该范围的完整性缓存，
          // 避免旧的 missing/incomplete 缓存导致 checkFreshness 误报 stale。
          if (dataType == KLineDataType.oneMinute) {
            await findMissingMinuteDates(
              stockCode: stockCode,
              dateRange: dateRange,
            );
          }

          totalRecords += klines.length;
          updatedStockCodes.add(stockCode);
        }

        successCount++;
      } catch (e, stackTrace) {
        failureCount++;
        errors[stockCode] = e.toString();
        debugPrint('fetchMissingData: $stockCode 失败 - $e');
        if (kDebugMode) {
          debugPrint('Stack trace: $stackTrace');
        }
      }

      // 更新进度
      completedCount++;
      _statusController.add(
        DataFetching(
          current: completedCount,
          total: total,
          currentStock: stockCode,
        ),
      );
      onProgress?.call(completedCount, total);
    }

    // 滑动窗口并发：始终保持 maxConcurrent 个任务运行
    var activeCount = 0;
    var nextIndex = 0;
    final completer = Completer<void>();

    void startNext() {
      while (nextIndex < total && activeCount < maxConcurrent) {
        final index = nextIndex++;
        activeCount++;
        processStock(stocksNeedingFetch[index]).whenComplete(() {
          activeCount--;
          if (nextIndex < total) {
            startNext();
          } else if (activeCount == 0) {
            completer.complete();
          }
        });
      }
    }

    startNext();
    if (total > 0) {
      await completer.future;
    }

    stopwatch.stop();

    // 获取当前版本号
    final currentVersion = await _metadataManager.getCurrentVersion();

    // 发出数据更新事件（仅当有成功更新时）
    if (updatedStockCodes.isNotEmpty) {
      _dataUpdatedController.add(
        DataUpdatedEvent(
          stockCodes: updatedStockCodes,
          dateRange: dateRange,
          dataType: dataType,
          dataVersion: currentVersion,
        ),
      );
    }

    // 发出 DataReady 状态
    _statusController.add(DataReady(currentVersion));

    // 跳过的股票视为成功（已完整）
    final totalSuccessCount = successCount + skippedStocks.length;

    return FetchResult(
      totalStocks: stockCodes.length,
      successCount: totalSuccessCount,
      failureCount: failureCount,
      errors: errors,
      totalRecords: totalRecords,
      duration: stopwatch.elapsed,
    );
  }

  Future<FetchResult> _fetchMinuteDataWithPoolPipeline({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
    required Stopwatch stopwatch,
  }) async {
    final now = _nowProvider();
    final today = DateTime(now.year, now.month, now.day);

    final tradingDates = await getTradingDates(dateRange);
    var planningTradingDates =
        tradingDates
            .map((day) => DateTime(day.year, day.month, day.day))
            .toSet()
            .toList()
          ..sort();

    if (planningTradingDates.isEmpty) {
      planningTradingDates = _buildFallbackTradingDatesForMinutePlan(
        dateRange: dateRange,
        today: today,
      );
    }

    if (_minuteSyncConfig.enableMinutePipelineLogs) {
      debugPrint(
        '[MinutePipeline] start stocks=${stockCodes.length} '
        'tradingDays=${tradingDates.length} planningDays=${planningTradingDates.length}',
      );
    }

    if (planningTradingDates.isEmpty) {
      stopwatch.stop();
      final currentVersion = await _metadataManager.getCurrentVersion();
      _statusController.add(DataReady(currentVersion));
      return FetchResult(
        totalStocks: stockCodes.length,
        successCount: stockCodes.length,
        failureCount: 0,
        errors: const {},
        totalRecords: 0,
        duration: stopwatch.elapsed,
      );
    }

    final planningStopwatch = Stopwatch()..start();

    final syncStateByCode = await _minuteSyncStateStorage.getBatchByStockCodes(
      stockCodes,
    );
    final pendingDatesByCode = await _dateCheckStorage.getPendingDatesBatch(
      stockCodes: stockCodes,
      dataType: KLineDataType.oneMinute,
      fromDate: planningTradingDates.first,
      toDate: planningTradingDates.last,
      excludeToday: true,
      today: today,
    );

    final plans = <MinuteFetchPlan>[];
    for (final stockCode in stockCodes) {
      final plan = _minuteSyncPlanner.planForStock(
        stockCode: stockCode,
        tradingDates: planningTradingDates,
        syncState: syncStateByCode[stockCode],
        knownMissingDates: pendingDatesByCode[stockCode] ?? const [],
        knownIncompleteDates: const [],
      );
      plans.add(plan);
    }

    final plansNeedingFetch = plans
        .where((plan) => plan.datesToFetch.isNotEmpty)
        .toList();

    planningStopwatch.stop();

    if (_minuteSyncConfig.enableMinutePipelineLogs) {
      debugPrint(
        '[MinutePipeline] planned=${plans.length} fetch=${plansNeedingFetch.length} '
        'skip=${plans.length - plansNeedingFetch.length}',
      );
    }

    if (plansNeedingFetch.isEmpty) {
      stopwatch.stop();
      final currentVersion = await _metadataManager.getCurrentVersion();
      _statusController.add(DataReady(currentVersion));

      if (_minuteSyncConfig.enableMinutePipelineLogs) {
        final durationMs = stopwatch.elapsedMilliseconds;
        debugPrint(
          '[MinutePipeline][timing] '
          'planMs=${planningStopwatch.elapsedMilliseconds} '
          'fetchMs=0 writeMs=0 writePersistMs=0 writeVersionMs=0 '
          'writeConcurrency=${_minuteSyncWriter.maxConcurrentWrites} '
          'finalizeMs=0 totalMs=$durationMs',
        );
      }

      return FetchResult(
        totalStocks: stockCodes.length,
        successCount: stockCodes.length,
        failureCount: 0,
        errors: const {},
        totalRecords: 0,
        duration: stopwatch.elapsed,
      );
    }

    final stocksToFetch = plansNeedingFetch
        .map((plan) => plan.stockCode)
        .toList(growable: false);

    final requiredBatchesByStock = <String, int>{
      for (final plan in plansNeedingFetch)
        plan.stockCode: _calculateRequiredBatchCount(
          tradingDates: planningTradingDates,
          datesToFetch: plan.datesToFetch,
          batchSize: _minuteSyncConfig.poolBatchCount,
          maxBatches: _minuteSyncConfig.poolMaxBatches,
        ),
    };

    final totalFetchUnits = requiredBatchesByStock.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );

    _statusController.add(
      DataFetching(
        current: 0,
        total: totalFetchUnits,
        currentStock: stocksToFetch.first,
      ),
    );

    final barsByStock = <String, List<KLine>>{
      for (final code in stocksToFetch) code: <KLine>[],
    };

    final fetchStopwatch = Stopwatch()..start();
    var completedFetchUnits = 0;
    for (
      var batchIndex = 0;
      batchIndex < _minuteSyncConfig.poolMaxBatches;
      batchIndex++
    ) {
      final activeStocks = stocksToFetch
          .where((code) => (requiredBatchesByStock[code] ?? 0) > batchIndex)
          .toList(growable: false);

      if (activeStocks.isEmpty) {
        break;
      }

      final batchStart = batchIndex * _minuteSyncConfig.poolBatchCount;
      final batchBarsByStock = await _minuteFetchAdapter.fetchMinuteBars(
        stockCodes: activeStocks,
        start: batchStart,
        count: _minuteSyncConfig.poolBatchCount,
        onProgress: (current, total) {
          final safeTotal = total <= 0 ? activeStocks.length : total;
          final stockIndex = current <= 0
              ? 0
              : current - 1 < safeTotal
              ? current - 1
              : safeTotal - 1;

          final overallCurrent = completedFetchUnits + current;
          _statusController.add(
            DataFetching(
              current: overallCurrent,
              total: totalFetchUnits,
              currentStock: activeStocks[stockIndex],
            ),
          );
          onProgress?.call(overallCurrent, totalFetchUnits);
        },
      );

      var hasNonEmptyBars = false;
      for (final stockCode in activeStocks) {
        final bars = batchBarsByStock[stockCode] ?? const <KLine>[];
        if (bars.isNotEmpty) {
          hasNonEmptyBars = true;
          barsByStock[stockCode]!.addAll(bars);
        }
      }

      completedFetchUnits += activeStocks.length;

      if (_minuteSyncConfig.enableMinutePipelineLogs) {
        debugPrint(
          '[MinutePipeline] batch=$batchIndex start=$batchStart active=${activeStocks.length} '
          'hasData=$hasNonEmptyBars',
        );
      }

      if (!hasNonEmptyBars) {
        break;
      }
    }
    fetchStopwatch.stop();

    DateTime? latestPlannedTradingDay;
    for (final plan in plansNeedingFetch) {
      if (plan.datesToFetch.isEmpty) continue;
      final candidate = plan.datesToFetch.last;
      if (latestPlannedTradingDay == null ||
          candidate.isAfter(latestPlannedTradingDay)) {
        latestPlannedTradingDay = candidate;
      }
    }

    final writeTargetCount = barsByStock.values
        .where((bars) => bars.isNotEmpty)
        .length;
    if (writeTargetCount > 0) {
      _statusController.add(
        const DataFetching(current: 0, total: 1, currentStock: '__WRITE__'),
      );
    }

    final writeStopwatch = Stopwatch()..start();
    final writeResult = await _minuteSyncWriter.writeBatch(
      barsByStock: barsByStock,
      dataType: KLineDataType.oneMinute,
      fetchedTradingDay: latestPlannedTradingDay,
      onProgress: (current, total) {
        final safeTotal = total <= 0 ? writeTargetCount : total;
        final boundedCurrent = current.clamp(0, safeTotal);
        _statusController.add(
          DataFetching(
            current: boundedCurrent,
            total: safeTotal,
            currentStock: '__WRITE__',
          ),
        );
      },
    );
    writeStopwatch.stop();

    final finalizeStopwatch = Stopwatch()..start();
    for (final stockCode in writeResult.updatedStocks) {
      _invalidateCache(stockCode, KLineDataType.oneMinute);
    }

    stopwatch.stop();
    final currentVersion = await _metadataManager.getCurrentVersion();

    if (writeResult.updatedStocks.isNotEmpty) {
      _dataUpdatedController.add(
        DataUpdatedEvent(
          stockCodes: writeResult.updatedStocks,
          dateRange: dateRange,
          dataType: KLineDataType.oneMinute,
          dataVersion: currentVersion,
        ),
      );
    }

    _statusController.add(DataReady(currentVersion));
    finalizeStopwatch.stop();

    if (_minuteSyncConfig.enableMinutePipelineLogs) {
      final durationMs = stopwatch.elapsedMilliseconds;
      final perMinute = durationMs <= 0
          ? 0
          : (stocksToFetch.length * 60000 / durationMs).round();
      debugPrint(
        '[MinutePipeline] done fetched=${stocksToFetch.length} '
        'updated=${writeResult.updatedStocks.length} records=${writeResult.totalRecords} '
        'durationMs=$durationMs stocksPerMin=$perMinute',
      );
      debugPrint(
        '[MinutePipeline][timing] '
        'planMs=${planningStopwatch.elapsedMilliseconds} '
        'fetchMs=${fetchStopwatch.elapsedMilliseconds} '
        'writeMs=${writeStopwatch.elapsedMilliseconds} '
        'writePersistMs=${writeResult.persistDurationMs} '
        'writeVersionMs=${writeResult.versionDurationMs} '
        'writeTotalMs=${writeResult.totalDurationMs} '
        'writeConcurrency=${_minuteSyncWriter.maxConcurrentWrites} '
        'finalizeMs=${finalizeStopwatch.elapsedMilliseconds} '
        'totalMs=$durationMs',
      );
    }

    return FetchResult(
      totalStocks: stockCodes.length,
      successCount: stockCodes.length,
      failureCount: 0,
      errors: const {},
      totalRecords: writeResult.totalRecords,
      duration: stopwatch.elapsed,
    );
  }

  Future<FetchResult> _fetchHigherTimeframeDataWithPoolPipeline({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    required int totalStocksForResult,
    required int skippedStocksCount,
    ProgressCallback? onProgress,
    required Stopwatch stopwatch,
  }) async {
    if (stockCodes.isEmpty) {
      stopwatch.stop();
      final currentVersion = await _metadataManager.getCurrentVersion();
      _statusController.add(DataReady(currentVersion));
      return FetchResult(
        totalStocks: totalStocksForResult,
        successCount: skippedStocksCount,
        failureCount: 0,
        errors: const {},
        totalRecords: 0,
        duration: stopwatch.elapsed,
      );
    }

    final category = _mapDataTypeToCategory(dataType);
    final batchSize = _minuteSyncConfig.poolBatchCount;
    final maxBatches = _minuteSyncConfig.poolMaxBatches;

    _statusController.add(
      DataFetching(
        current: 0,
        total: stockCodes.length,
        currentStock: stockCodes.first,
      ),
    );

    final allBarsByStock = <String, List<KLine>>{
      for (final code in stockCodes) code: <KLine>[],
    };

    final completedByStock = <String, bool>{
      for (final code in stockCodes) code: false,
    };
    var completedStocks = 0;
    var fetchProgressCurrent = 0;

    for (var batchIndex = 0; batchIndex < maxBatches; batchIndex++) {
      final activeStocks = stockCodes
          .where((stockCode) => !(completedByStock[stockCode] ?? false))
          .toList(growable: false);

      if (activeStocks.isEmpty) {
        break;
      }

      final batchStart = batchIndex * batchSize;
      final barsByStock = await _klineFetchAdapter!.fetchBars(
        stockCodes: activeStocks,
        category: category,
        start: batchStart,
        count: batchSize,
        onProgress: (current, total) {
          final safeTotal = total <= 0 ? activeStocks.length : total;
          final boundedCurrent = current.clamp(0, safeTotal);
          final stockIndex = boundedCurrent <= 0
              ? 0
              : min(activeStocks.length - 1, boundedCurrent - 1);
          final overallCurrent = (completedStocks + boundedCurrent).clamp(
            0,
            stockCodes.length,
          );
          if (overallCurrent > fetchProgressCurrent) {
            fetchProgressCurrent = overallCurrent;
            _statusController.add(
              DataFetching(
                current: fetchProgressCurrent,
                total: stockCodes.length,
                currentStock: activeStocks[stockIndex],
              ),
            );
            onProgress?.call(fetchProgressCurrent, stockCodes.length);
          }
        },
      );

      for (final stockCode in activeStocks) {
        final batchBars = barsByStock[stockCode] ?? const <KLine>[];
        if (batchBars.isNotEmpty) {
          allBarsByStock[stockCode]!.addAll(batchBars);
        }

        final reachedRangeStart =
            batchBars.isNotEmpty &&
            batchBars.first.datetime.isBefore(dateRange.start);
        final noMoreData = batchBars.isEmpty || batchBars.length < batchSize;

        if (reachedRangeStart || noMoreData || batchIndex == maxBatches - 1) {
          if (!(completedByStock[stockCode] ?? false)) {
            completedByStock[stockCode] = true;
            completedStocks++;
            if (completedStocks > fetchProgressCurrent) {
              fetchProgressCurrent = completedStocks;
              _statusController.add(
                DataFetching(
                  current: fetchProgressCurrent,
                  total: stockCodes.length,
                  currentStock: stockCode,
                ),
              );
              onProgress?.call(fetchProgressCurrent, stockCodes.length);
            }
          }
        }
      }
    }

    final errors = <String, String>{};
    final updatedStockCodes = <String>[];
    var successCount = 0;
    var failureCount = 0;
    var totalRecords = 0;

    final writeTargetCount = stockCodes.length;
    _statusController.add(
      DataFetching(
        current: 0,
        total: writeTargetCount,
        currentStock: '__WRITE__',
      ),
    );

    final writeOutcomes = List<_HigherTimeframeWriteOutcome?>.filled(
      stockCodes.length,
      null,
    );
    final writeWorkerCount = min(
      _runtimeMinuteWriteConcurrency,
      stockCodes.length,
    );
    var nextWriteIndex = 0;
    var completedWrites = 0;

    Future<void> runWriteWorker() async {
      while (true) {
        final currentIndex = nextWriteIndex;
        if (currentIndex >= stockCodes.length) {
          return;
        }
        nextWriteIndex++;

        final stockCode = stockCodes[currentIndex];
        late _HigherTimeframeWriteOutcome outcome;

        try {
          final filteredBars =
              (allBarsByStock[stockCode] ?? const <KLine>[])
                  .where((bar) => dateRange.contains(bar.datetime))
                  .toList()
                ..sort((a, b) => a.datetime.compareTo(b.datetime));

          if (filteredBars.isNotEmpty) {
            await _metadataManager.saveKlineData(
              stockCode: stockCode,
              newBars: filteredBars,
              dataType: dataType,
              bumpVersion: false,
            );
            _invalidateCache(stockCode, dataType);
          }

          outcome = _HigherTimeframeWriteOutcome(
            stockCode: stockCode,
            success: true,
            updated: filteredBars.isNotEmpty,
            recordCount: filteredBars.length,
          );
        } catch (e, stackTrace) {
          debugPrint('${dataType.name} pool fetch: $stockCode failed - $e');
          if (kDebugMode) {
            debugPrint('Stack trace: $stackTrace');
          }
          outcome = _HigherTimeframeWriteOutcome(
            stockCode: stockCode,
            success: false,
            updated: false,
            recordCount: 0,
            error: e.toString(),
          );
        } finally {
          writeOutcomes[currentIndex] = outcome;
          completedWrites++;
          _statusController.add(
            DataFetching(
              current: completedWrites,
              total: writeTargetCount,
              currentStock: '__WRITE__',
            ),
          );
        }
      }
    }

    await Future.wait(
      List.generate(writeWorkerCount, (_) => runWriteWorker(), growable: false),
    );

    for (final outcome
        in writeOutcomes.whereType<_HigherTimeframeWriteOutcome>()) {
      if (outcome.success) {
        successCount++;
      } else {
        failureCount++;
        errors[outcome.stockCode] = outcome.error ?? 'unknown error';
      }

      if (outcome.updated) {
        updatedStockCodes.add(outcome.stockCode);
        totalRecords += outcome.recordCount;
      }
    }

    stopwatch.stop();

    if (updatedStockCodes.isNotEmpty) {
      await _metadataManager.incrementDataVersion(
        'Updated ${dataType.name} data for ${updatedStockCodes.length} stocks',
      );
    }
    final currentVersion = await _metadataManager.getCurrentVersion();

    if (updatedStockCodes.isNotEmpty) {
      _dataUpdatedController.add(
        DataUpdatedEvent(
          stockCodes: updatedStockCodes,
          dateRange: dateRange,
          dataType: dataType,
          dataVersion: currentVersion,
        ),
      );
    }

    _statusController.add(DataReady(currentVersion));

    return FetchResult(
      totalStocks: totalStocksForResult,
      successCount: successCount + skippedStocksCount,
      failureCount: failureCount,
      errors: errors,
      totalRecords: totalRecords,
      duration: stopwatch.elapsed,
    );
  }

  int _calculateRequiredBatchCount({
    required List<DateTime> tradingDates,
    required List<DateTime> datesToFetch,
    required int batchSize,
    required int maxBatches,
  }) {
    if (datesToFetch.isEmpty || batchSize <= 0) {
      return 0;
    }

    final normalizedTradingDates =
        tradingDates
            .map((day) => DateTime(day.year, day.month, day.day))
            .toSet()
            .toList()
          ..sort();

    if (normalizedTradingDates.isEmpty) {
      return 1;
    }

    final normalizedTargetDates =
        datesToFetch
            .map((day) => DateTime(day.year, day.month, day.day))
            .toSet()
            .toList()
          ..sort();

    final earliestTarget = normalizedTargetDates.first;
    final coveredTradingDays = normalizedTradingDates
        .where((day) => !day.isBefore(earliestTarget))
        .length;

    final daysToCover = coveredTradingDays <= 0 ? 1 : coveredTradingDays;
    final requiredBars = daysToCover * _expectedMinuteBarsPerTradingDay;
    final rawBatches = (requiredBars / batchSize).ceil();

    final safeMaxBatches = maxBatches <= 0 ? 1 : maxBatches;
    final bounded = rawBatches.clamp(1, safeMaxBatches);
    return bounded;
  }

  /// 从 TDX 获取单只股票的 K 线数据
  ///
  /// [stockCode] 股票代码
  /// [dateRange] 日期范围
  /// [dataType] 数据类型
  ///
  /// 分批获取数据，直到获取到 dateRange.start 之前的数据或达到批次上限
  Future<List<KLine>> _fetchKlinesForStock({
    required String stockCode,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final market = _mapCodeToMarket(stockCode);
    final category = _mapDataTypeToCategory(dataType);

    const batchSize = 800; // 每批数量
    const maxBatches = 10; // 最大批次数（安全限制）

    final allKlines = <KLine>[];
    var start = 0;

    for (var batch = 0; batch < maxBatches; batch++) {
      final klines = await _tdxClient.getSecurityBars(
        market: market,
        code: stockCode,
        category: category,
        start: start,
        count: batchSize,
      );

      if (klines.isEmpty) {
        if (batch == 0) {
          debugPrint(
            'Warning: First batch for $stockCode returned empty - may indicate data unavailability',
          );
        }
        break; // 没有更多数据
      }

      allKlines.addAll(klines);

      // 检查是否已获取到足够早的数据
      // K线数据按时间升序排列，第一条是最旧的
      final oldestBar = klines.first;
      if (oldestBar.datetime.isBefore(dateRange.start)) {
        break; // 已获取到范围起始日期之前的数据
      }

      // 移动到下一批
      start += batchSize;
    }

    // 过滤结果到 dateRange 内
    final filteredKlines = allKlines.where((kline) {
      return dateRange.contains(kline.datetime);
    }).toList();

    // 按时间排序
    filteredKlines.sort((a, b) => a.datetime.compareTo(b.datetime));

    return filteredKlines;
  }

  bool _hasCoverageForDateRange({
    required DateTime? startDate,
    required DateTime? endDate,
    required DateRange dateRange,
    Duration freshnessTolerance = Duration.zero,
  }) {
    if (startDate == null || endDate == null) {
      return false;
    }

    final requiredStart = DateTime(
      dateRange.start.year,
      dateRange.start.month,
      dateRange.start.day,
    );

    final rawRequiredEnd = DateTime(
      dateRange.end.year,
      dateRange.end.month,
      dateRange.end.day,
    ).subtract(freshnessTolerance);

    final requiredEnd = rawRequiredEnd.isBefore(requiredStart)
        ? requiredStart
        : rawRequiredEnd;

    final coveredStart = !startDate.isAfter(requiredStart);
    final coveredEnd = !endDate.isBefore(requiredEnd);
    return coveredStart && coveredEnd;
  }

  /// 映射数据类型到 TDX category
  /// oneMinute -> 7 (1分钟K线)
  /// daily -> 4 (日线)
  /// weekly -> 5 (周线)
  int _mapDataTypeToCategory(KLineDataType dataType) {
    switch (dataType) {
      case KLineDataType.oneMinute:
        return 7; // 1分钟K线
      case KLineDataType.daily:
        return 4; // 日线
      case KLineDataType.weekly:
        return 5; // 周线
    }
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    // refetchData 强制重新拉取，跳过预检查
    return await _fetchDataInternal(
      stockCodes: stockCodes,
      dateRange: dateRange,
      dataType: dataType,
      onProgress: onProgress,
      skipPrecheck: true,
    );
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
    KLineDataType? dataType,
  }) async {
    try {
      final targetDataTypes = dataType == null
          ? KLineDataType.values
          : [dataType];

      // 遍历目标数据类型
      for (final currentDataType in targetDataTypes) {
        // 查询该类型下所有股票代码
        final stockCodes = await _metadataManager.getAllStockCodes(
          dataType: currentDataType,
        );

        for (final stockCode in stockCodes) {
          await _metadataManager.deleteOldData(
            stockCode: stockCode,
            dataType: currentDataType,
            beforeDate: beforeDate,
          );

          // 清除缓存
          _invalidateCache(stockCode, currentDataType);
        }

        // 删除原始数据后，必须清除对应检测缓存，避免“已完整”脏缓存短路后续拉取。
        await _dateCheckStorage.clearCheckStatus(dataType: currentDataType);
      }

      // 更新状态
      final newVersion = await _metadataManager.getCurrentVersion();
      _statusController.add(DataReady(newVersion));
    } catch (e) {
      debugPrint('Failed to cleanup old data: $e');
      rethrow;
    }
  }

  // ============ 缺失数据检测 ============

  bool _hasReliableTradingDateCoverage(
    List<DateTime> tradingDates,
    DateRange dateRange,
  ) {
    if (tradingDates.isEmpty) return false;

    final startDate = DateTime(
      dateRange.start.year,
      dateRange.start.month,
      dateRange.start.day,
    );
    final endDate = DateTime(
      dateRange.end.year,
      dateRange.end.month,
      dateRange.end.day,
    );
    final calendarDays = endDate.difference(startDate).inDays + 1;

    // 短窗口下（<=5天）只要有交易日即可认为可靠，避免过度放宽为“全量拉取”。
    if (calendarDays <= 5) return true;

    final minExpectedTradingDates =
        (calendarDays * _minTradingDateCoverageRatio).ceil();
    return tradingDates.length >= minExpectedTradingDates;
  }

  bool _isWeekendOnlyRange(DateTime startDay, DateTime endDay) {
    if (startDay.isAfter(endDay)) return false;

    var cursor = DateTime(startDay.year, startDay.month, startDay.day);
    final normalizedEnd = DateTime(endDay.year, endDay.month, endDay.day);

    while (!cursor.isAfter(normalizedEnd)) {
      final weekday = cursor.weekday;
      if (weekday != DateTime.saturday && weekday != DateTime.sunday) {
        return false;
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    return true;
  }

  List<DateTime> _buildFallbackTradingDatesForMinutePlan({
    required DateRange dateRange,
    required DateTime today,
  }) {
    final startDay = DateTime(
      dateRange.start.year,
      dateRange.start.month,
      dateRange.start.day,
    );
    var endDay = DateTime(
      dateRange.end.year,
      dateRange.end.month,
      dateRange.end.day,
    );
    if (endDay.isAfter(today)) {
      endDay = today;
    }
    if (startDay.isAfter(endDay)) {
      return const [];
    }

    final candidatesInRange = _buildWeekdayDates(startDay, endDay);
    if (candidatesInRange.isNotEmpty) {
      return candidatesInRange;
    }

    final fallbackStart = endDay.subtract(const Duration(days: 7));
    return _buildWeekdayDates(fallbackStart, endDay);
  }

  List<DateTime> _buildWeekdayDates(DateTime startDay, DateTime endDay) {
    if (startDay.isAfter(endDay)) {
      return const [];
    }

    final days = <DateTime>[];
    var cursor = DateTime(startDay.year, startDay.month, startDay.day);
    final normalizedEnd = DateTime(endDay.year, endDay.month, endDay.day);

    while (!cursor.isAfter(normalizedEnd)) {
      if (cursor.weekday >= DateTime.monday &&
          cursor.weekday <= DateTime.friday) {
        days.add(cursor);
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  Future<bool> _hasReliableTradingContext({
    required DateTime uncheckedStartDay,
    required DateTime uncheckedEndDay,
    required DateTime today,
  }) async {
    final probeStartDay = uncheckedStartDay.subtract(const Duration(days: 15));

    final latestHistoricalDay = today.subtract(const Duration(days: 1));
    var probeEndDay = uncheckedEndDay.add(const Duration(days: 15));
    if (probeEndDay.isAfter(latestHistoricalDay)) {
      probeEndDay = latestHistoricalDay;
    }

    if (probeStartDay.isAfter(probeEndDay)) {
      return false;
    }

    final probeRange = DateRange(
      probeStartDay,
      DateTime(
        probeEndDay.year,
        probeEndDay.month,
        probeEndDay.day,
        23,
        59,
        59,
        999,
        999,
      ),
    );

    final probeTradingDates = await getTradingDates(probeRange);
    return _hasReliableTradingDateCoverage(probeTradingDates, probeRange);
  }

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  }) async {
    return _findMissingMinuteDatesInternal(
      stockCode: stockCode,
      dateRange: dateRange,
      verifyCachedComplete: false,
    );
  }

  Future<MissingDatesResult> _findMissingMinuteDatesInternal({
    required String stockCode,
    required DateRange dateRange,
    required bool verifyCachedComplete,
  }) async {
    // 1. Get trading dates from daily K-line data
    final tradingDates = await getTradingDates(dateRange);

    if (tradingDates.isEmpty) {
      return const MissingDatesResult(
        missingDates: [],
        incompleteDates: [],
        completeDates: [],
      );
    }

    // 统一归一化到日期粒度，避免时间部分导致哈希匹配问题。
    final normalizedTradingDates =
        tradingDates
            .map((date) => DateTime(date.year, date.month, date.day))
            .toSet()
            .toList()
          ..sort();

    final checkedStatus = await _dateCheckStorage.getCheckedStatus(
      stockCode: stockCode,
      dataType: KLineDataType.oneMinute,
      dates: normalizedTradingDates,
    );

    final now = _nowProvider();
    final todayDate = DateTime(now.year, now.month, now.day);

    // 2. Determine which dates need actual bar recount.
    final datesToCheck = <DateTime>[];
    final missingDates = <DateTime>[];
    final incompleteDates = <DateTime>[];
    final completeDates = <DateTime>[];

    for (final dateOnly in normalizedTradingDates) {
      final status = checkedStatus[dateOnly];

      if (!verifyCachedComplete && status == DayDataStatus.complete) {
        completeDates.add(dateOnly);
        continue;
      }

      datesToCheck.add(dateOnly);
    }

    // 3. Count bars only for dates that need verification.
    final barCountsByDate = <DateTime, int>{};
    if (datesToCheck.isNotEmpty) {
      if (verifyCachedComplete) {
        final firstDate = datesToCheck.first;
        final lastDate = datesToCheck.last;
        final checkRange = DateRange(
          firstDate,
          DateTime(
            lastDate.year,
            lastDate.month,
            lastDate.day,
            23,
            59,
            59,
            999,
            999,
          ),
        );

        final counted = await _metadataManager.countBarsByDateInRange(
          stockCode: stockCode,
          dataType: KLineDataType.oneMinute,
          dateRange: checkRange,
        );
        for (final date in datesToCheck) {
          barCountsByDate[date] = counted[date] ?? 0;
        }
      } else {
        for (final date in datesToCheck) {
          final barCount = await _metadataManager.countBarsForDate(
            stockCode: stockCode,
            dataType: KLineDataType.oneMinute,
            date: date,
          );
          barCountsByDate[date] = barCount;
        }
      }
    }

    // 4. Categorize recounted dates and update cache.
    for (final dateOnly in datesToCheck) {
      final barCount = barCountsByDate[dateOnly] ?? 0;
      final isToday = dateOnly == todayDate;

      DayDataStatus status;
      if (barCount == 0) {
        status = DayDataStatus.missing;
        missingDates.add(dateOnly);
      } else if (barCount >= _minCompleteBars) {
        status = DayDataStatus.complete;
        completeDates.add(dateOnly);
      } else if (isToday) {
        status = DayDataStatus.inProgress;
        // Don't add to any list, don't cache
      } else {
        status = DayDataStatus.incomplete;
        incompleteDates.add(dateOnly);
      }

      // 5. Save to cache (skip inProgress)
      if (status != DayDataStatus.inProgress) {
        await _dateCheckStorage.saveCheckStatus(
          stockCode: stockCode,
          dataType: KLineDataType.oneMinute,
          date: dateOnly,
          status: status,
          barCount: barCount,
        );
      }
    }

    completeDates.sort();
    missingDates.sort();
    incompleteDates.sort();

    return MissingDatesResult(
      missingDates: missingDates,
      incompleteDates: incompleteDates,
      completeDates: completeDates,
    );
  }

  @override
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) async {
    final result = <String, MissingDatesResult>{};
    var completed = 0;

    for (final stockCode in stockCodes) {
      result[stockCode] = await findMissingMinuteDates(
        stockCode: stockCode,
        dateRange: dateRange,
      );
      completed++;
      onProgress?.call(completed, stockCodes.length);
    }

    return result;
  }

  @override
  Future<List<DateTime>> getTradingDates(DateRange dateRange) async {
    return await _metadataManager.getTradingDates(dateRange);
  }

  @override
  Future<int> clearFreshnessCache({KLineDataType? dataType}) async {
    final count = await _dateCheckStorage.clearCheckStatus(dataType: dataType);
    debugPrint('clearFreshnessCache: cleared $count cached check records');
    return count;
  }

  /// 释放资源
  @override
  Future<void> dispose() async {
    await _tdxClient.disconnect();
    await _statusController.close();
    await _dataUpdatedController.close();
    _klineCache.clear();
  }
}

class _HigherTimeframeWriteOutcome {
  final String stockCode;
  final bool success;
  final bool updated;
  final int recordCount;
  final String? error;

  const _HigherTimeframeWriteOutcome({
    required this.stockCode,
    required this.success,
    required this.updated,
    required this.recordCount,
    this.error,
  });
}

class _LegacyMinuteFetchAdapter implements MinuteFetchAdapter {
  final TdxClient _client;

  _LegacyMinuteFetchAdapter({required TdxClient client}) : _client = client;

  @override
  Future<Map<String, List<KLine>>> fetchMinuteBars({
    required List<String> stockCodes,
    required int start,
    required int count,
    ProgressCallback? onProgress,
  }) async {
    final result = <String, List<KLine>>{};

    if (!_client.isConnected) {
      final connected = await _client.autoConnect();
      if (!connected) {
        return {for (final code in stockCodes) code: <KLine>[]};
      }
    }

    for (var index = 0; index < stockCodes.length; index++) {
      final stockCode = stockCodes[index];
      final market = stockCode.startsWith('6') ? 1 : 0;

      try {
        result[stockCode] = await _client.getSecurityBars(
          market: market,
          code: stockCode,
          category: 7,
          start: start,
          count: count,
        );
      } catch (_) {
        result[stockCode] = [];
      }

      onProgress?.call(index + 1, stockCodes.length);
    }

    return result;
  }
}
