// ignore_for_file: avoid_print

import 'dart:io';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';

void main() async {
  print('=== TDX Pool Benchmark ===\n');

  final pool = TdxPool(poolSize: 5);

  // 1. 连接测试
  print('1. 连接到服务器 (5个并行连接)...');
  var start = DateTime.now();
  final connected = await pool.autoConnect();
  var elapsed = DateTime.now().difference(start);
  print('   连接耗时: ${elapsed.inMilliseconds}ms');

  if (!connected) {
    print('   连接失败!');
    exit(1);
  }
  print('   成功连接 ${pool.poolSize} 个连接!\n');

  // 2. 获取股票列表
  print('2. 获取股票列表...');
  start = DateTime.now();

  final szCount = await pool.getSecurityCount(0);
  final shCount = await pool.getSecurityCount(1);
  print('   深圳: $szCount, 上海: $shCount');

  final stocks = await pool.getSecurityList(0, 0);
  final validStocks = stocks.where((s) => s.isValidAStock).toList();
  elapsed = DateTime.now().difference(start);
  print('   有效A股: ${validStocks.length} 只, 耗时: ${elapsed.inMilliseconds}ms\n');

  // 3. 批量获取K线 (100只)
  const testCount1 = 100;
  final testStocks1 = validStocks.take(testCount1).toList();
  print('3. 并行获取 $testCount1 只股票的1分钟K线...');
  start = DateTime.now();
  final bars1 = await pool.batchGetSecurityBars(
    stocks: testStocks1,
    category: klineType1Min,
    start: 0,
    count: 240,
  );
  elapsed = DateTime.now().difference(start);
  final totalBars1 = bars1.fold<int>(0, (sum, b) => sum + b.length);
  print('   获取 $totalBars1 根K线, 总耗时: ${elapsed.inMilliseconds}ms');
  print('   平均每只: ${elapsed.inMilliseconds ~/ testCount1}ms\n');

  // 4. 批量获取K线 (全部有效股票)
  final testCount2 = validStocks.length;
  print('4. 并行获取 $testCount2 只股票的1分钟K线 (全部)...');
  start = DateTime.now();
  var completed = 0;
  final bars2 = await pool.batchGetSecurityBars(
    stocks: validStocks,
    category: klineType1Min,
    start: 0,
    count: 240,
    onProgress: (current, total) {
      if (current % 100 == 0 || current == total) {
        final pct = (current / total * 100).toStringAsFixed(1);
        stdout.write('\r   进度: $current/$total ($pct%)');
      }
      completed = current;
    },
  );
  print('');
  elapsed = DateTime.now().difference(start);
  final totalBars2 = bars2.fold<int>(0, (sum, b) => sum + b.length);
  print('   获取 $totalBars2 根K线, 总耗时: ${elapsed.inMilliseconds}ms');
  print('   平均每只: ${elapsed.inMilliseconds ~/ testCount2}ms\n');

  // 断开连接
  await pool.disconnect();
  print('=== 测试完成 ===');
}
