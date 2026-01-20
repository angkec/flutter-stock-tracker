import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/screens/main_screen.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';

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
        ChangeNotifierProxyProvider3<TdxPool, StockService, IndustryService, MarketDataProvider>(
          create: (_) => MarketDataProvider(
            pool: TdxPool(poolSize: 5), // 临时，会被 update 替换
            stockService: StockService(TdxPool(poolSize: 5)),
            industryService: IndustryService(),
          ),
          update: (_, pool, stockService, industryService, previous) {
            final provider = previous ?? MarketDataProvider(
              pool: pool,
              stockService: stockService,
              industryService: industryService,
            );
            // 首次创建时加载缓存
            if (previous == null) {
              provider.loadFromCache();
            }
            return provider;
          },
        ),
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
