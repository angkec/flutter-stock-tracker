import 'dart:io';
import 'package:stock_rtwatcher/services/tdx_client.dart';

/// 独立的性能测试脚本
void main() async {
  final client = TdxClient();

  print('=== TDX Client Benchmark ===\n');

  // 1. 连接测试
  print('1. 连接到服务器...');
  final connectStart = DateTime.now();
  final connected = await client.autoConnect();
  final connectTime = DateTime.now().difference(connectStart);
  print('   连接耗时: ${connectTime.inMilliseconds}ms');

  if (!connected) {
    print('   连接失败!');
    exit(1);
  }
  print('   连接成功!\n');

  // 2. 获取股票列表测试
  print('2. 获取深圳市场股票数量...');
  var start = DateTime.now();
  final szCount = await client.getSecurityCount(0);
  var elapsed = DateTime.now().difference(start);
  print('   深圳市场: $szCount 只, 耗时: ${elapsed.inMilliseconds}ms');

  start = DateTime.now();
  final shCount = await client.getSecurityCount(1);
  elapsed = DateTime.now().difference(start);
  print('   上海市场: $shCount 只, 耗时: ${elapsed.inMilliseconds}ms\n');

  // 3. 获取部分股票列表
  print('3. 获取深圳市场前1000只股票...');
  start = DateTime.now();
  final stocks = await client.getSecurityList(0, 0);
  elapsed = DateTime.now().difference(start);
  print('   获取 ${stocks.length} 只, 耗时: ${elapsed.inMilliseconds}ms');

  // 过滤有效A股
  final validStocks = stocks.where((s) => s.isValidAStock).toList();
  print('   有效A股: ${validStocks.length} 只\n');

  // 4. 单只股票K线测试
  if (validStocks.isNotEmpty) {
    final testStock = validStocks.first;
    print('4. 获取单只股票1分钟K线 (${testStock.code} ${testStock.name})...');
    start = DateTime.now();
    final bars = await client.getSecurityBars(
      market: testStock.market,
      code: testStock.code,
      category: klineType1Min,
      start: 0,
      count: 240,
    );
    elapsed = DateTime.now().difference(start);
    print('   获取 ${bars.length} 根K线, 耗时: ${elapsed.inMilliseconds}ms\n');

    // 5. 批量测试 (10只股票)
    final testCount = 10;
    final testStocks = validStocks.take(testCount).toList();
    print('5. 批量获取 $testCount 只股票的1分钟K线 (串行)...');
    start = DateTime.now();
    var totalBars = 0;
    for (final stock in testStocks) {
      final bars = await client.getSecurityBars(
        market: stock.market,
        code: stock.code,
        category: klineType1Min,
        start: 0,
        count: 240,
      );
      totalBars += bars.length;
    }
    elapsed = DateTime.now().difference(start);
    print('   获取 $totalBars 根K线, 总耗时: ${elapsed.inMilliseconds}ms');
    print('   平均每只: ${elapsed.inMilliseconds ~/ testCount}ms\n');

    // 6. 批量测试 (50只股票)
    final testCount2 = 50;
    final testStocks2 = validStocks.take(testCount2).toList();
    print('6. 批量获取 $testCount2 只股票的1分钟K线 (串行)...');
    start = DateTime.now();
    totalBars = 0;
    for (final stock in testStocks2) {
      final bars = await client.getSecurityBars(
        market: stock.market,
        code: stock.code,
        category: klineType1Min,
        start: 0,
        count: 240,
      );
      totalBars += bars.length;
    }
    elapsed = DateTime.now().difference(start);
    print('   获取 $totalBars 根K线, 总耗时: ${elapsed.inMilliseconds}ms');
    print('   平均每只: ${elapsed.inMilliseconds ~/ testCount2}ms\n');
  }

  // 断开连接
  await client.disconnect();
  print('=== 测试完成 ===');
}
