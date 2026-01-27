import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/data_status.dart';
import '../models/data_updated_event.dart';
import '../models/data_freshness.dart';
import '../models/kline_data_type.dart';
import '../models/date_range.dart';
import '../models/fetch_result.dart';
import '../storage/kline_metadata_manager.dart';
import '../../models/kline.dart';
import '../../models/quote.dart';
import '../../services/tdx_client.dart';
import 'data_repository.dart';

/// 市场数据仓库 - DataRepository 的具体实现
class MarketDataRepository implements DataRepository {
  final KLineMetadataManager _metadataManager;
  final TdxClient _tdxClient;
  final StreamController<DataStatus> _statusController = StreamController<DataStatus>.broadcast();
  final StreamController<DataUpdatedEvent> _dataUpdatedController = StreamController<DataUpdatedEvent>.broadcast();

  // 内存缓存：Map<cacheKey, List<KLine>>
  // cacheKey = "${stockCode}_${dataType}_${startDate}_${endDate}"
  final Map<String, List<KLine>> _klineCache = {};

  // 最大缓存大小
  static const int _maxCacheSize = 100;

  MarketDataRepository({
    KLineMetadataManager? metadataManager,
    TdxClient? tdxClient,
  })  : _metadataManager = metadataManager ?? KLineMetadataManager(),
        _tdxClient = tdxClient ?? TdxClient() {
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
      try {
        // 获取最新数据日期
        final latestDate = await _metadataManager.getLatestDataDate(
          stockCode: stockCode,
          dataType: dataType,
        );

        if (latestDate == null) {
          // 完全没有数据
          result[stockCode] = const Missing();
          continue;
        }

        // 检查数据是否过时
        final now = DateTime.now();
        final age = now.difference(latestDate);

        // 1分钟数据和日线数据：超过1天视为过时
        // 注意：age > staleThreshold 意味着恰好24小时的数据仍视为新鲜
        const staleThreshold = Duration(days: 1);

        if (age > staleThreshold) {
          // 数据过时，需要拉取从 latestDate+1 到现在的数据
          final missingStart = latestDate.add(const Duration(days: 1));
          result[stockCode] = Stale(
            missingRange: DateRange(missingStart, now),
          );
        } else {
          // 数据新鲜
          result[stockCode] = const Fresh();
        }
      } catch (e, stackTrace) {
        // 出错视为缺失
        debugPrint('Failed to check freshness for $stockCode: $e');
        if (kDebugMode) {
          debugPrint('Stack trace: $stackTrace');
        }
        result[stockCode] = const Missing();
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
    final stopwatch = Stopwatch()..start();
    final total = stockCodes.length;

    // 处理空列表
    if (total == 0) {
      return FetchResult(
        totalStocks: 0,
        successCount: 0,
        failureCount: 0,
        errors: {},
        totalRecords: 0,
        duration: stopwatch.elapsed,
      );
    }

    // 发出 DataFetching 状态
    _statusController.add(DataFetching(
      current: 0,
      total: total,
      currentStock: stockCodes.first,
    ));

    // 连接到 TDX 服务器
    if (!_tdxClient.isConnected) {
      final connected = await _tdxClient.autoConnect();
      if (!connected) {
        debugPrint('fetchMissingData: 无法连接到 TDX 服务器');
        stopwatch.stop();

        // 所有股票都视为失败
        final errors = <String, String>{};
        for (final code in stockCodes) {
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

    // 遍历股票代码
    for (var i = 0; i < total; i++) {
      final stockCode = stockCodes[i];

      // 更新状态
      _statusController.add(DataFetching(
        current: i + 1,
        total: total,
        currentStock: stockCode,
      ));

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
        debugPrint('fetchMissingData: $stockCode 成功，获取 ${klines.length} 条数据');
      } catch (e, stackTrace) {
        failureCount++;
        errors[stockCode] = e.toString();
        debugPrint('fetchMissingData: $stockCode 失败 - $e');
        if (kDebugMode) {
          debugPrint('Stack trace: $stackTrace');
        }
      }

      // 报告进度
      onProgress?.call(i + 1, total);
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

    return FetchResult(
      totalStocks: total,
      successCount: successCount,
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
    // refetchData 和 fetchMissingData 逻辑相同
    // 区别在于 refetchData 强制重新拉取，覆盖现有数据
    // 由于 saveKlineData 会覆盖同月数据，所以实现相同
    return await fetchMissingData(
      stockCodes: stockCodes,
      dateRange: dateRange,
      dataType: dataType,
      onProgress: onProgress,
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

  /// 释放资源
  @override
  Future<void> dispose() async {
    await _tdxClient.disconnect();
    await _statusController.close();
    await _dataUpdatedController.close();
    _klineCache.clear();
  }
}
