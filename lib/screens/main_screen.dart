// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/screens/watchlist_screen.dart';
import 'package:stock_rtwatcher/screens/market_screen.dart';
import 'package:stock_rtwatcher/screens/industry_screen.dart';
import 'package:stock_rtwatcher/screens/breakout_screen.dart';
import 'package:stock_rtwatcher/theme/app_theme.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _marketScreenKey = GlobalKey<MarketScreenState>();

  /// 跳转到全市场并按行业搜索
  void _goToMarketAndSearchIndustry(String industry) {
    setState(() => _currentIndex = 1);
    // 延迟一帧确保 Tab 切换完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _marketScreenKey.currentState?.searchByIndustry(industry);
    });
  }

  late final List<Widget> _screens;

  /// 获取当前 Tab 对应的 AppTab 枚举
  AppTab get _currentTab {
    switch (_currentIndex) {
      case 0:
        return AppTab.watchlist;
      case 1:
        return AppTab.market;
      case 2:
        return AppTab.industry;
      case 3:
        return AppTab.breakout;
      default:
        return AppTab.market;
    }
  }

  @override
  void initState() {
    super.initState();
    _screens = [
      WatchlistScreen(onIndustryTap: _goToMarketAndSearchIndustry),
      MarketScreen(key: _marketScreenKey),
      IndustryScreen(onIndustryTap: _goToMarketAndSearchIndustry),
      BreakoutScreen(onIndustryTap: _goToMarketAndSearchIndustry),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tabTheme = AppTheme.forTab(_currentTab, brightness);

    return AnimatedTheme(
      data: tabTheme,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            body: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _currentIndex,
              indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  key: ValueKey<String>('nav_watchlist'),
                  icon: Icon(Icons.star_outline),
                  selectedIcon: Icon(Icons.star),
                  label: '自选',
                ),
                NavigationDestination(
                  key: ValueKey<String>('nav_market'),
                  icon: Icon(Icons.show_chart_outlined),
                  selectedIcon: Icon(Icons.show_chart),
                  label: '全市场',
                ),
                NavigationDestination(
                  key: ValueKey<String>('nav_industry'),
                  icon: Icon(Icons.category_outlined),
                  selectedIcon: Icon(Icons.category),
                  label: '行业',
                ),
                NavigationDestination(
                  key: ValueKey<String>('nav_breakout'),
                  icon: Icon(Icons.trending_up_outlined),
                  selectedIcon: Icon(Icons.trending_up),
                  label: '回踩',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
