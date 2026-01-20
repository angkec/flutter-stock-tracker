# Shared Market Data Design

## Overview

将三个 tab 的数据统一到 MarketDataProvider，实现数据共享、优先加载自选股、渐进式更新、数据持久化。

## 数据架构

**MarketDataProvider** (ChangeNotifier)

```dart
class MarketDataProvider extends ChangeNotifier {
  List<StockMonitorData> allData = [];
  bool isLoading = false;
  int progress = 0;
  int total = 0;
  String? updateTime;
  String? errorMessage;

  Future<void> refresh();
  Future<void> loadFromCache();
  Future<void> saveToCache();
}
```

**各 Tab 读取方式：**
- 自选 tab：`allData.where((d) => watchlist.contains(d.stock.code))`
- 全市场 tab：`allData`（可搜索过滤）
- 行业 tab：按行业分组统计 `allData`

## 刷新流程

**优先级：** 自选股排在前面优先获取

**渐进式更新：**
```
批次1 (自选股) → 更新 allData → notifyListeners() → UI刷新
批次2          → 更新 allData → notifyListeners() → UI刷新
批次3          → 更新 allData → notifyListeners() → UI刷新
...
全部完成       → 更新 updateTime → saveToCache()
```

## UI 变化

**StatusBar 右上角：**

| 状态 | 显示内容 |
|------|---------|
| 空闲 | 刷新按钮 |
| 加载中 | 小型进度指示器 + "123/5000" |
| 错误 | 红色错误图标（点击可重试）|

**移除：**
- 各 Screen 不再单独管理加载状态
- StatusBar 直接从 MarketDataProvider 读取状态

## Screen 简化

| Screen | 改动 |
|--------|------|
| WatchlistScreen | 移除刷新逻辑；从 Provider 读数据并过滤自选股 |
| MarketScreen | 移除刷新逻辑；从 Provider 读 allData |
| IndustryScreen | 移除刷新逻辑；从 Provider 读数据并按行业统计 |
| MainScreen | 移除 _refreshAll()；刷新直接调用 Provider |

**保留的逻辑：**
- WatchlistScreen：添加/删除自选股
- MarketScreen：搜索框过滤
- IndustryScreen：行业统计计算、点击跳转

## 数据持久化

**存储方式：** SharedPreferences + JSON

**启动时：**
1. MarketDataProvider 初始化
2. 从 SharedPreferences 读取缓存
3. 如有缓存 → 立即填充 allData → UI 显示旧数据
4. 显示上次更新时间

**刷新完成时：**
1. 序列化 allData 为 JSON
2. 存入 SharedPreferences

**需要添加：**
- StockMonitorData.toJson()
- StockMonitorData.fromJson()

## 实现文件

### 新建
- `lib/providers/market_data_provider.dart`

### 修改
- `lib/services/stock_service.dart` - StockMonitorData 添加 JSON 序列化
- `lib/widgets/status_bar.dart` - 从 Provider 读取状态，改进进度显示
- `lib/screens/watchlist_screen.dart` - 简化，从 Provider 读数据
- `lib/screens/market_screen.dart` - 简化，从 Provider 读数据
- `lib/screens/industry_screen.dart` - 简化，从 Provider 读数据
- `lib/screens/main_screen.dart` - 移除 _refreshAll
- `lib/main.dart` - 注册 MarketDataProvider
