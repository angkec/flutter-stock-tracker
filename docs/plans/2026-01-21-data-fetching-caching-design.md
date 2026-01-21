# Data Fetching & Caching Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Improve data fetching with incremental updates, persistent caching, unified refresh entry, and clear progress indication.

**Problems Solved:**
1. 日K数据重启后丢失 → 持久化缓存
2. 刷新耗时长 → 增量拉取
3. 多处触发刷新 → 统一入口 + 数据管理页

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    UI Layer                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │ RefreshStatus│  │ DataManage │  │  Screens    │  │
│  │  (顶栏)      │  │   Screen   │  │             │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
└─────────┼────────────────┼────────────────┼─────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────┐
│              MarketDataProvider                      │
│  ┌─────────────────────────────────────────────┐    │
│  │ refresh() - 唯一刷新入口                      │    │
│  │ - fetchMinuteData (增量)                     │    │
│  │ - updateDailyBars (增量)                     │    │
│  │ - runAnalysis                               │    │
│  │ - persistCache                              │    │
│  └─────────────────────────────────────────────┘    │
│  RefreshStage: idle | fetchMinuteData |             │
│                updateDailyBars | analyzing | error  │
└─────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────┐
│              SharedPreferences                       │
│  - daily_bars_cache_v1 (日K缓存)                     │
│  - minute_data_cache_v1 (分时缓存)                   │
│  - minute_data_date (分时缓存日期)                   │
│  - last_fetch_date (上次拉取日期)                    │
└─────────────────────────────────────────────────────┘
```

---

## 2. Incremental Fetching Strategy

### 分时数据 (Minute Data)
- **首次拉取**: 全量 240 条
- **后续拉取**: 仅拉取上次时间戳之后的新数据
- **合并策略**: 追加到已有数据末尾

### 日K数据 (Daily Bars)
- **首次拉取**: 15 天数据
- **后续拉取**: 仅拉取 1 天新数据
- **每日首次**: 用完整昨日数据覆盖缓存中的昨日数据

### 判断逻辑

```dart
bool _isFirstFetchToday() {
  final today = DateTime.now().toString().substring(0, 10);
  return _lastFetchDate != today;
}

// 分时增量判断
int _getMinuteDataStartIndex(String stockCode) {
  final cached = _minuteDataCache[stockCode];
  if (cached == null || cached.isEmpty) return 0;
  return cached.length; // 从已有数量开始
}

// 日K增量判断
int _getDailyBarsToFetch(String stockCode) {
  final cached = _dailyBarsCache[stockCode];
  if (cached == null || cached.isEmpty) return 15; // 首次全量
  if (_isFirstFetchToday()) return 2; // 昨日+今日
  return 1; // 仅今日
}
```

---

## 3. Progress Display & State Management

### Refresh Stage Enum

```dart
enum RefreshStage {
  idle,           // 空闲
  fetchMinuteData, // 拉取分时数据
  updateDailyBars, // 更新日K数据
  analyzing,       // 分析计算
  error,          // 错误
}
```

### State Fields

```dart
// MarketDataProvider 新增字段
RefreshStage _stage = RefreshStage.idle;
String? _stageDescription;  // "拉取分时 32/156"
int _stageProgress = 0;     // 当前进度
int _stageTotal = 0;        // 总数
bool _isRefreshing = false;
String? _lastUpdateTime;    // "09:35:12"
String? _lastFetchDate;     // "2026-01-21"

// Getters
RefreshStage get stage => _stage;
String? get stageDescription => _stageDescription;
bool get isRefreshing => _isRefreshing;
String? get lastUpdateTime => _lastUpdateTime;
```

### Progress Update

```dart
void _updateProgress(RefreshStage stage, int current, int total) {
  _stage = stage;
  _stageProgress = current;
  _stageTotal = total;
  _stageDescription = _formatStageDescription(stage, current, total);
  notifyListeners();
}

String _formatStageDescription(RefreshStage stage, int current, int total) {
  switch (stage) {
    case RefreshStage.fetchMinuteData:
      return '拉取分时 $current/$total';
    case RefreshStage.updateDailyBars:
      return '更新日K $current/$total';
    case RefreshStage.analyzing:
      return '分析计算...';
    case RefreshStage.error:
      return _stageDescription ?? '刷新失败';
    default:
      return '';
  }
}
```

---

## 4. Cache Persistence Implementation

### Storage Format

```dart
// 缓存键
static const String _dailyBarsCacheKey = 'daily_bars_cache_v1';
static const String _lastFetchDateKey = 'last_fetch_date';

