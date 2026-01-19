import 'dart:io';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/models/stock.dart';

/// 并行获取K线数据
Future<int> fetchKlinesParallel(
  List<TdxClient> clients,
  List<Stock> stocks,
) async {
  var totalBars = 0;
  final futures = <Future<int>>[];

  for (var i = 0; i < stocks.length; i++) {
    final client = clients[i % clients.length];
    final stock = stocks[i];

    futures.add(
      client
          .getSecurityBars(
            market: stock.market,
            code: stock.code,
            category: klineType1Min,
            start: 0,
            count: 240,
          )
          .then((bars) => bars.length)
          .catchError((_) => 0),
    );
  }

  final results = await Future.wait(futures);
  for (final count in results) {
    totalBars += count;
  }

  return totalBars;
}

void main() async {
  print('=== TDX Client Parallel Benchmark ===\n');

  // 创建多个连接
  const numConnections = 5;
  final clients = <TdxClient>[];

  print('1. 创建 $numConnections 个并行连接...');
  var start = DateTime.now();

  // 并行连接
  final connectFutures = <Future<bool>>[];
  for (var i = 0; i < numConnections; i++) {
    final client = TdxClient();
    clients.add(client);
    connectFutures.add(client.autoConnect());
  }

  final connectResults = await Future.wait(connectFutures);
  var elapsed = DateTime.now().difference(start);
  final connectedCount = connectResults.where((r) => r).length;
  print('   成功连接: $connectedCount/$numConnections, 耗时: ${elapsed.inMilliseconds}ms\n');

  if (connectedCount == 0) {
    print('   所有连接失败!');
    exit(1);
  }

  // 只保留成功连接的client
  final activeClients = <TdxClient>[];
  for (var i = 0; i < clients.length; i++) {
    if (connectResults[i]) {
      activeClients.add(clients[i]);
    }
  }

  // 获取股票列表
  print('2. 获取股票列表...');
  start = DateTime.now();
  final stocks = await activeClients.first.getSecurityList(0, 0);
  final validStocks = stocks.where((s) => s.isValidAStock).toList();
  elapsed = DateTime.now().difference(start);
  print('   有效A股: ${validStocks.length} 只, 耗时: ${elapsed.inMilliseconds}ms\n');

  // 测试并行获取 (50只)
  final testCount = 50;
  final testStocks = validStocks.take(testCount).toList();
  print('3. 并行获取 $testCount 只股票 (${activeClients.length} 个连接)...');
  start = DateTime.now();
  var totalBars = await fetchKlinesParallel(activeClients, testStocks);
  elapsed = DateTime.now().difference(start);
  print('   获取 $totalBars 根K线, 总耗时: ${elapsed.inMilliseconds}ms');
  print('   平均每只: ${elapsed.inMilliseconds ~/ testCount}ms\n');

  // 测试并行获取 (200只)
  final testCount2 = 200;
  final testStocks2 = validStocks.take(testCount2).toList();
  print('4. 并行获取 $testCount2 只股票 (${activeClients.length} 个连接)...');
  start = DateTime.now();
  totalBars = await fetchKlinesParallel(activeClients, testStocks2);
  elapsed = DateTime.now().difference(start);
  print('   获取 $totalBars 根K线, 总耗时: ${elapsed.inMilliseconds}ms');
  print('   平均每只: ${elapsed.inMilliseconds ~/ testCount2}ms\n');

  // 测试并行获取 (全部有效股票，但最多1000只)
  final testCount3 = validStocks.length > 1000 ? 1000 : validStocks.length;
  final testStocks3 = validStocks.take(testCount3).toList();
  print('5. 并行获取 $testCount3 只股票 (${activeClients.length} 个连接)...');
  start = DateTime.now();
  totalBars = await fetchKlinesParallel(activeClients, testStocks3);
  elapsed = DateTime.now().difference(start);
  print('   获取 $totalBars 根K线, 总耗时: ${elapsed.inMilliseconds}ms');
  print('   平均每只: ${elapsed.inMilliseconds ~/ testCount3}ms\n');

  // 断开所有连接
  for (final client in activeClients) {
    await client.disconnect();
  }

  print('=== 测试完成 ===');
}
