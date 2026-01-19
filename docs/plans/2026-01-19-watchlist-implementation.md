# 自选股功能实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 A股涨跌量比监控 App 添加自选股功能，支持独立监控页面、全市场高亮、本地持久化

**Architecture:** 底部 Tab 导航（自选/全市场），WatchlistService 管理自选股状态，shared_preferences 持久化

**Tech Stack:** Flutter, Provider, shared_preferences

---

## Task 1: 添加 shared_preferences 依赖

**Files:**
- Modify: `pubspec.yaml`

**Step 1: 添加依赖**

```bash
flutter pub add shared_preferences
```

**Step 2: 验证依赖已添加**

Run: `flutter pub get`
Expected: 成功获取依赖

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add shared_preferences dependency"
```

---

## Task 2: 创建 WatchlistService

**Files:**
- Create: `lib/services/watchlist_service.dart`
- Test: `test/services/watchlist_service_test.dart`

**Step 1: 编写 WatchlistService 测试**

```dart
// test/services/watchlist_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';

void main() {
  group('WatchlistService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts with empty watchlist', () async {
      final service = WatchlistService();
      await service.load();
      expect(service.watchlist, isEmpty);
    });

    test('adds stock to watchlist', () async {
      final service = WatchlistService();
      await service.load();
      await service.addStock('000001');
      expect(service.watchlist, contains('000001'));
    });

    test('removes stock from watchlist', () async {
      final service = WatchlistService();
      await service.load();
      await service.addStock('000001');
      await service.removeStock('000001');
      expect(service.watchlist, isEmpty);
    });

    test('persists watchlist', () async {
      final service1 = WatchlistService();
      await service1.load();
      await service1.addStock('600519');

      final service2 = WatchlistService();
      await service2.load();
      expect(service2.watchlist, contains('600519'));
    });

    test('contains returns correct value', () async {
      final service = WatchlistService();
      await service.load();
      await service.addStock('000001');
      expect(service.contains('000001'), isTrue);
      expect(service.contains('000002'), isFalse);
    });

    test('validates stock code', () {
      expect(WatchlistService.isValidCode('000001'), isTrue);
      expect(WatchlistService.isValidCode('600519'), isTrue);
      expect(WatchlistService.isValidCode('300001'), isTrue);
      expect(WatchlistService.isValidCode('12345'), isFalse);
      expect(WatchlistService.isValidCode('abc123'), isFalse);
      expect(WatchlistService.isValidCode('900001'), isFalse);
    });

    test('getMarket returns correct market', () {
      expect(WatchlistService.getMarket('000001'), 0); // 深圳
      expect(WatchlistService.getMarket('300001'), 0); // 深圳创业板
      expect(WatchlistService.getMarket('600519'), 1); // 上海
      expect(WatchlistService.getMarket('688001'), 1); // 上海科创板
    });
  });
}
```

**Step 2: 运行测试验证失败**

Run: `flutter test test/services/watchlist_service_test.dart`
Expected: FAIL (文件不存在)

**Step 3: 实现 WatchlistService**

```dart
// lib/services/watchlist_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchlistService extends ChangeNotifier {
  static const _key = 'watchlist';
  List<String> _watchlist = [];

  List<String> get watchlist => List.unmodifiable(_watchlist);

  /// 从本地存储加载自选股列表
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _watchlist = prefs.getStringList(_key) ?? [];
    notifyListeners();
  }

  /// 添加股票到自选
  Future<void> addStock(String code) async {
    if (_watchlist.contains(code)) return;
    _watchlist.add(code);
    await _save();
    notifyListeners();
  }

  /// 从自选中移除股票
  Future<void> removeStock(String code) async {
    _watchlist.remove(code);
    await _save();
    notifyListeners();
  }

  /// 判断是否在自选中
  bool contains(String code) => _watchlist.contains(code);

  /// 保存到本地存储
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _watchlist);
  }

  /// 校验股票代码格式
  static bool isValidCode(String code) {
    if (code.length != 6) return false;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;
    // 深圳: 000/001/002/003/300/301, 上海: 600/601/603/605/688
    final validPrefixes = ['000', '001', '002', '003', '300', '301', '600', '601', '603', '605', '688'];
    return validPrefixes.any((p) => code.startsWith(p));
  }

  /// 根据代码获取市场 (0=深圳, 1=上海)
  static int getMarket(String code) {
    return code.startsWith('6') ? 1 : 0;
  }
}
```

**Step 4: 运行测试验证通过**

Run: `flutter test test/services/watchlist_service_test.dart`
Expected: All tests passed

**Step 5: Commit**

```bash
git add lib/services/watchlist_service.dart test/services/watchlist_service_test.dart
git commit -m "feat: add WatchlistService for watchlist management"
```

---

## Task 3: 创建 MainScreen (Tab 容器)

**Files:**
- Create: `lib/screens/main_screen.dart`
- Modify: `lib/main.dart`

**Step 1: 创建 MainScreen**

```dart
// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/screens/watchlist_screen.dart';
import 'package:stock_rtwatcher/screens/market_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final _screens = const [
    WatchlistScreen(),
    MarketScreen(),
  ];

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
        ],
      ),
    );
  }
}
```

**Step 2: 创建占位 WatchlistScreen**

```dart
// lib/screens/watchlist_screen.dart
import 'package:flutter/material.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(child: Text('自选股页面 (待实现)')),
    );
  }
}
```

**Step 3: 创建占位 MarketScreen**

```dart
// lib/screens/market_screen.dart
import 'package:flutter/material.dart';

