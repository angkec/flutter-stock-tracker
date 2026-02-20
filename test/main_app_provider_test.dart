import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/industry_ema_breadth_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';

void main() {
  testWidgets(
    'Provider tree wires IndustryEmaBreadthService into MarketDataProvider via MultiProvider',
    (WidgetTester tester) async {
      final industryService = IndustryService();
      final dailyCacheStore = DailyKlineCacheStore();
      final emaCacheStore = EmaCacheStore();
      final tdxPool = TdxPool(poolSize: 1);
      final widget = MultiProvider(
        providers: [
          Provider<IndustryService>.value(value: industryService),
          Provider<DailyKlineCacheStore>.value(value: dailyCacheStore),
          Provider<EmaCacheStore>.value(value: emaCacheStore),
          Provider<TdxPool>.value(value: tdxPool),
          ProxyProvider<TdxPool, StockService>(
            update: (_, pool, __) => StockService(pool),
          ),
          ProxyProvider3<
            IndustryService,
            DailyKlineCacheStore,
            EmaCacheStore,
            IndustryEmaBreadthService
          >(
            update: (_, industry, dailyCache, emaCache, __) {
              return IndustryEmaBreadthService(
                industryService: industry,
                dailyCacheStore: dailyCache,
                emaCacheStore: emaCache,
              );
            },
          ),
          ChangeNotifierProxyProvider3<
            StockService,
            IndustryService,
            IndustryEmaBreadthService,
            MarketDataProvider
          >(
            create: (context) {
              final provider = MarketDataProvider(
                pool: context.read<TdxPool>(),
                stockService: context.read<StockService>(),
                industryService: context.read<IndustryService>(),
                dailyBarsFileStorage: context.read<DailyKlineCacheStore>(),
              );
              provider.setIndustryEmaBreadthService(
                context.read<IndustryEmaBreadthService>(),
              );
              return provider;
            },
            update:
                (
                  context,
                  stockService,
                  industry,
                  industryEmaBreadthService,
                  previous,
                ) {
                  previous!.setIndustryEmaBreadthService(
                    industryEmaBreadthService,
                  );
                  return previous;
                },
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final providerFromTree = context
                  .read<IndustryEmaBreadthService>();
              final marketProviderFromTree = context.read<MarketDataProvider>();

              expect(
                marketProviderFromTree.industryEmaBreadthService,
                same(providerFromTree),
              );

              return const Scaffold(body: Text('verified'));
            },
          ),
        ),
      );

      await tester.pumpWidget(widget);
      await tester.pump();
    },
  );

  test(
    'MarketDataProvider setter and getter for IndustryEmaBreadthService work correctly',
    () {
      final industryService = IndustryService();
      final dailyCacheStore = DailyKlineCacheStore();
      final tdxPool = TdxPool(poolSize: 1);

      final provider = MarketDataProvider(
        pool: tdxPool,
        stockService: StockService(tdxPool),
        industryService: industryService,
        dailyBarsFileStorage: dailyCacheStore,
      );

      // Initially null
      expect(provider.industryEmaBreadthService, isNull);

      // After setting via setter (simulating main.dart wiring), should be accessible
      final industryEmaBreadthService = IndustryEmaBreadthService(
        industryService: industryService,
        dailyCacheStore: dailyCacheStore,
        emaCacheStore: EmaCacheStore(),
      );
      provider.setIndustryEmaBreadthService(industryEmaBreadthService);

      expect(provider.industryEmaBreadthService, isNotNull);
      expect(
        provider.industryEmaBreadthService,
        equals(industryEmaBreadthService),
      );
    },
  );
}
