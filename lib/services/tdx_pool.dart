import 'dart:async';

import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

/// TDX 连接池，支持并行请求
class TdxPool {
  final List<TdxClient> _clients = [];
  final int _poolSize;
  bool _isConnected = false;
  String? _connectedHost;
  int? _connectedPort;

  TdxPool({int poolSize = 5}) : _poolSize = poolSize;

  bool get isConnected => _isConnected && _clients.any((c) => c.isConnected);
  int get poolSize => _clients.length;

  /// 确保连接可用，如果有死连接则重连
  Future<bool> ensureConnected() async {
    // 移除所有死连接
    _clients.removeWhere((c) => !c.isConnected);

    // 如果没有可用连接，重新连接
    if (_clients.isEmpty) {
      _isConnected = false;
      return await autoConnect();
    }

    // 如果连接数不足，补充连接
    if (_clients.length < _poolSize && _connectedHost != null) {
      final futures = <Future<TdxClient?>>[];
      for (var i = _clients.length; i < _poolSize; i++) {
        futures.add(_createConnection(_connectedHost!, _connectedPort!));
      }
      final results = await Future.wait(futures);
      for (final client in results) {
        if (client != null) {
          _clients.add(client);
        }
      }
    }

    return _clients.isNotEmpty;
  }

  /// 自动连接到可用服务器
  /// 并行尝试所有服务器，使用第一个成功的
  Future<bool> autoConnect() async {
    // 并行尝试所有服务器
    final completer = Completer<(String, int)?>();
    var pendingCount = TdxClient.servers.length;

    for (final server in TdxClient.servers) {
      final host = server['host'] as String;
      final port = server['port'] as int;

      _createConnection(host, port).then((client) {
        if (client != null && !completer.isCompleted) {
          // 第一个成功的连接
          _connectedHost = host;
          _connectedPort = port;
          _clients.add(client);
          completer.complete((host, port));
        } else {
          pendingCount--;
          if (pendingCount == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      });
    }

    final result = await completer.future;
    if (result == null) {
      return false;
    }

    // 并行创建剩余连接
    final futures = <Future<TdxClient?>>[];
    for (var i = 1; i < _poolSize; i++) {
      futures.add(_createConnection(_connectedHost!, _connectedPort!));
    }

    final results = await Future.wait(futures);
    for (final client in results) {
      if (client != null) {
        _clients.add(client);
      }
    }

    _isConnected = _clients.isNotEmpty;
    return _isConnected;
  }

  Future<TdxClient?> _createConnection(String host, int port) async {
    final client = TdxClient();
    if (await client.connect(host, port)) {
      return client;
    }
    return null;
  }

  /// 断开所有连接
  Future<void> disconnect() async {
    for (final client in _clients) {
      await client.disconnect();
    }
    _clients.clear();
    _isConnected = false;
  }

  /// 获取股票数量 (使用第一个连接)
  Future<int> getSecurityCount(int market) async {
    if (_clients.isEmpty) throw StateError('Not connected');
    return _clients.first.getSecurityCount(market);
  }

  /// 获取股票列表 (使用第一个连接)
  Future<List<Stock>> getSecurityList(int market, int start) async {
    if (_clients.isEmpty) throw StateError('Not connected');
    return _clients.first.getSecurityList(market, start);
  }

  /// 并行批量获取K线数据
  Future<List<List<KLine>>> batchGetSecurityBars({
    required List<Stock> stocks,
    required int category,
    required int start,
    required int count,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_clients.isEmpty) throw StateError('Not connected');

    final results = List<List<KLine>>.filled(stocks.length, []);
    var completed = 0;

    // 创建所有任务
    final futures = <Future<void>>[];

    for (var i = 0; i < stocks.length; i++) {
      final stockIndex = i;
      final client = _clients[i % _clients.length];
      final stock = stocks[i];

      futures.add(
        client
            .getSecurityBars(
              market: stock.market,
              code: stock.code,
              category: category,
              start: start,
              count: count,
            )
            .then((bars) {
          results[stockIndex] = bars;
          completed++;
          onProgress?.call(completed, stocks.length);
        }).catchError((_) {
          results[stockIndex] = [];
          completed++;
          onProgress?.call(completed, stocks.length);
        }),
      );
    }

    await Future.wait(futures);
    return results;
  }

  /// 并行批量获取K线数据 (流式回调)
  /// [onStockBars] 每获取到一只股票的数据就立即回调
  Future<void> batchGetSecurityBarsStreaming({
    required List<Stock> stocks,
    required int category,
    required int start,
    required int count,
    required void Function(int stockIndex, List<KLine> bars) onStockBars,
  }) async {
    if (_clients.isEmpty) throw StateError('Not connected');

    final futures = <Future<void>>[];

    for (var i = 0; i < stocks.length; i++) {
      final stockIndex = i;
      final client = _clients[i % _clients.length];
      final stock = stocks[i];

      futures.add(
        client
            .getSecurityBars(
              market: stock.market,
              code: stock.code,
              category: category,
              start: start,
              count: count,
            )
            .then((bars) {
          onStockBars(stockIndex, bars);
        }).catchError((_) {
          onStockBars(stockIndex, []);
        }),
      );
    }

    await Future.wait(futures);
  }
}
