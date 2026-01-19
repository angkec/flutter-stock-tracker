// lib/screens/watchlist_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

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
    final pool = context.read<TdxPool>();

    try {
      // Cache security lists per market to avoid repeated API calls
      final securityListCache = <int, List<Stock>>{};
      final stocks = <Stock>[];

      for (final code in watchlistService.watchlist) {
        final market = WatchlistService.getMarket(code);
        if (!securityListCache.containsKey(market)) {
          securityListCache[market] = await pool.getSecurityList(market, 0);
        }
        final stockList = securityListCache[market]!;
        final stock = stockList.firstWhere(
          (s) => s.code == code,
          orElse: () => Stock(code: code, name: code, market: market),
        );
        stocks.add(stock);
      }

      if (!mounted) return;

      final data = await stockService.batchGetMonitorData(stocks);
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
      (_) {
        if (_isConnected && mounted) {
          _fetchData();
        }
      },
    );
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

  void _copyCode(String code, String name) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $code ($name)'),
        duration: const Duration(seconds: 1),
      ),
    );
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
      onRefresh: _fetchData,
      child: ListView.builder(
        itemCount: _monitorData.length,
        itemBuilder: (context, index) {
          final data = _monitorData[index];
          final ratioColor = data.ratio >= 1 ? const Color(0xFFFF4444) : const Color(0xFF00AA00);

          return ListTile(
            leading: GestureDetector(
              onTap: () => _copyCode(data.stock.code, data.stock.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  data.stock.code,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            title: Text(
              data.stock.name,
              style: TextStyle(color: data.stock.isST ? Colors.orange : null),
            ),
            trailing: Text(
              data.ratio.toStringAsFixed(2),
              style: TextStyle(
                color: ratioColor,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            onLongPress: () => _removeStock(data.stock.code, data.stock.name),
          );
        },
      ),
    );
  }
}