class MarketScreen extends StatelessWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Center(child: Text('全市场页面 (待实现)')),
    );
  }
}
```

**Step 4: 更新 main.dart**

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/screens/main_screen.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
```

**Step 5: 运行验证 Tab 切换正常**

Run: `flutter run`
Expected: 底部 Tab 可正常切换

**Step 6: Commit**

```bash
git add lib/screens/main_screen.dart lib/screens/watchlist_screen.dart lib/screens/market_screen.dart lib/main.dart
git commit -m "feat: add MainScreen with bottom tab navigation"
```

---

## Task 4: 实现 WatchlistScreen

**Files:**
- Modify: `lib/screens/watchlist_screen.dart`

**Step 1: 实现完整的自选股页面**

```dart
// lib/screens/watchlist_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/stock.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _codeController = TextEditingController();
  List<StockMonitorData> _monitorData = [];
  String? _updateTime;
  bool _isLoading = false;
  bool _isConnected = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final watchlistService = context.read<WatchlistService>();
    await watchlistService.load();
    await _connect();
    if (_isConnected && watchlistService.watchlist.isNotEmpty) {
      await _fetchData();
      _startAutoRefresh();
    }
  }

  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final pool = context.read<TdxPool>();
    try {
      final success = await pool.autoConnect();
      setState(() {
        _isConnected = success;
        if (!success) _errorMessage = '无法连接到服务器';
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _errorMessage = '连接失败: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchData() async {
    final watchlistService = context.read<WatchlistService>();
    if (watchlistService.watchlist.isEmpty) {
      setState(() => _monitorData = []);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final stockService = context.read<StockService>();
    final pool = context.read<TdxPool>();

    try {
      // 构建 Stock 对象列表
      final stocks = <Stock>[];
      for (final code in watchlistService.watchlist) {
        final market = WatchlistService.getMarket(code);
        // 获取股票名称
        final stockList = await pool.getSecurityList(market, 0);
        final stock = stockList.firstWhere(
          (s) => s.code == code,
          orElse: () => Stock(code: code, name: code, market: market),
        );
        stocks.add(stock);
      }

      final data = await stockService.batchGetMonitorData(stocks);
      data.sort((a, b) => b.ratio.compareTo(a.ratio));

      setState(() {
        _monitorData = data;
        _updateTime = _formatTime();
      });
    } catch (e) {
      setState(() => _errorMessage = '获取数据失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _fetchData(),
    );
  }

  Future<void> _addStock() async {
    final code = _codeController.text.trim();
    if (!WatchlistService.isValidCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的股票代码')),
      );
      return;
    }

    final watchlistService = context.read<WatchlistService>();
    if (watchlistService.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该股票已在自选中')),
      );
      return;
    }

    await watchlistService.addStock(code);
    _codeController.clear();
    await _fetchData();
  }

  Future<void> _removeStock(String code, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除 $code $name？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final watchlistService = context.read<WatchlistService>();
      await watchlistService.removeStock(code);
      await _fetchData();
    }
  }

  void _copyCode(String code, String name) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: $code ($name)'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          StatusBar(
            updateTime: _updateTime,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
          ),
          // 添加股票输入框
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      hintText: '输入股票代码',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onSubmitted: (_) => _addStock(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addStock,
                  child: const Text('添加'),
                ),
              ],
            ),
          ),
          // 自选股列表
          Expanded(
            child: _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final watchlistService = context.watch<WatchlistService>();

    if (watchlistService.watchlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star_outline, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('暂无自选股', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('请在上方输入股票代码添加', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    if (_monitorData.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在获取数据...', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: ListView.builder(
        itemCount: _monitorData.length,
        itemBuilder: (context, index) {
          final data = _monitorData[index];
          final ratioColor = data.ratio >= 1 ? const Color(0xFFFF4444) : const Color(0xFF00AA00);

          return ListTile(
            leading: GestureDetector(
              onTap: () => _copyCode(data.stock.code, data.stock.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  data.stock.code,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
            title: Text(
              data.stock.name,
              style: TextStyle(color: data.stock.isST ? Colors.orange : null),
            ),
            trailing: Text(
              data.ratio.toStringAsFixed(2),
              style: TextStyle(
                color: ratioColor,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            onLongPress: () => _removeStock(data.stock.code, data.stock.name),
          );
        },
      ),
    );
  }
}
```

