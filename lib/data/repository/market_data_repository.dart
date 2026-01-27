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
    // TODO: Implement
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: {},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    // TODO: Implement
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: {},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<void> cleanupOldData({
    required DateTime beforeDate,
  }) async {
    // TODO: Implement
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
