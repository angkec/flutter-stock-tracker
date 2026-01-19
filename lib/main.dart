import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/screens/main_screen.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) {
          final service = IndustryService();
          service.load(); // 异步加载，不阻塞启动
          return service;
        }),
        Provider(create: (_) => TdxPool(poolSize: 5)),
        ProxyProvider<TdxPool, StockService>(
          update: (_, pool, __) => StockService(pool),
        ),
        ChangeNotifierProvider(create: (_) => WatchlistService()),
      ],
      child: MaterialApp(
        title: 'A股涨跌量比监控',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const MainScreen(),
      ),
    );
  }
}
