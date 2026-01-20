# Shared Market Data Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 统一三个 tab 的数据到 MarketDataProvider，实现数据共享、优先加载自选股、渐进式更新、数据持久化。

**Architecture:** 创建 MarketDataProvider (ChangeNotifier) 作为共享数据中心，各 Screen 从 Provider 读取数据。刷新时自选股优先排序，每批数据到达后立即 notifyListeners() 实现渐进式更新。使用 SharedPreferences + JSON 持久化数据。

**Tech Stack:** Flutter, Dart, Provider, SharedPreferences

---

### Task 1: Add JSON serialization to Stock model

**Files:**
- Modify: `lib/models/stock.dart`

**Step 1: Add toJson and fromJson methods**

在 `Stock` class 末尾添加：

```dart
  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'market': market,
    'volUnit': volUnit,
    'decimalPoint': decimalPoint,
    'preClose': preClose,
  };

  factory Stock.fromJson(Map<String, dynamic> json) => Stock(
    code: json['code'] as String,
    name: json['name'] as String,
    market: json['market'] as int,
    volUnit: json['volUnit'] as int? ?? 100,
    decimalPoint: json['decimalPoint'] as int? ?? 2,
    preClose: (json['preClose'] as num?)?.toDouble() ?? 0.0,
  );
```

**Step 2: Run analyze**

Run: `flutter analyze lib/models/stock.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/models/stock.dart
git commit -m "feat: add JSON serialization to Stock model"
```

---

### Task 2: Add JSON serialization to StockMonitorData

**Files:**
- Modify: `lib/services/stock_service.dart`

**Step 1: Add toJson and fromJson methods to StockMonitorData**

在 `StockMonitorData` class 末尾（`});` 之后）添加：

```dart
  Map<String, dynamic> toJson() => {
    'stock': stock.toJson(),
    'ratio': ratio,
    'changePercent': changePercent,
    'industry': industry,
  };

  factory StockMonitorData.fromJson(Map<String, dynamic> json) => StockMonitorData(
    stock: Stock.fromJson(json['stock'] as Map<String, dynamic>),
    ratio: (json['ratio'] as num).toDouble(),
    changePercent: (json['changePercent'] as num).toDouble(),
    industry: json['industry'] as String?,
  );
```

**Step 2: Run analyze**

Run: `flutter analyze lib/services/stock_service.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/services/stock_service.dart
git commit -m "feat: add JSON serialization to StockMonitorData"
```

---

### Task 3: Create MarketDataProvider

**Files:**
- Create: `lib/providers/market_data_provider.dart`

**Step 1: Create the provider file**

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/tdx_pool.dart';
import 'package:stock_rtwatcher/services/industry_service.dart';

class MarketDataProvider extends ChangeNotifier {
  final TdxPool _pool;
  final StockService _stockService;
  final IndustryService _industryService;

  List<StockMonitorData> _allData = [];
  bool _isLoading = false;
  int _progress = 0;
  int _total = 0;
  String? _updateTime;
  String? _errorMessage;

  // Watchlist codes for priority sorting
  Set<String> _watchlistCodes = {};

  MarketDataProvider({
    required TdxPool pool,
    required StockService stockService,
    required IndustryService industryService,
  })  : _pool = pool,
        _stockService = stockService,
        _industryService = industryService;

  // Getters
  List<StockMonitorData> get allData => _allData;
  bool get isLoading => _isLoading;
  int get progress => _progress;
  int get total => _total;
  String? get updateTime => _updateTime;
  String? get errorMessage => _errorMessage;

  /// 设置自选股代码（用于优先排序）
  void setWatchlistCodes(Set<String> codes) {
    _watchlistCodes = codes;
  }

  /// 从缓存加载数据
  Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('market_data_cache');
      final timeStr = prefs.getString('market_data_time');

