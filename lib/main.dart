import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_checkpoint_store.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_monthly_writer.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/sw_industry_l1_mapping_store.dart';
import 'package:stock_rtwatcher/config/minute_sync_config.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/screens/main_screen.dart';
import 'package:stock_rtwatcher/services/tdx_client.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/daily_kline_read_service.dart';
import 'package:stock_rtwatcher/services/daily_kline_sync_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/services/holdings_service.dart';
import 'package:stock_rtwatcher/services/ai_analysis_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/tushare_token_service.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';
import 'package:stock_rtwatcher/services/sw_industry_index_mapping_service.dart';
import 'package:stock_rtwatcher/services/pullback_service.dart';
import 'package:stock_rtwatcher/services/backtest_service.dart';
import 'package:stock_rtwatcher/services/breakout_service.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';
import 'package:stock_rtwatcher/services/industry_buildup_service.dart';
import 'package:stock_rtwatcher/services/industry_rank_service.dart';
import 'package:stock_rtwatcher/services/industry_trend_service.dart';
import 'package:stock_rtwatcher/services/macd_indicator_service.dart';
import 'package:stock_rtwatcher/services/adx_indicator_service.dart';
import 'package:stock_rtwatcher/services/ema_indicator_service.dart';
import 'package:stock_rtwatcher/services/power_system_indicator_service.dart';
import 'package:stock_rtwatcher/services/industry_ema_breadth_service.dart';
import 'package:stock_rtwatcher/services/linked_layout_config_service.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/providers/sw_index_data_provider.dart';
import 'package:stock_rtwatcher/audit/services/audit_service.dart';
import 'package:stock_rtwatcher/theme/theme.dart';
import 'package:stock_rtwatcher/data/repository/tdx_pool_fetch_adapter.dart';
import 'package:stock_rtwatcher/data/repository/sw_index_repository.dart';

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
        Provider(create: (_) => DailyKlineCacheStore()),
        Provider(create: (_) => DailyKlineCheckpointStore()),
        Provider(create: (_) => EmaCacheStore()),
        ProxyProvider<DailyKlineCacheStore, DailyKlineReadService>(
          update: (_, cacheStore, __) =>
              DailyKlineReadService(cacheStore: cacheStore),
        ),
        ProxyProvider3<
          DailyKlineCheckpointStore,
          DailyKlineCacheStore,
          TdxPool,
          DailyKlineSyncService
        >(
          update: (_, checkpointStore, cacheStore, pool, __) {
            return DailyKlineSyncService(
              checkpointStore: checkpointStore,
              cacheStore: cacheStore,
              fetcher:
                  ({
                    required stocks,
                    required count,
                    required mode,
                    onProgress,
                  }) async {
                    final barsByCode = <String, List<KLine>>{};
                    var completed = 0;
                    await pool.batchGetSecurityBarsStreaming(
                      stocks: stocks,
                      category: klineTypeDaily,
                      start: 0,
                      count: count,
                      onStockBars: (index, bars) {
                        barsByCode[stocks[index].code] = bars;
                        completed++;
                        onProgress?.call(completed, stocks.length);
                      },
                    );
                    return barsByCode;
                  },
              monthlyWriter: DailyKlineMonthlyWriterImpl().call,
            );
          },
        ),
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
            final service = LinkedLayoutConfigService();
            service.load(); // 异步加载联动布局调试配置
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
            final service = TushareTokenService();
            service.load();
            return service;
          },
        ),
        Provider(create: (_) => SwIndustryL1MappingStore()),
        ProxyProvider<TushareTokenService, TushareClient>(
          update: (_, tokenService, __) {
            final token = tokenService.token;
            return TushareClient(
              token: (token == null || token.isEmpty) ? '__NO_TOKEN__' : token,
            );
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
        ProxyProvider<TushareClient, SwIndexRepository>(
          update: (_, client, __) {
            return SwIndexRepository(client: client);
          },
        ),
        ProxyProvider2<
          TushareClient,
          SwIndustryL1MappingStore,
          SwIndustryIndexMappingService
        >(
          update: (_, client, store, __) {
            return SwIndustryIndexMappingService(client: client, store: store);
          },
        ),
        ChangeNotifierProxyProvider<SwIndexRepository, SwIndexDataProvider>(
          create: (context) {
            return SwIndexDataProvider(
              repository: context.read<SwIndexRepository>(),
            );
          },
          update: (_, repository, __) {
            return SwIndexDataProvider(repository: repository);
          },
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
        ChangeNotifierProxyProvider<DataRepository, EmaIndicatorService>(
          create: (context) {
            final repository = context.read<DataRepository>();
            final service = EmaIndicatorService(repository: repository);
            service.load();
            return service;
          },
          update: (_, repository, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<
          DataRepository,
          PowerSystemIndicatorService
        >(
          create: (context) {
            final repository = context.read<DataRepository>();
            final emaService = context.read<EmaIndicatorService>();
            final macdService = context.read<MacdIndicatorService>();
            return PowerSystemIndicatorService(
              repository: repository,
              emaService: emaService,
              macdService: macdService,
            );
          },
          update: (_, repository, previous) => previous!,
        ),
        ProxyProvider3<
          IndustryService,
          DailyKlineCacheStore,
          EmaCacheStore,
          IndustryEmaBreadthService
        >(
          update:
              (_, industryService, dailyCacheStore, emaCacheStore, previous) {
                return IndustryEmaBreadthService(
                  industryService: industryService,
                  dailyCacheStore: dailyCacheStore,
                  emaCacheStore: emaCacheStore,
                );
              },
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
        ChangeNotifierProxyProvider6<
          StockService,
          IndustryService,
          PullbackService,
          BreakoutService,
          HistoricalKlineService,
          MacdIndicatorService,
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
            final emaService = context.read<EmaIndicatorService>();
            final powerSystemService = context
                .read<PowerSystemIndicatorService>();
            final industryEmaBreadthService = context
                .read<IndustryEmaBreadthService>();
            final dailyCacheStore = context.read<DailyKlineCacheStore>();
            final dailyCheckpointStore = context
                .read<DailyKlineCheckpointStore>();
            final dailyReadService = context.read<DailyKlineReadService>();
            final dailySyncService = context.read<DailyKlineSyncService>();
            breakoutService.setHistoricalKlineService(historicalKlineService);
            final provider = MarketDataProvider(
              pool: pool,
              stockService: stockService,
              industryService: industryService,
              dailyBarsFileStorage: dailyCacheStore,
              dailyKlineCheckpointStore: dailyCheckpointStore,
              dailyKlineReadService: dailyReadService,
              dailyKlineSyncService: dailySyncService,
            );
            provider.setPullbackService(pullbackService);
            provider.setBreakoutService(breakoutService);
            provider.setMacdService(macdService);
            provider.setAdxService(adxService);
            provider.setEmaService(emaService);
            provider.setPowerSystemService(powerSystemService);
            provider.setIndustryEmaBreadthService(industryEmaBreadthService);
            provider.loadFromCache();
            return provider;
          },
          update:
              (
                context,
                stockService,
                industryService,
                pullbackService,
                breakoutService,
                historicalKlineService,
                macdService,
                previous,
              ) {
                // IndustryEmaBreadthService may not be available on first update
                IndustryEmaBreadthService? industryEmaBreadthService;
                try {
                  industryEmaBreadthService = context
                      .read<IndustryEmaBreadthService>();
                } catch (_) {
                  // Service not yet available
                }
                final adxService = context.read<AdxIndicatorService>();
                final emaService = context.read<EmaIndicatorService>();
                final powerSystemService = context
                    .read<PowerSystemIndicatorService>();
                breakoutService.setHistoricalKlineService(
                  historicalKlineService,
                );
                previous!.setPullbackService(pullbackService);
                previous.setBreakoutService(breakoutService);
                previous.setMacdService(macdService);
                previous.setAdxService(adxService);
                previous.setEmaService(emaService);
                previous.setPowerSystemService(powerSystemService);
                if (industryEmaBreadthService != null) {
                  previous.setIndustryEmaBreadthService(
                    industryEmaBreadthService,
                  );
                }
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