// 存储格式: Map<String, List<Map>>
// key = stockCode, value = list of bar data
{
  "sh600000": [
    {"date": "2026-01-20", "open": 10.5, "high": 11.0, "low": 10.2, "close": 10.8, "volume": 1000000},
    {"date": "2026-01-21", "open": 10.8, ...}
  ],
  "sz000001": [...]
}
```

### Load on Startup

```dart
Future<void> loadFromCache() async {
  final prefs = await SharedPreferences.getInstance();

  // 加载日K缓存
  final dailyJson = prefs.getString(_dailyBarsCacheKey);
  if (dailyJson != null) {
    try {
      final Map<String, dynamic> data = jsonDecode(dailyJson);
      _dailyBarsCache = data.map((k, v) => MapEntry(
        k,
        (v as List).map((e) => BarData.fromJson(e)).toList()
      ));
    } catch (e) {
      // 缓存损坏，清空
      await prefs.remove(_dailyBarsCacheKey);
    }
  }

  // 加载上次拉取日期
  _lastFetchDate = prefs.getString(_lastFetchDateKey);
}
```

### Save After Update

```dart
Future<void> _persistDailyBarsCache() async {
  final prefs = await SharedPreferences.getInstance();
  final data = _dailyBarsCache.map((k, v) => MapEntry(
    k,
    v.map((bar) => bar.toJson()).toList()
  ));
  await prefs.setString(_dailyBarsCacheKey, jsonEncode(data));

  // 更新拉取日期
  final today = DateTime.now().toString().substring(0, 10);
  await prefs.setString(_lastFetchDateKey, today);
  _lastFetchDate = today;
}
```

### Debounce Save

```dart
Timer? _saveDebounceTimer;

void _schedulePersist() {
  _saveDebounceTimer?.cancel();
  _saveDebounceTimer = Timer(Duration(milliseconds: 500), () {
    _persistDailyBarsCache();
  });
}
```

---

## 5. Unified Refresh Entry Point

### Single Refresh Method

```dart
Future<void> refresh({
  bool silent = false,  // 静默刷新（不显示进度）
}) async {
  if (_isRefreshing) return;  // 防止重复触发

  _isRefreshing = true;
  _failedStocks.clear();

  if (!silent) {
    _stage = RefreshStage.fetchMinuteData;
    notifyListeners();
  }

  try {
    final stocks = _getStocksToRefresh();

    // 1. 拉取分时数据
    await _fetchMinuteDataIncremental(stocks, silent: silent);

    // 2. 更新日K数据
    if (!silent) {
      _stage = RefreshStage.updateDailyBars;
      notifyListeners();
    }
    await _updateDailyBarsIncremental(stocks, silent: silent);

    // 3. 分析计算
    if (!silent) {
      _stage = RefreshStage.analyzing;
      notifyListeners();
    }
    await _runAnalysis();

    // 4. 持久化
    _schedulePersist();

    // 5. 更新时间
    _lastUpdateTime = _formatTime(DateTime.now());
    _stage = RefreshStage.idle;

    // 6. 部分失败提示
    if (_failedStocks.isNotEmpty) {
      _stageDescription = '${_failedStocks.length}只股票拉取失败';
      Future.delayed(Duration(seconds: 3), () {
        if (_stage == RefreshStage.idle) {
          _stageDescription = null;
          notifyListeners();
        }
      });
    }
  } catch (e) {
    _stage = RefreshStage.error;
    _stageDescription = _formatError(e);
  } finally {
    _isRefreshing = false;
    notifyListeners();
  }
}

String _formatTime(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:'
         '${dt.minute.toString().padLeft(2, '0')}:'
         '${dt.second.toString().padLeft(2, '0')}';
}

String _formatError(dynamic e) {
  if (e is SocketException) return '网络连接失败';
  if (e is TimeoutException) return '请求超时';
  return '刷新失败';
}
```

### Unified Call Sites

```dart
// 下拉刷新
onRefresh: () => provider.refresh()

// 定时刷新 (静默)
Timer.periodic(Duration(seconds: 3), (_) => provider.refresh(silent: true))

