// lib/screens/watchlist_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _codeController = TextEditingController();
  List<StockMonitorData> _monitorData = [];
  String? _updateTime;
  bool _isLoading = false;
  bool _isConnected = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final watchlistService = context.read<WatchlistService>();
    await watchlistService.load();
    if (!mounted) return;
    await _connect();
    if (!mounted) return;
    if (_isConnected && watchlistService.watchlist.isNotEmpty) {
      await _fetchData();
      _startAutoRefresh();
    }
  }

  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final pool = context.read<TdxPool>();
    try {
      final success = await pool.autoConnect();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isConnected = success;
        if (!success) _errorMessage = '无法连接到服务器';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isConnected = false;
        _errorMessage = '连接失败: $e';
      });
    }
  }

  Future<void> _fetchData() async {
    final watchlistService = context.read<WatchlistService>();
    if (watchlistService.watchlist.isEmpty) {
      if (mounted) setState(() => _monitorData = []);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final stockService = context.read<StockService>();
    final industryService = context.read<IndustryService>();

    try {
      // Get all stocks to find names for watchlist codes
      final allStocks = await stockService.getAllStocks();
      if (!mounted) return;

      // Build stock list for watchlist codes
      final watchlistCodes = watchlistService.watchlist.toSet();
      final stocks = <Stock>[];
      for (final stock in allStocks) {
        if (watchlistCodes.contains(stock.code)) {
          stocks.add(stock);
        }
      }

      // Add any codes not found in allStocks (shouldn't happen normally)
      for (final code in watchlistService.watchlist) {
        if (!stocks.any((s) => s.code == code)) {
          stocks.add(Stock(
            code: code,
            name: code,
            market: WatchlistService.getMarket(code),
          ));
        }
      }

      if (!mounted) return;

      final data = await stockService.batchGetMonitorData(
        stocks,
        industryService: industryService,
      );
      data.sort((a, b) => b.ratio.compareTo(a.ratio));

      if (!mounted) return;
      setState(() {
        _monitorData = data;
        _updateTime = _formatTime();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '获取数据失败: $e';
        _isLoading = false;
      });
    }
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) async {
        if (mounted) {
          await _refresh();
        }
      },
    );
  }

  Future<void> _refresh() async {
    if (_isLoading) return;

    final pool = context.read<TdxPool>();

    // 确保连接可用（会自动重连死连接）
    final connected = await pool.ensureConnected();
    if (!mounted) return;

    if (!connected) {
      setState(() {
        _isConnected = false;
        _errorMessage = '无法连接到服务器';
      });
      return;
    }

    setState(() => _isConnected = true);
    await _fetchData();
  }

  Future<void> _addStock() async {
    final code = _codeController.text.trim();
    if (!WatchlistService.isValidCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的股票代码')),
      );
      return;
    }

    final watchlistService = context.read<WatchlistService>();
    if (watchlistService.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该股票已在自选中')),
      );
      return;
    }

    await watchlistService.addStock(code);
    _codeController.clear();
    await _fetchData();
  }

  Future<void> _removeStock(String code, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除 $code $name？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final watchlistService = context.read<WatchlistService>();
      await watchlistService.removeStock(code);
      await _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          StatusBar(
            updateTime: _updateTime,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
          ),
          // 添加股票输入框
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      hintText: '输入股票代码',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onSubmitted: (_) => _addStock(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addStock,
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
          // 自选股列表
          Expanded(
            child: _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final watchlistService = context.watch<WatchlistService>();

    if (watchlistService.watchlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_outline, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('暂无自选股', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('请在上方输入股票代码添加', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    if (_monitorData.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在获取数据...', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: StockTable(
        stocks: _monitorData,
        isLoading: _isLoading,
        onLongPress: (data) => _removeStock(data.stock.code, data.stock.name),
      ),
    );
  }
}
