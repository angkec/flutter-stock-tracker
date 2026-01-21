import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';

class MarketDataProvider extends ChangeNotifier {
  final TdxPool _pool;
  final StockService _stockService;
  final IndustryService _industryService;
  PullbackService? _pullbackService;

  List<StockMonitorData> _allData = [];
  bool _isLoading = false;
  int _progress = 0;
  int _total = 0;
  String? _updateTime;
  DateTime? _dataDate;
  String? _errorMessage;

  // Watchlist codes for priority sorting
  Set<String> _watchlistCodes = {};

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

  /// 从缓存加载数据
  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('market_data_cache');
      final timeStr = prefs.getString('market_data_time');
      final dateStr = prefs.getString('market_data_date');

      if (jsonStr != null) {
        final List<dynamic> jsonList = json.decode(jsonStr);
        _allData = jsonList
            .map((e) => StockMonitorData.fromJson(e as Map<String, dynamic>))
            .toList();
        _updateTime = timeStr;
        if (dateStr != null) {
          _dataDate = DateTime.tryParse(dateStr);
        }
        notifyListeners();
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

  /// 刷新数据
  Future<void> refresh() async {
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
        _errorMessage = '无法连接到服务器';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 获取所有股票
      final stocks = await _stockService.getAllStocks();
      _total = stocks.length;
      notifyListeners();

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

      // 批量获取数据（渐进式更新）
      final result = await _stockService.batchGetMonitorData(
        orderedStocks,
        industryService: _industryService,
        onProgress: (current, total) {
          _progress = current;
          _total = total;
          notifyListeners();
        },
        onData: (results) {
          _allData = results;
          notifyListeners();
        },
      );

      // 保存数据日期
      _dataDate = result.dataDate;

      // 检测高质量回踩
      if (_pullbackService != null && _allData.isNotEmpty) {
        await _detectPullbacks();
      }

      // 更新时间
      final now = DateTime.now();
      _updateTime = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      _isLoading = false;
      _progress = 0;
      _total = 0;
      notifyListeners();

      // 保存到缓存
      await _saveToCache();
    } catch (e) {
      _errorMessage = '获取数据失败: $e';
      _isLoading = false;
      _progress = 0;
      _total = 0;
      notifyListeners();
    }
  }

  /// 检测高质量回踩
  Future<void> _detectPullbacks() async {
    if (_pullbackService == null || _allData.isEmpty) return;

    // 获取所有股票信息
    final stocks = _allData.map((d) => d.stock).toList();

    // 批量获取日K数据（7根，用于回踩检测）
    final dailyBarsMap = <String, List<dynamic>>{}; // code -> bars

    await _pool.batchGetSecurityBarsStreaming(
      stocks: stocks,
      category: klineTypeDaily,
      start: 0,
      count: 7,
      onStockBars: (index, bars) {
        dailyBarsMap[stocks[index].code] = bars;
      },
    );

    // 更新回踩标记
    final updatedData = <StockMonitorData>[];
    for (final data in _allData) {
      final dailyBars = dailyBarsMap[data.stock.code];
      final isPullback = dailyBars != null &&
          dailyBars.length >= 7 &&
          _pullbackService!.isPullback(dailyBars.cast());

      updatedData.add(data.copyWith(isPullback: isPullback));
    }

    _allData = updatedData;
    notifyListeners();
  }
}