// 数据管理页刷新
onPressed: () => provider.refresh()
```

---

## 6. Top Bar Refresh Status Widget

### RefreshStatusWidget

```dart
class RefreshStatusWidget extends StatelessWidget {
  const RefreshStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketDataProvider>(
      builder: (_, provider, __) {
        return GestureDetector(
          onTap: () {
            if (!provider.isRefreshing) {
              provider.refresh();
            }
          },
          onLongPress: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataManagementScreen()),
            );
          },
          child: _buildContent(context, provider),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, MarketDataProvider provider) {
    final theme = Theme.of(context);

    // 错误状态
    if (provider.stage == RefreshStage.error) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.orange, size: 18),
          SizedBox(width: 4),
          Text(
            provider.stageDescription ?? '刷新失败',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    // 刷新中
    if (provider.isRefreshing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 6),
          Text(
            provider.stageDescription ?? '刷新中...',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    // 空闲状态
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          provider.lastUpdateTime ?? '--:--:--',
          style: theme.textTheme.bodySmall,
        ),
        SizedBox(width: 4),
        Icon(Icons.refresh, size: 18),
      ],
    );
  }
}
```

---

## 7. Data Management Screen

### DataManagementScreen

```dart
class DataManagementScreen extends StatelessWidget {
  const DataManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('数据管理')),
      body: Consumer<MarketDataProvider>(
        builder: (_, provider, __) {
          return ListView(
            padding: EdgeInsets.all(16),
            children: [
              // 缓存总大小
              _buildSummaryCard(provider),
              SizedBox(height: 16),

              // 分类缓存列表
              _buildCacheItem(
                context,
                title: '日K数据',
                subtitle: '${provider.dailyBarsCacheCount}只股票',
                size: provider.dailyBarsCacheSize,
                onClear: () => provider.clearDailyBarsCache(),
              ),
              _buildCacheItem(
                context,
                title: '分时数据',
                subtitle: '${provider.minuteDataCacheCount}只股票',
                size: provider.minuteDataCacheSize,
                onClear: () => provider.clearMinuteDataCache(),
              ),
              _buildCacheItem(
                context,
                title: '行业数据',
                subtitle: provider.industryDataLoaded ? '已加载' : '未加载',
                size: provider.industryDataCacheSize,
                onClear: () => provider.clearIndustryDataCache(),
              ),

              SizedBox(height: 24),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _confirmClearAll(context, provider),
                      child: Text('清空所有缓存'),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: provider.isRefreshing
                        ? null
                        : () => provider.refresh(),
                      child: Text('刷新数据'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(MarketDataProvider provider) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('缓存总大小'),
            Text(provider.totalCacheSizeFormatted),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String? size,
    required VoidCallback onClear,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (size != null) Text(size),
          SizedBox(width: 8),
          TextButton(
            onPressed: () => _confirmClear(context, title, onClear),
            child: Text('清空'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, String title, VoidCallback onClear) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('确认清空'),
        content: Text('确定要清空 $title 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              onClear();
              Navigator.pop(context);
            },
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, MarketDataProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('确认清空'),
        content: Text('确定要清空所有缓存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.clearAllCache();
              Navigator.pop(context);
            },
            child: Text('确定'),
          ),
        ],
      ),
    );
  }
}
```

---

## 8. Unified Minute Data Fetching & Persistence

### Data Sharing Strategy

```dart
// 需要拉取分时的股票 = 自选股 ∪ 行业成分股
Set<String> _getStocksNeedingMinuteData() {
  final stocks = <String>{};

  // 自选股
  stocks.addAll(_watchlistService.stocks);

  // 行业趋势需要的成分股
  stocks.addAll(_industryTrendService.getRequiredStocks());

  return stocks;
}
```

### Paginated Fetching (Large Volume for Industry)

```dart
Future<void> _fetchMinuteDataIncremental(Set<String> stocks, {bool silent = false}) async {
  final stockList = stocks.toList();
  final pageSize = 20; // TDX 每次请求限制

  for (int i = 0; i < stockList.length; i += pageSize) {
    final batch = stockList.skip(i).take(pageSize).toList();

    // 增量: 只拉取新数据
    final results = await _fetchMinuteBatch(batch, incremental: true);

    // 更新缓存 (个股+行业共用)
    for (final entry in results.entries) {
      _minuteDataCache[entry.key] = entry.value;
    }

    if (!silent) {
      _updateProgress(RefreshStage.fetchMinuteData, i + batch.length, stockList.length);
    }
  }
}
```

### Shared Cache Access

```dart
// 个股详情使用
List<MinuteData>? getMinuteData(String stockCode) => _minuteDataCache[stockCode];