      if (jsonStr != null) {
        final List<dynamic> jsonList = json.decode(jsonStr);
        _allData = jsonList
            .map((e) => StockMonitorData.fromJson(e as Map<String, dynamic>))
            .toList();
        _updateTime = timeStr;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load cache: $e');
    }
  }

  /// 保存数据到缓存
  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _allData.map((e) => e.toJson()).toList();
      await prefs.setString('market_data_cache', json.encode(jsonList));
      if (_updateTime != null) {
        await prefs.setString('market_data_time', _updateTime!);
      }
    } catch (e) {
      debugPrint('Failed to save cache: $e');
    }
  }

  /// 刷新数据
  Future<void> refresh() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _progress = 0;
    _total = 0;
    notifyListeners();

    try {
      // 确保连接
      final connected = await _pool.ensureConnected();
      if (!connected) {
        _errorMessage = '无法连接到服务器';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 获取所有股票
      final stocks = await _stockService.getAllStocks();
      _total = stocks.length;
      notifyListeners();

      // 按自选股优先排序
      final prioritizedStocks = <Stock>[];
      final otherStocks = <Stock>[];
      for (final stock in stocks) {
        if (_watchlistCodes.contains(stock.code)) {
          prioritizedStocks.add(stock);
        } else {
          otherStocks.add(stock);
        }
      }
      final orderedStocks = [...prioritizedStocks, ...otherStocks];

      // 清空旧数据，准备渐进式更新
      _allData = [];

      // 批量获取数据（渐进式更新）
      await _stockService.batchGetMonitorData(
        orderedStocks,
        industryService: _industryService,
        onProgress: (current, total) {
          _progress = current;
          _total = total;
          notifyListeners();
        },
        onData: (results) {
          _allData = results;
          notifyListeners();
        },
      );

      // 更新时间
      final now = DateTime.now();
      _updateTime = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      _isLoading = false;
      _progress = 0;
      _total = 0;
      notifyListeners();

      // 保存到缓存
      await _saveToCache();
    } catch (e) {
      _errorMessage = '获取数据失败: $e';
      _isLoading = false;
      _progress = 0;
      _total = 0;
      notifyListeners();
    }
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/providers/market_data_provider.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/providers/market_data_provider.dart
git commit -m "feat: create MarketDataProvider for shared market data"
```

---

### Task 4: Register MarketDataProvider in main.dart

**Files:**
- Modify: `lib/main.dart`

**Step 1: Add import**

在文件顶部添加：

```dart
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
```

**Step 2: Add MarketDataProvider to providers list**

将 providers 列表改为：

```dart
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
```

**Step 3: Run analyze**

Run: `flutter analyze lib/main.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: register MarketDataProvider in main.dart"
```

---

### Task 5: Update StatusBar to read from Provider

**Files:**
- Modify: `lib/widgets/status_bar.dart`

**Step 1: Add provider import**

在文件顶部添加：

```dart
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
```

**Step 2: Change StatusBar to read from Provider**

将整个 `StatusBar` class 替换为：

```dart
/// 状态栏组件
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MarketDataProvider>();
    final marketStatus = getCurrentMarketStatus();
    final statusColor = getMarketStatusColor(marketStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 400;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行: 标题 + 状态 + 时间 + 刷新/进度
              Row(
                children: [
                  // 市场状态指示点
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 标题
                  Text(
                    isNarrow ? '涨跌量比' : 'A股涨跌量比监控',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  // 更新时间
                  if (provider.updateTime != null && !provider.isLoading)
                    Text(
                      provider.updateTime!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                    ),
                  const SizedBox(width: 8),
                  // 右上角：刷新按钮 或 进度指示器
                  _buildRefreshArea(context, provider),
                ],
              ),
              // 第二行: 错误信息
              if (provider.errorMessage != null && !provider.isLoading) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        provider.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRefreshArea(BuildContext context, MarketDataProvider provider) {
    if (provider.isLoading) {
      // 加载中：显示小进度指示器 + 数字
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          if (provider.total > 0) ...[
            const SizedBox(width: 6),
            Text(
              '${provider.progress}/${provider.total}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
            ),
          ],
        ],
      );
    } else if (provider.errorMessage != null) {
      // 错误：显示红色重试按钮
      return SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: () => provider.refresh(),
          icon: Icon(
            Icons.refresh,
            size: 20,
            color: Theme.of(context).colorScheme.error,
          ),
          tooltip: '重试',
        ),
      );
    } else {
      // 空闲：显示刷新按钮
      return SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: () => provider.refresh(),
          icon: const Icon(Icons.refresh, size: 20),
          tooltip: '刷新数据',
        ),
      );
    }
  }
}
```

**Step 3: Run analyze**

Run: `flutter analyze lib/widgets/status_bar.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/widgets/status_bar.dart
git commit -m "feat: update StatusBar to read from MarketDataProvider"
```

---

### Task 6: Simplify WatchlistScreen

**Files:**
- Modify: `lib/screens/watchlist_screen.dart`

**Step 1: Add provider import**

在 imports 中添加：

```dart
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
```

**Step 2: Replace the entire file content**

```dart
// lib/screens/watchlist_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';

