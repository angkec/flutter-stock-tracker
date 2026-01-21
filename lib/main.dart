import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/screens/main_screen.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
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
        ChangeNotifierProvider(create: (_) {
          final service = WatchlistService();
          service.load(); // 异步加载自选股列表
          return service;
        }),
        ChangeNotifierProvider(create: (_) {
          final service = PullbackService();
          service.load(); // 异步加载回踩配置
          return service;
        }),
        ChangeNotifierProxyProvider4<TdxPool, StockService, IndustryService, PullbackService, MarketDataProvider>(
          create: (context) {
            final pool = context.read<TdxPool>();
            final stockService = context.read<StockService>();
            final industryService = context.read<IndustryService>();
            final pullbackService = context.read<PullbackService>();
            final provider = MarketDataProvider(
              pool: pool,
              stockService: stockService,
              industryService: industryService,
            );
            provider.setPullbackService(pullbackService);
            provider.loadFromCache();
            return provider;
          },
          update: (_, pool, stockService, industryService, pullbackService, previous) {
            previous!.setPullbackService(pullbackService);
            return previous;
          },
        ),
      ],
      child: MaterialApp(
        title: '盯喵',
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