// 行业趋势计算使用 (同一缓存)
Map<String, List<MinuteData>> getMinuteDataForIndustry(List<String> stockCodes) {
  return Map.fromEntries(
    stockCodes
      .where((code) => _minuteDataCache.containsKey(code))
      .map((code) => MapEntry(code, _minuteDataCache[code]!))
  );
}
```

### Minute Data Persistence

```dart
// 缓存键
static const String _minuteDataCacheKey = 'minute_data_cache_v1';
static const String _minuteDataDateKey = 'minute_data_date';

// 存储格式: Map<String, List<Map>>
{
  "sh600000": [
    {"time": "09:31", "price": 10.5, "volume": 1000, "avgPrice": 10.48},
    {"time": "09:32", ...}
  ],
  ...
}
```

### Daily Auto-Clear Strategy

```dart
Future<void> _loadMinuteDataCache() async {
  final prefs = await SharedPreferences.getInstance();
  final cacheDate = prefs.getString(_minuteDataDateKey);
  final today = DateTime.now().toString().substring(0, 10);

  // 跨日自动清空
  if (cacheDate != today) {
    await prefs.remove(_minuteDataCacheKey);
    await prefs.setString(_minuteDataDateKey, today);
    return;
  }

  // 当日加载缓存
  final json = prefs.getString(_minuteDataCacheKey);
  if (json != null) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      _minuteDataCache = data.map((k, v) => MapEntry(
        k,
        (v as List).map((e) => MinuteData.fromJson(e)).toList()
      ));
    } catch (e) {
      await prefs.remove(_minuteDataCacheKey);
    }
  }
}
```

### Save with Debounce

```dart
// 与日K缓存一起 debounce 保存
void _schedulePersist() {
  _saveDebounceTimer?.cancel();
  _saveDebounceTimer = Timer(Duration(milliseconds: 500), () {
    _persistDailyBarsCache();
    _persistMinuteDataCache();  // 新增
  });
}

Future<void> _persistMinuteDataCache() async {
  final prefs = await SharedPreferences.getInstance();
  final data = _minuteDataCache.map((k, v) => MapEntry(
    k,
    v.map((m) => m.toJson()).toList()
  ));
  await prefs.setString(_minuteDataCacheKey, jsonEncode(data));

  final today = DateTime.now().toString().substring(0, 10);
  await prefs.setString(_minuteDataDateKey, today);
}
```

---

## 9. MarketDataProvider New Methods

```dart
// Cache info getters
int get dailyBarsCacheCount => _dailyBarsCache.length;
int get minuteDataCacheCount => _minuteDataCache.length;
String get dailyBarsCacheSize => _formatSize(_estimateDailyBarsSize());
String get minuteDataCacheSize => _formatSize(_estimateMinuteDataSize());
String? get industryDataCacheSize => _industryService.isLoaded
  ? _formatSize(_estimateIndustryDataSize())
  : null;
bool get industryDataLoaded => _industryService.isLoaded;
String get totalCacheSizeFormatted => _formatSize(_estimateTotalSize());

// Clear methods
Future<void> clearDailyBarsCache() async {
  _dailyBarsCache.clear();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_dailyBarsCacheKey);
  notifyListeners();
}

Future<void> clearMinuteDataCache() async {
  _minuteDataCache.clear();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_minuteDataCacheKey);
  notifyListeners();
}

Future<void> clearIndustryDataCache() async {
  await _industryService.clearCache();
  notifyListeners();
}

Future<void> clearAllCache() async {
  await clearDailyBarsCache();
  await clearMinuteDataCache();
  await clearIndustryDataCache();
}

// Size estimation
int _estimateDailyBarsSize() {
  int total = 0;
  for (final bars in _dailyBarsCache.values) {
    total += bars.length * 50; // ~50 bytes per bar
  }
  return total;
}

int _estimateMinuteDataSize() {
  int total = 0;
  for (final data in _minuteDataCache.values) {
    total += data.length * 40; // ~40 bytes per minute data
  }
  return total;
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '<1KB';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}
```

---

## 10. Files to Modify

| File | Changes |
|------|---------|
| `lib/providers/market_data_provider.dart` | Add refresh stages, incremental fetching, cache persistence, clear methods |
| `lib/widgets/refresh_status_widget.dart` | New file - top bar refresh status |
| `lib/screens/data_management_screen.dart` | New file - data management page |
| `lib/screens/main_screen.dart` | Add RefreshStatusWidget to AppBar |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-21 | Initial design |