class WatchlistScreen extends StatefulWidget {
  final void Function(String industry)? onIndustryTap;

  const WatchlistScreen({super.key, this.onIndustryTap});

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen> {
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 初始化时同步自选股代码到 MarketDataProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWatchlistCodes();
    });
  }

  void _syncWatchlistCodes() {
    final watchlistService = context.read<WatchlistService>();
    final marketProvider = context.read<MarketDataProvider>();
    marketProvider.setWatchlistCodes(watchlistService.watchlist.toSet());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _addStock() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    final watchlistService = context.read<WatchlistService>();
    if (!WatchlistService.isValidCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无效的股票代码')),
      );
      return;
    }

    if (watchlistService.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该股票已在自选列表中')),
      );
      return;
    }

    watchlistService.add(code);
    _codeController.clear();
    _syncWatchlistCodes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加 $code')),
    );
  }

  void _removeStock(String code) {
    final watchlistService = context.read<WatchlistService>();
    watchlistService.remove(code);
    _syncWatchlistCodes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已移除 $code')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlistService = context.watch<WatchlistService>();
    final marketProvider = context.watch<MarketDataProvider>();

    // 从共享数据中过滤自选股
    final watchlistData = marketProvider.allData
        .where((d) => watchlistService.contains(d.stock.code))
        .toList();

    return SafeArea(
      child: Column(
        children: [
          const StatusBar(),
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
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            child: watchlistData.isEmpty
                ? _buildEmptyState(watchlistService)
                : RefreshIndicator(
                    onRefresh: () => marketProvider.refresh(),
                    child: StockTable(
                      stocks: watchlistData,
                      isLoading: marketProvider.isLoading,
                      onTap: (data) => _removeStock(data.stock.code),
                      onIndustryTap: widget.onIndustryTap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(WatchlistService watchlistService) {
    if (watchlistService.watchlist.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_outline,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无自选股',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '在上方输入股票代码添加',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.refresh,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '点击刷新按钮获取数据',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }
  }
}
```

**Step 3: Run analyze**

Run: `flutter analyze lib/screens/watchlist_screen.dart`
Expected: No issues found

**Step 4: Commit**

```bash
git add lib/screens/watchlist_screen.dart
git commit -m "feat: simplify WatchlistScreen to use MarketDataProvider"
```

---

### Task 7: Simplify MarketScreen

**Files:**
- Modify: `lib/screens/market_screen.dart`

**Step 1: Replace the entire file content**

```dart
// lib/screens/market_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/watchlist_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';
import 'package:stock_rtwatcher/widgets/stock_table.dart';
import 'package:stock_rtwatcher/widgets/market_stats_bar.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => MarketScreenState();
}

class MarketScreenState extends State<MarketScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 供外部调用：设置搜索框为指定行业
  void searchByIndustry(String industry) {
    _searchController.text = industry;
    setState(() => _searchQuery = industry);
  }

  void _addToWatchlist(String code, String name) {
    final watchlistService = context.read<WatchlistService>();
    final marketProvider = context.read<MarketDataProvider>();

    if (watchlistService.contains(code)) {
      watchlistService.remove(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从自选移除 $name ($code)')),
      );
    } else {
      watchlistService.add(code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加到自选 $name ($code)')),
      );
    }
    // 同步自选股代码
    marketProvider.setWatchlistCodes(watchlistService.watchlist.toSet());
  }

  @override
  Widget build(BuildContext context) {
    final watchlistService = context.watch<WatchlistService>();
    final marketProvider = context.watch<MarketDataProvider>();

    // 过滤数据
    final filteredData = _searchQuery.isEmpty
        ? marketProvider.allData
        : marketProvider.allData.where((d) {
            final query = _searchQuery.toLowerCase();
            return d.stock.code.contains(query) ||
                d.stock.name.toLowerCase().contains(query) ||
                (d.industry?.toLowerCase().contains(query) ?? false);
          }).toList();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const StatusBar(),
                // 搜索框
                if (marketProvider.allData.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: '搜索代码、名称或行业',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 68),
                    child: RefreshIndicator(
                      onRefresh: () => marketProvider.refresh(),
                      child: StockTable(
                        stocks: filteredData,
                        isLoading: marketProvider.isLoading,
                        highlightCodes: watchlistService.watchlist.toSet(),
                        onTap: (data) => _addToWatchlist(data.stock.code, data.stock.name),
                        onIndustryTap: searchByIndustry,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // 底部统计条
            if (filteredData.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MarketStatsBar(stocks: filteredData),
              ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/screens/market_screen.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/screens/market_screen.dart
git commit -m "feat: simplify MarketScreen to use MarketDataProvider"
```

---

### Task 8: Simplify IndustryScreen

**Files:**
- Modify: `lib/screens/industry_screen.dart`

**Step 1: Replace the entire file content**

```dart
// lib/screens/industry_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stock_rtwatcher/models/industry_stats.dart';
import 'package:stock_rtwatcher/providers/market_data_provider.dart';
import 'package:stock_rtwatcher/services/stock_service.dart';
import 'package:stock_rtwatcher/widgets/status_bar.dart';

class IndustryScreen extends StatelessWidget {
  final void Function(String industry)? onIndustryTap;

  const IndustryScreen({super.key, this.onIndustryTap});

  /// 计算行业统计
  List<IndustryStats> _calculateStats(List<StockMonitorData> data) {
    final Map<String, List<StockMonitorData>> grouped = {};

    for (final stock in data) {
      final industry = stock.industry ?? '未知';
      grouped.putIfAbsent(industry, () => []).add(stock);
    }

    final result = <IndustryStats>[];
    for (final entry in grouped.entries) {
      int up = 0, down = 0, flat = 0, ratioAbove = 0, ratioBelow = 0;

      for (final stock in entry.value) {
        // 涨跌统计
        if (stock.changePercent > 0.001) {
          up++;
        } else if (stock.changePercent < -0.001) {
          down++;
        } else {
          flat++;
        }
        // 量比统计
        if (stock.ratio >= 1.0) {
          ratioAbove++;
        } else {
          ratioBelow++;
        }
      }

      result.add(IndustryStats(
        name: entry.key,
        upCount: up,
        downCount: down,
        flatCount: flat,
        ratioAbove: ratioAbove,
        ratioBelow: ratioBelow,
      ));
    }

    // 按量比排序值降序
    result.sort((a, b) => b.ratioSortValue.compareTo(a.ratioSortValue));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final marketProvider = context.watch<MarketDataProvider>();
    final stats = _calculateStats(marketProvider.allData);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            Expanded(
              child: stats.isEmpty && !marketProvider.isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无数据',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击刷新按钮获取数据',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // 表头
                        Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 64,
                                child: Text(
                                  '行业',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '涨跌',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '量比',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () => marketProvider.refresh(),
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: stats.length,
                              itemExtent: 48,
                              itemBuilder: (context, index) =>
                                  _buildRow(context, stats[index], index),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, IndustryStats stats, int index) {
    const upColor = Color(0xFFFF4444);
    const downColor = Color(0xFF00AA00);

    return GestureDetector(
      onTap: onIndustryTap != null ? () => onIndustryTap!(stats.name) : null,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: index.isOdd
              ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            // 行业名
            SizedBox(
              width: 64,
              child: Text(
                stats.name,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 涨跌进度条 + 数字
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Row(
                        children: [
                          if (stats.upCount > 0)
                            Expanded(
                              flex: stats.upCount,
                              child: Container(height: 6, color: upColor),
                            ),
                          if (stats.downCount > 0)
                            Expanded(
                              flex: stats.downCount,
                              child: Container(height: 6, color: downColor),
                            ),
                          if (stats.upCount == 0 && stats.downCount == 0)
                            Expanded(
                              child: Container(
                                height: 6,
                                color: Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.upCount}↑ ${stats.downCount}↓',
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // 量比进度条 + 数字
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Row(
                        children: [
                          if (stats.ratioAbove > 0)
                            Expanded(
                              flex: stats.ratioAbove,
                              child: Container(height: 6, color: upColor),
                            ),
                          if (stats.ratioBelow > 0)
                            Expanded(
                              flex: stats.ratioBelow,
                              child: Container(height: 6, color: downColor),
                            ),
                          if (stats.ratioAbove == 0 && stats.ratioBelow == 0)
                            Expanded(
                              child: Container(
                                height: 6,
                                color: Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${stats.ratioAbove}↑ ${stats.ratioBelow}↓',
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze lib/screens/industry_screen.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/screens/industry_screen.dart
git commit -m "feat: simplify IndustryScreen to use MarketDataProvider"
```

---

### Task 9: Simplify MainScreen

**Files:**
- Modify: `lib/screens/main_screen.dart`

**Step 1: Replace the entire file content**

```dart
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

  @override
  void initState() {
    super.initState();
    _screens = [
      WatchlistScreen(onIndustryTap: _goToMarketAndSearchIndustry),
      MarketScreen(key: _marketScreenKey),
      IndustryScreen(onIndustryTap: _goToMarketAndSearchIndustry),
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
```

**Step 2: Run analyze**

Run: `flutter analyze lib/screens/main_screen.dart`
Expected: No issues found

**Step 3: Commit**

```bash
git add lib/screens/main_screen.dart
git commit -m "feat: simplify MainScreen, remove centralized refresh"
```

---

### Task 10: Run All Tests and Manual Verification

**Step 1: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 2: Run the app**

Run: `flutter run -d macos`

**Step 3: Verify functionality**

1. App 启动时显示缓存数据（如有）
2. 点击刷新按钮，自选股数据最先显示
3. 进度条在右上角显示 "123/5000" 格式
4. 数据渐进式更新，三个 tab 同步更新
5. 切换 tab 时数据共享，不重新请求
6. 刷新完成后，关闭重启 app，数据仍在

**Step 4: Final commit**

```bash
git commit --allow-empty -m "test: verified shared market data feature"
```

---

## Summary

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Add JSON to Stock | `feat: add JSON serialization to Stock model` |
| 2 | Add JSON to StockMonitorData | `feat: add JSON serialization to StockMonitorData` |
| 3 | Create MarketDataProvider | `feat: create MarketDataProvider for shared market data` |
| 4 | Register Provider | `feat: register MarketDataProvider in main.dart` |
| 5 | Update StatusBar | `feat: update StatusBar to read from MarketDataProvider` |
| 6 | Simplify WatchlistScreen | `feat: simplify WatchlistScreen to use MarketDataProvider` |
| 7 | Simplify MarketScreen | `feat: simplify MarketScreen to use MarketDataProvider` |
| 8 | Simplify IndustryScreen | `feat: simplify IndustryScreen to use MarketDataProvider` |
| 9 | Simplify MainScreen | `feat: simplify MainScreen, remove centralized refresh` |
| 10 | Manual verification | `test: verified shared market data feature` |
