import 'dart:async';
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
import '../../models/kline.dart';
import '../../models/quote.dart';
import '../../services/tdx_client.dart';
import 'data_repository.dart';

/// 市场数据仓库 - DataRepository 的具体实现
class MarketDataRepository implements DataRepository {
  final KLineMetadataManager _metadataManager;
  final TdxClient _tdxClient;
  final DateCheckStorage _dateCheckStorage;
  final StreamController<DataStatus> _statusController = StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _dataUpdatedController = StreamController<DataUpdatedEvent>.broadcast();

  // 内存缓存：Map<cacheKey, List<KLine>>
  // cacheKey = "${stockCode}_${dataType}_${startDate}_${endDate}"
  final Map<String, List<KLine>> _klineCache = {};

  // 最大缓存大小
  static const int _maxCacheSize = 100;

  // 完整分钟数据的最小K线数量（一个交易日约240根1分钟K线）
  static const int _minCompleteBars = 220;

  MarketDataRepository({
    KLineMetadataManager? metadataManager,
    TdxClient? tdxClient,
    DateCheckStorage? dateCheckStorage,
  })  : _metadataManager = metadataManager ?? KLineMetadataManager(),
        _tdxClient = tdxClient ?? TdxClient(),
        _dateCheckStorage = dateCheckStorage ?? DateCheckStorage() {
    // 初始状态：就绪
    _statusController.add(const DataReady(0));
  }

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _dataUpdatedController.stream;

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
        if (_klineCache.length >= _maxCacheSize && !_klineCache.containsKey(cacheKey)) {
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

  String _buildCacheKey(String stockCode, DateRange dateRange, KLineDataType dataType) {
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
      // 1. Check for pending dates (excluding today)
      final pendingDates = await _dateCheckStorage.getPendingDates(
        stockCode: stockCode,
        dataType: dataType,
        excludeToday: true,
      );

      if (pendingDates.isNotEmpty) {
        // Has incomplete historical dates -> Stale
        result[stockCode] = Stale(
          missingRange: DateRange(
            pendingDates.first,
            pendingDates.last,
          ),
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

      // 3. Check if there might be new unchecked dates
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final daysSinceLastCheck = today.difference(latestCheckedDate).inDays;

      if (daysSinceLastCheck > 1) {
        // Might have new trading days not yet checked -> Stale
        result[stockCode] = Stale(
          missingRange: DateRange(
            latestCheckedDate.add(const Duration(days: 1)),
            now,
          ),
        );
      } else {
        // Data is complete -> Fresh
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
        final missingCodes = stockCodes.where((code) => !result.containsKey(code)).toList();
        debugPrint('Missing quotes for ${missingCodes.length} codes: $missingCodes');
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

    // ============ 预检查：过滤掉已完整的股票 ============
    final stocksNeedingFetch = <String>[];
    final skippedStocks = <String>[];

    if (!skipPrecheck && dataType == KLineDataType.oneMinute) {
      for (final stockCode in stockCodes) {
        final missingInfo = await findMissingMinuteDates(
          stockCode: stockCode,
          dateRange: dateRange,
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

      debugPrint('fetchMissingData: ${skippedStocks.length} stocks skipped (already complete), '
                 '${stocksNeedingFetch.length} stocks need fetching');
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
    _statusController.add(DataFetching(
      current: 0,
      total: total,
      currentStock: stocksNeedingFetch.first,
    ));

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

        _statusController.add(DataReady(await _metadataManager.getCurrentVersion()));

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
      _statusController.add(DataFetching(
        current: completedCount,
        total: total,
        currentStock: stockCode,
      ));
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
      _dataUpdatedController.add(DataUpdatedEvent(
        stockCodes: updatedStockCodes,
        dateRange: dateRange,
        dataType: dataType,
        dataVersion: currentVersion,
      ));
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
          debugPrint('Warning: First batch for $stockCode returned empty - may indicate data unavailability');
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

  /// 映射数据类型到 TDX category
  /// oneMinute -> 7 (1分钟K线)
  /// daily -> 4 (日线)
  int _mapDataTypeToCategory(KLineDataType dataType) {
    switch (dataType) {
      case KLineDataType.oneMinute:
        return 7; // 1分钟K线
      case KLineDataType.daily:
        return 4; // 日线
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
  }) async {
    try {
      // 遍历所有数据类型
      for (final dataType in KLineDataType.values) {
        // 查询该类型下所有股票代码
        final stockCodes = await _metadataManager.getAllStockCodes(dataType: dataType);

        for (final stockCode in stockCodes) {
          await _metadataManager.deleteOldData(
            stockCode: stockCode,
            dataType: dataType,
            beforeDate: beforeDate,
          );

          // 清除缓存
          _invalidateCache(stockCode, dataType);
        }
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

  @override
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
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

    // 2. Query cached status
    final checkedStatus = await _dateCheckStorage.getCheckedStatus(
      stockCode: stockCode,
      dataType: KLineDataType.oneMinute,
      dates: tradingDates,
    );

    // 3. Categorize dates
    final missingDates = <DateTime>[];
    final incompleteDates = <DateTime>[];
    final completeDates = <DateTime>[];
    final toCheckDates = <DateTime>[];

    for (final date in tradingDates) {
      final status = checkedStatus[date];

      if (status == null) {
        toCheckDates.add(date);
      } else if (status == DayDataStatus.complete) {
        completeDates.add(date);
      } else {
        // incomplete or missing - re-check
        toCheckDates.add(date);
      }
    }

    // 4. Check uncached dates
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    for (final date in toCheckDates) {
      final barCount = await _metadataManager.countBarsForDate(
        stockCode: stockCode,
        dataType: KLineDataType.oneMinute,
        date: date,
      );

      final dateOnly = DateTime(date.year, date.month, date.day);
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
    final count = await _dateCheckStorage.clearCheckStatus(
      dataType: dataType,
    );
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
