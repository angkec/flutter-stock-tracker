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

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

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
    try {
      await service.batchGetMonitorData(
        _allStocks,
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
        child: Column(
          children: [
            StatusBar(
              updateTime: _updateTime,
              progress: _progress > 0 ? _progress : null,
              total: _total > 0 ? _total : null,
              isLoading: _isLoading,
              errorMessage: _errorMessage,
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
              child: StockTable(
                stocks: filteredData,
                isLoading: _isLoading,
                highlightCodes: watchlistService.watchlist.toSet(),
                onTap: (data) => _addToWatchlist(data.stock.code, data.stock.name),
                onIndustryTap: searchByIndustry,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _refresh,
        tooltip: '刷新数据',
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.refresh),
      ),
    );
  }
}
