// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/screens/watchlist_screen.dart';
import 'package:stock_rtwatcher/screens/market_screen.dart';
import 'package:stock_rtwatcher/screens/industry_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _watchlistScreenKey = GlobalKey<WatchlistScreenState>();
  final _marketScreenKey = GlobalKey<MarketScreenState>();
  final _industryScreenKey = GlobalKey<IndustryScreenState>();

  /// 跳转到全市场并按行业搜索
  void _goToMarketAndSearchIndustry(String industry) {
    setState(() => _currentIndex = 1);
    // 延迟一帧确保 Tab 切换完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _marketScreenKey.currentState?.searchByIndustry(industry);
    });
  }

  /// 统一刷新：优先刷新自选股，然后刷新全市场和行业
  Future<void> _refreshAll() async {
    // 1. 优先刷新自选股
    await _watchlistScreenKey.currentState?.refresh();
    // 2. 然后并行刷新全市场和行业
    await Future.wait([
      _marketScreenKey.currentState?.refresh() ?? Future.value(),
      _industryScreenKey.currentState?.refresh() ?? Future.value(),
    ]);
  }

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      WatchlistScreen(
        key: _watchlistScreenKey,
        onIndustryTap: _goToMarketAndSearchIndustry,
        onRefresh: _refreshAll,
      ),
      MarketScreen(
        key: _marketScreenKey,
        onRefresh: _refreshAll,
      ),
      IndustryScreen(
        key: _industryScreenKey,
        onIndustryTap: _goToMarketAndSearchIndustry,
        onRefresh: _refreshAll,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: '自选',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: '全市场',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: '行业',
          ),
        ],
      ),
    );
  }
}
