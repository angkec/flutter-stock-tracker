import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/config/minute_sync_config.dart';
import 'package:stock_rtwatcher/screens/main_screen.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/holdings_service.dart';
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/backtest_service.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/audit/services/audit_service.dart';
import 'package:stock_rtwatcher/theme/theme.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS || Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(
          create: (_) {
            final service = IndustryService();
            service.load(); // 异步加载，不阻塞启动
            return service;
          },
        ),
        Provider(create: (_) => TdxPool(poolSize: 12)),
        ProxyProvider<TdxPool, StockService>(
          update: (_, pool, __) => StockService(pool),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = WatchlistService();
            service.load(); // 异步加载自选股列表
            return service;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = HoldingsService();
            service.load();
            return service;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = AIAnalysisService();
            service.load(); // 异步加载 API Key
            return service;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = PullbackService();
            service.load(); // 异步加载回踩配置
            return service;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = BreakoutService();
            service.load(); // 异步加载突破配置
            return service;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = IndustryTrendService();
            service.load(); // 异步加载行业趋势缓存
            return service;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = IndustryRankService();
            service.load(); // 异步加载排名缓存
            return service;
          },
        ),
        // DataRepository must be created before HistoricalKlineService
        Provider<DataRepository>(
          create: (context) {
            final pool = context.read<TdxPool>();
            final poolAdapter = TdxPoolFetchAdapter(pool: pool);
            return MarketDataRepository(
              minuteFetchAdapter: poolAdapter,
              klineFetchAdapter: poolAdapter,
              minuteSyncConfig: const MinuteSyncConfig(
                enablePoolMinutePipeline: true,
                enableMinutePipelineLogs: false,
                minutePipelineFallbackToLegacyOnError: true,
                poolBatchCount: 800,
                poolMaxBatches: 10,
                minuteWriteConcurrency: 6,
              ),
            );
          },
          dispose: (_, repo) => repo.dispose(),
        ),
        ChangeNotifierProxyProvider2<
          DataRepository,
          IndustryService,
          IndustryBuildUpService
        >(
          create: (context) {
            final repository = context.read<DataRepository>();
            final industryService = context.read<IndustryService>();
            final service = IndustryBuildUpService(
              repository: repository,
              industryService: industryService,
            );
            service.load();
            return service;
          },
          update: (_, repository, industryService, previous) {
            if (previous != null) {
              return previous;
            }
            final service = IndustryBuildUpService(
              repository: repository,
              industryService: industryService,
            );
            service.load();
            return service;
          },
        ),
        ChangeNotifierProxyProvider<DataRepository, HistoricalKlineService>(
          create: (context) {
            final repository = context.read<DataRepository>();
            return HistoricalKlineService(repository: repository);
          },
          update: (_, repository, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<DataRepository, MacdIndicatorService>(
          create: (context) {
            final repository = context.read<DataRepository>();
            final service = MacdIndicatorService(repository: repository);
            service.load();
            return service;
          },
          update: (_, repository, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<DataRepository, AdxIndicatorService>(
          create: (context) {
            final repository = context.read<DataRepository>();
            final service = AdxIndicatorService(repository: repository);
            service.load();
            return service;
          },
          update: (_, repository, previous) => previous!,
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = BacktestService();
            service.loadConfig(); // 异步加载回测配置
            return service;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final service = AuditService();
            service.refreshLatest();
            return service;
          },
        ),
        ChangeNotifierProxyProvider7<
          StockService,
          IndustryService,
          PullbackService,
          BreakoutService,
          HistoricalKlineService,
          MacdIndicatorService,
          AdxIndicatorService,
          MarketDataProvider
        >(
          create: (context) {
            final pool = context.read<TdxPool>();
            final stockService = context.read<StockService>();
            final industryService = context.read<IndustryService>();
            final pullbackService = context.read<PullbackService>();
            final breakoutService = context.read<BreakoutService>();
            final historicalKlineService = context
                .read<HistoricalKlineService>();
            final macdService = context.read<MacdIndicatorService>();
            final adxService = context.read<AdxIndicatorService>();
            breakoutService.setHistoricalKlineService(historicalKlineService);
            final provider = MarketDataProvider(
              pool: pool,
              stockService: stockService,
              industryService: industryService,
              dailyBarsFileStorage: DailyKlineCacheStore(),
            );
            provider.setPullbackService(pullbackService);
            provider.setBreakoutService(breakoutService);
            provider.setMacdService(macdService);
            provider.setAdxService(adxService);
            provider.loadFromCache();
            return provider;
          },
          update:
              (
                _,
                stockService,
                industryService,
                pullbackService,
                breakoutService,
                historicalKlineService,
                macdService,
                adxService,
                previous,
              ) {
                breakoutService.setHistoricalKlineService(
                  historicalKlineService,
                );
                previous!.setPullbackService(pullbackService);
                previous.setBreakoutService(breakoutService);
                previous.setMacdService(macdService);
                previous.setAdxService(adxService);
                return previous;
              },
        ),
      ],
      child: MaterialApp(
        title: '盯喵',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const MainScreen(),
      ),
    );
  }
}
