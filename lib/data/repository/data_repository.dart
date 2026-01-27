// lib/data/repository/data_repository.dart

import 'dart:async';
import '../models/data_status.dart';
import '../models/data_updated_event.dart';
import '../models/data_freshness.dart';
import '../models/kline_data_type.dart';
import '../models/date_range.dart';
import '../models/fetch_result.dart';
import '../../models/kline.dart';
import '../../models/quote.dart';

typedef ProgressCallback = void Function(int current, int total);

/// 数据仓库接口 - 唯一的数据源
abstract class DataRepository {
  // ============ 状态流 ============

  /// 数据状态流
  Stream<DataStatus> get statusStream;

  /// 数据更新事件流
  Stream<DataUpdatedEvent> get dataUpdatedStream;

  // ============ 查询接口 ============

  /// 获取K线数据（优先从缓存读取）
  ///
  /// [stockCodes] 股票代码列表
  /// [dateRange] 日期范围
  /// [dataType] 数据类型 '1min' 或 'daily'
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  });

  /// 检查数据新鲜度
  ///
  /// 返回每只股票的数据状态：
  /// - fresh: 数据完整
  /// - stale: 数据过时，需要拉取
  /// - missing: 完全缺失
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  });

  /// 获取实时行情
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  });

  /// 获取当前数据版本
  Future<int> getCurrentVersion();

  // ============ 命令接口 ============

  /// 拉取缺失数据（增量更新）
  ///
  /// [stockCodes] 需要更新的股票列表
  /// [dateRange] 需要拉取的日期范围
  /// [dataType] 数据类型
  ///
  /// 返回拉取结果统计
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  });

  /// 强制重新拉取（覆盖现有数据）
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  });

  /// 清理旧数据
  ///
  /// [beforeDate] 清理此日期之前的数据
  Future<void> cleanupOldData({
    required DateTime beforeDate,
  });
}