**Step 2: 运行验证自选股页面正常**

Run: `flutter run`
Expected: 能添加、删除自选股，显示量比数据

**Step 3: Commit**

```bash
git add lib/screens/watchlist_screen.dart
git commit -m "feat: implement WatchlistScreen with add/remove functionality"
```

---

## Task 5: 实现 MarketScreen

**Files:**
- Modify: `lib/screens/market_screen.dart`
- Modify: `lib/widgets/stock_table.dart` (添加高亮支持)

**Step 1: 修改 StockTable 支持高亮**

在 `lib/widgets/stock_table.dart` 中:

- 添加 `highlightCodes` 参数
- 自选股行使用 `Colors.amber.withOpacity(0.15)` 背景

**Step 2: 从 home_screen.dart 提取逻辑到 MarketScreen**

MarketScreen 基本复用 HomeScreen 的逻辑，但:
- 移除 `_displayCount` 限制，显示全部数据
- 不自动加载，需手动点击刷新
- 集成高亮自选股功能

**Step 3: 运行验证全市场页面正常**

Run: `flutter run`
Expected: 全市场显示全部股票，自选股高亮

**Step 4: Commit**

```bash
git add lib/screens/market_screen.dart lib/widgets/stock_table.dart
git commit -m "feat: implement MarketScreen with watchlist highlighting"
```

---

## Task 6: 清理和最终测试

**Files:**
- Delete: `lib/screens/home_screen.dart` (已被 market_screen 替代)

**Step 1: 删除旧的 home_screen.dart**

```bash
rm lib/screens/home_screen.dart
```

**Step 2: 运行全部测试**

Run: `flutter test`
Expected: All tests passed

**Step 3: 运行 flutter analyze**

Run: `flutter analyze`
Expected: No issues found

**Step 4: 最终验证**

Run: `flutter run`

验证:
- [ ] 启动后显示自选股页面
- [ ] 能添加自选股
- [ ] 能长按删除自选股
- [ ] 点击代码复制到剪贴板
- [ ] 切换到全市场 Tab
- [ ] 全市场手动刷新获取数据
- [ ] 全市场中自选股高亮显示
- [ ] 重启 App 自选股仍在

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: complete watchlist feature implementation"
```
