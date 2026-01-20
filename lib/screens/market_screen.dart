// lib/screens/market_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';
import 'package:stock_rtwatcher/widgets/market_stats_bar.dart';

class MarketScreen extends StatefulWidget {
  final VoidCallback? onRefresh;

  const MarketScreen({super.key, this.onRefresh});

  @override
  State<MarketScreen> createState() => MarketScreenState();
}

class MarketScreenState extends State<MarketScreen> {
  final _searchController = TextEditingController();
  List<Stock> _allStocks = [];
  List<StockMonitorData> _monitorData = [];
  String _searchQuery = '';
  String? _updateTime;
  int _progress = 0;
  int _total = 0;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // 延迟调用以确保 context 可用
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StockMonitorData> get _filteredData {
    if (_searchQuery.isEmpty) return _monitorData;

    final query = _searchQuery.trim();
    final industryService = context.read<IndustryService>();

    // 如果是完整行业名，只按行业筛选
    if (industryService.allIndustries.contains(query)) {
      return _monitorData.where((d) => d.industry == query).toList();
    }

    // 否则按代码/名称搜索
    final lowerQuery = query.toLowerCase();
    return _monitorData
        .where((d) =>
            d.stock.code.contains(lowerQuery) ||
            d.stock.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  Future<void> _loadStocks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final service = context.read<StockService>();
    try {
      final stocks = await service.getAllStocks();
      if (!mounted) return;
      setState(() => _allStocks = stocks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '获取股票列表失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMonitorData() async {
    if (_allStocks.isEmpty) return;

    setState(() {
      _isLoading = true;
      _progress = 0;
      _total = _allStocks.length;
      _errorMessage = null;
    });

    final service = context.read<StockService>();
    final industryService = context.read<IndustryService>();
    final watchlistService = context.read<WatchlistService>();

    // 将自选股放到列表最前面，优先获取
    final watchlistCodes = watchlistService.watchlist.toSet();
    final prioritizedStocks = <Stock>[];
    final otherStocks = <Stock>[];
    for (final stock in _allStocks) {
      if (watchlistCodes.contains(stock.code)) {
        prioritizedStocks.add(stock);
      } else {
        otherStocks.add(stock);
      }
    }
    final orderedStocks = [...prioritizedStocks, ...otherStocks];

    try {
      await service.batchGetMonitorData(
        orderedStocks,
        industryService: industryService,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progress = current;
              _total = total;
            });
          }
        },
        onData: (results) {
          if (mounted) {
            setState(() {
              _monitorData = results; // Show ALL stocks, no limit
              _updateTime = _formatCurrentTime();
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '获取监控数据失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _progress = 0;
          _total = 0;
        });
      }
    }
  }

  String _formatCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  /// 按行业搜索（公开方法，供外部调用）
  void searchByIndustry(String industry) {
    _searchController.text = industry;
    setState(() => _searchQuery = industry);
  }

  /// 公开的刷新方法，供外部调用
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    if (_isLoading) return;

    final pool = context.read<TdxPool>();

    // 确保连接可用（会自动重连死连接）
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connected = await pool.ensureConnected();
      if (!mounted) return;

      if (!connected) {
        setState(() {
          _isLoading = false;
          _errorMessage = '无法连接到服务器';
        });
        return;
      }

      if (_allStocks.isEmpty) {
        await _loadStocks();
      }
      await _fetchMonitorData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '刷新失败: $e';
      });
    }
  }

  Future<void> _addToWatchlist(String code, String name) async {
    final watchlistService = context.read<WatchlistService>();
    if (watchlistService.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name 已在自选中'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await watchlistService.addStock(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加 $name 到自选'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlistService = context.watch<WatchlistService>();
    final filteredData = _filteredData;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                StatusBar(
                  updateTime: _updateTime,
                  progress: _progress > 0 ? _progress : null,
                  total: _total > 0 ? _total : null,
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  onRefresh: widget.onRefresh,
                ),
                // 搜索框
                if (_monitorData.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索代码或名称',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 68),
                    child: StockTable(
                      stocks: filteredData,
                      isLoading: _isLoading,
                      highlightCodes: watchlistService.watchlist.toSet(),
                      onTap: (data) => _addToWatchlist(data.stock.code, data.stock.name),
                      onIndustryTap: searchByIndustry,
                    ),
                  ),
                ),
              ],
            ),
            // 底部统计条
            if (filteredData.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MarketStatsBar(stocks: filteredData),
              ),
          ],
        ),
      ),
    );
  }
}
