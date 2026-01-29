import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/kline.dart';

/// 历史分钟K线数据服务
/// 统一管理原始分钟K线，支持增量拉取
class HistoricalKlineService extends ChangeNotifier {
  /// 数据仓库（用于获取数据更新通知）
  final DataRepository _repository;

  /// 数据更新订阅（用于取消订阅）
  StreamSubscription? _dataUpdatedSubscription;

  /// 缓存版本（用于判断是否需要重新计算）
  int _cacheVersion = -1;

  /// 每日涨跌量缓存
  /// { stockCode: { dateKey: (up, down) } }
  Map<String, Map<String, ({double up, double down})>> _dailyVolumesCache = {};

  /// 构造函数
  HistoricalKlineService({required DataRepository repository}) : _repository = repository {
    // 监听数据更新事件，失效缓存
    _dataUpdatedSubscription = _repository.dataUpdatedStream.listen(
      (event) {
        debugPrint('[HistoricalKline] 收到数据更新事件: version=${event.dataVersion}, stocks=${event.stockCodes.length}');
        // 失效对应股票的缓存
        for (final stockCode in event.stockCodes) {
          _dailyVolumesCache.remove(stockCode);
        }
        // 更新缓存版本
        _cacheVersion = event.dataVersion;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('[HistoricalKline] 数据更新流错误: $error');
      },
    );
  }

  @override
  void dispose() {
    _dataUpdatedSubscription?.cancel();
    _dataUpdatedSubscription = null;
    super.dispose();
  }

  /// 格式化日期为 "YYYY-MM-DD" 字符串
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 解析 "YYYY-MM-DD" 字符串为 DateTime
  static DateTime parseDate(String dateStr) {
    final parts = dateStr.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  /// 获取某只股票所有日期的涨跌量汇总
  /// 返回 { dateKey: (up: upVolume, down: downVolume) }
  Future<Map<String, ({double up, double down})>> getDailyVolumes(String stockCode) async {
    try {
      // Check cache validity by version
      final repoVersion = await _repository.getCurrentVersion();
      if (repoVersion != _cacheVersion) {
        _dailyVolumesCache.clear();
        _cacheVersion = repoVersion;
      }

      // Return cached if available
      if (_dailyVolumesCache.containsKey(stockCode)) {
        return _dailyVolumesCache[stockCode]!;
      }

      // Fetch from DataRepository
      final klines = await _repository.getKlines(
        stockCodes: [stockCode],
        dateRange: DateRange(
          DateTime.now().subtract(const Duration(days: 30)),
          DateTime.now(),
        ),
        dataType: KLineDataType.oneMinute,
      );

      final bars = klines[stockCode] ?? [];
      final result = _computeDailyVolumes(bars);

      // Cache result
      _dailyVolumesCache[stockCode] = result;
      return result;
    } catch (e, stackTrace) {
      debugPrint('[HistoricalKline] getDailyVolumes failed for $stockCode: $e');
      if (kDebugMode) {
        debugPrint('Stack trace: $stackTrace');
      }
      return {};
    }
  }

  /// 计算每日涨跌量（纯计算，无IO）
  Map<String, ({double up, double down})> _computeDailyVolumes(List<KLine> bars) {
    if (bars.isEmpty) return {};

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

  /// 获取某只股票某日的分钟量比
  /// 返回 null 表示数据不足或无法计算（涨停/跌停等）
  Future<double?> getDailyRatio(String stockCode, DateTime date) async {
    final volumes = await getDailyVolumes(stockCode);
    final dateKey = formatDate(date);
    final dayVolume = volumes[dateKey];
    if (dayVolume == null || dayVolume.down == 0 || dayVolume.up == 0) {
      return null;
    }
    return dayVolume.up / dayVolume.down;
  }

  /// 获取缺失天数（基于 DataRepository.checkFreshness）
  ///
  /// 需要传入股票代码列表来检查数据新鲜度。
  /// 返回所有股票的累计缺失天数估算值。
  ///
  /// 计算逻辑：
  /// - Missing: 完全缺失的股票，按30天计算
  /// - Stale: 数据过时的股票，按缺失范围的天数计算（上限30天）
  /// - Fresh: 数据完整，不计入缺失
  Future<int> getMissingDaysForStocks(List<String> stockCodes) async {
    if (stockCodes.isEmpty) return 0;

    try {
      final freshness = await _repository.checkFreshness(
        stockCodes: stockCodes,
        dataType: KLineDataType.oneMinute,
      );

      int missingCount = 0;
      for (final entry in freshness.entries) {
        switch (entry.value) {
          case Missing():
            missingCount += 30; // Assume 30 days missing for completely missing stock
          case Stale(:final missingRange):
            missingCount += missingRange.duration.inDays.clamp(1, 30);
          case Fresh():
            // No missing data
            break;
        }
      }

      return missingCount;
    } catch (e) {
      debugPrint('[HistoricalKline] getMissingDaysForStocks failed: $e');
      return 0;
    }
  }
}
