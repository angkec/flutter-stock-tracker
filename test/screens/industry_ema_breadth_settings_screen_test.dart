import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/data/storage/daily_kline_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/ema_cache_store.dart';
import 'package:stock_rtwatcher/data/storage/industry_ema_breadth_config_store.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth_config.dart';
import 'package:stock_rtwatcher/models/industry_ema_breadth.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/screens/industry_ema_breadth_settings_screen.dart';
import 'package:stock_rtwatcher/services/industry_ema_breadth_service.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';

class _FakeIndustryEmaBreadthConfigStore extends IndustryEmaBreadthConfigStore {
  _FakeIndustryEmaBreadthConfigStore(this._config);

  IndustryEmaBreadthConfig _config;
  int saveCount = 0;

  @override
  Future<IndustryEmaBreadthConfig> load({
    IndustryEmaBreadthConfig? defaults,
  }) async {
    return _config;
  }

  @override
  Future<void> save(IndustryEmaBreadthConfig config) async {
    _config = config;
    saveCount++;
  }

  IndustryEmaBreadthConfig get latest => _config;
}

class _FakeIndustryEmaBreadthService extends IndustryEmaBreadthService {
  _FakeIndustryEmaBreadthService()
    : super(
        industryService: IndustryService(),
        dailyCacheStore: DailyKlineCacheStore(),
        emaCacheStore: EmaCacheStore(),
      );

  int recomputeCount = 0;
  Duration recomputeDelay = Duration.zero;

  @override
  Future<Map<String, IndustryEmaBreadthSeries>> recomputeAllIndustries({
    required DateTime startDate,
    required DateTime endDate,
    void Function(int current, int total, String stage)? onProgress,
  }) async {
    recomputeCount++;
    onProgress?.call(1, 1, '重算完成');
    if (recomputeDelay > Duration.zero) {
      await Future<void>.delayed(recomputeDelay);
    }
    return <String, IndustryEmaBreadthSeries>{};
  }
}

class _FakeMarketDataProvider extends MarketDataProvider {
  _FakeMarketDataProvider({required IndustryEmaBreadthService breadthService})
    : super(
        pool: TdxPool(poolSize: 1),
        stockService: StockService(TdxPool(poolSize: 1)),
        industryService: IndustryService(),
      ) {
    setIndustryEmaBreadthService(breadthService);
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeIndustryEmaBreadthConfigStore store,
  required _FakeIndustryEmaBreadthService service,
}) async {
  final provider = _FakeMarketDataProvider(breadthService: service);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MarketDataProvider>.value(value: provider),
      ],
      child: MaterialApp(
        home: IndustryEmaBreadthSettingsScreen(
          configStoreForTest: store,
          serviceForTest: service,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads thresholds from config store', (tester) async {
    final store = _FakeIndustryEmaBreadthConfigStore(
      const IndustryEmaBreadthConfig(upperThreshold: 80, lowerThreshold: 20),
    );
    final service = _FakeIndustryEmaBreadthService();

    await _pumpScreen(tester, store: store, service: service);

    expect(find.text('80'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
  });

  testWidgets('invalid threshold input shows error and does not save', (
    tester,
  ) async {
    final store = _FakeIndustryEmaBreadthConfigStore(
      IndustryEmaBreadthConfig.defaultConfig,
    );
    final service = _FakeIndustryEmaBreadthService();

    await _pumpScreen(tester, store: store, service: service);

    await tester.enterText(
      find.byKey(const ValueKey('industry_ema_upper')),
      '20',
    );
    await tester.enterText(
      find.byKey(const ValueKey('industry_ema_lower')),
      '30',
    );
    await tester.tap(find.byKey(const ValueKey('industry_ema_save')));
    await tester.pump();

    expect(find.textContaining('0<=lower<upper<=100'), findsOneWidget);
    expect(store.saveCount, 0);
  });

  testWidgets('save updates config only and does not trigger recompute', (
    tester,
  ) async {
    final store = _FakeIndustryEmaBreadthConfigStore(
      IndustryEmaBreadthConfig.defaultConfig,
    );
    final service = _FakeIndustryEmaBreadthService();

    await _pumpScreen(tester, store: store, service: service);

    await tester.enterText(
      find.byKey(const ValueKey('industry_ema_upper')),
      '78',
    );
    await tester.enterText(
      find.byKey(const ValueKey('industry_ema_lower')),
      '22',
    );
    await tester.tap(find.byKey(const ValueKey('industry_ema_save')));
    await tester.pumpAndSettle();

    expect(store.latest.upperThreshold, 78);
    expect(store.latest.lowerThreshold, 22);
    expect(service.recomputeCount, 0);
  });

  testWidgets('manual recompute button runs recompute flow', (tester) async {
    final store = _FakeIndustryEmaBreadthConfigStore(
      IndustryEmaBreadthConfig.defaultConfig,
    );
    final service = _FakeIndustryEmaBreadthService();

    await _pumpScreen(tester, store: store, service: service);

    await tester.tap(find.byKey(const ValueKey('industry_ema_recompute')));
    await tester.pumpAndSettle();

    expect(service.recomputeCount, 1);
  });

  testWidgets('manual recompute dialog shows text progress information', (
    tester,
  ) async {
    final store = _FakeIndustryEmaBreadthConfigStore(
      IndustryEmaBreadthConfig.defaultConfig,
    );
    final service = _FakeIndustryEmaBreadthService()
      ..recomputeDelay = const Duration(milliseconds: 120);

    await _pumpScreen(tester, store: store, service: service);

    await tester.tap(find.byKey(const ValueKey('industry_ema_recompute')));
    await tester.pump();

    expect(find.textContaining('已处理'), findsOneWidget);
    expect(find.textContaining('重算完成'), findsOneWidget);

    await tester.pumpAndSettle();
  });
}
