import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

/// 主页面
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Stock> _allStocks = [];
  List<StockMonitorData> _monitorData = [];
  String? _updateTime;
  int _progress = 0;
  int _total = 0;
  bool _isLoading = false;
  bool _isConnected = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  // 显示的数量
  static const int _displayCount = 20;
  // 自动刷新间隔 (秒)
  static const int _refreshInterval = 60;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 初始化连接和数据
  Future<void> _initialize() async {
    await _connect();
    if (_isConnected) {
      await _loadStocks();
      await _fetchMonitorData();
      _startAutoRefresh();
    }
  }

  /// 连接到TDX服务器
  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final pool = context.read<TdxPool>();

    try {
      final success = await pool.autoConnect();
      setState(() {
        _isConnected = success;
        if (!success) {
          _errorMessage = '无法连接到服务器';
        }
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _errorMessage = '连接失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 加载股票列表
  Future<void> _loadStocks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final service = context.read<StockService>();

    try {
      final stocks = await service.getAllStocks();
      setState(() {
        _allStocks = stocks;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '获取股票列表失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 获取监控数据
  Future<void> _fetchMonitorData() async {
    if (_allStocks.isEmpty) return;

    setState(() {
      _isLoading = true;
      _progress = 0;
      _total = _allStocks.length;
      _errorMessage = null;
    });

    final service = context.read<StockService>();

    try {
      final data = await service.batchGetMonitorData(
        _allStocks,
        onProgress: (current, total) {
          setState(() {
            _progress = current;
            _total = total;
          });
        },
      );

      // 按涨跌量比排序，取前N个
      data.sort((a, b) => b.ratio.compareTo(a.ratio));
      final topData = data.take(_displayCount).toList();

      setState(() {
        _monitorData = topData;
        _updateTime = _formatCurrentTime();
      });
    } catch (e) {
      setState(() {
        _errorMessage = '获取监控数据失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _progress = 0;
        _total = 0;
      });
    }
  }

  /// 格式化当前时间
  String _formatCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  /// 启动自动刷新
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: _refreshInterval),
      (_) => _fetchMonitorData(),
    );
  }

  /// 手动刷新
  Future<void> _refresh() async {
    if (_isLoading) return;

    if (!_isConnected) {
      await _initialize();
    } else {
      await _fetchMonitorData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 状态栏
          StatusBar(
            updateTime: _updateTime,
            progress: _progress > 0 ? _progress : null,
            total: _total > 0 ? _total : null,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
          ),
          // 主内容区域
          Expanded(
            child: StockTable(
              stocks: _monitorData,
              isLoading: _isLoading,
            ),
          ),
        ],
      ),
      // 刷新按钮
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
