# 自选股监控功能设计

## 概述

为 A股涨跌量比监控 App 添加自选股功能，支持：
- 独立的自选股监控页面
- 全市场列表中高亮自选股
- 本地持久化存储

## 页面结构

```
┌─────────────────────────────────┐
│         状态栏 (SafeArea)        │
├─────────────────────────────────┤
│                                 │
│         页面内容区域             │
│   (自选股页面 / 全市场页面)       │
│                                 │
├─────────────────────────────────┤
│    [自选]          [全市场]      │
│      ↑                          │
│   默认选中                       │
└─────────────────────────────────┘
```

## 数据加载策略

1. App 启动 → 加载自选股列表（本地存储）
2. 自动获取自选股 K线数据（仅几只，秒级完成）
3. 用户切换到全市场 Tab → 点击刷新按钮 → 获取全市场数据

**优势：**
- 启动快 - 只加载几只自选股
- 省流量 - 全市场数据按需获取
- 体验好 - 关注的股票优先展示

## 功能细节

### 自选股页面

- 顶部：输入框 + 添加按钮
- 列表：自选股的涨跌量比（按量比排序）
- 长按：弹出确认删除对话框
- 空状态：提示"暂无自选股，请添加"

### 全市场页面

- 显示全部有效股票（不限制条数）
- 自选股行高亮显示（特殊背景色）
- 列表可滚动浏览全部数据
- 手动点击刷新按钮获取数据

### 添加自选股

- 输入 6 位股票代码
- 自动识别市场（0/3 开头深圳，6 开头上海）
- 校验代码格式，重复添加提示
- 添加后立即获取该股票数据

### 删除自选股

- 长按弹出对话框："确定删除 000001 平安银行？"
- 确认后从列表和本地存储中移除

## 技术实现

### 新增文件

| 文件 | 说明 |
|------|------|
| `lib/services/watchlist_service.dart` | 自选股存储管理 |
| `lib/screens/watchlist_screen.dart` | 自选股页面 |
| `lib/screens/market_screen.dart` | 全市场页面 |
| `lib/screens/main_screen.dart` | 底部 Tab 容器 |

### 依赖包

- `shared_preferences` - 本地存储自选股列表

### WatchlistService

```dart
class WatchlistService extends ChangeNotifier {
  List<String> _watchlist = [];

  List<String> get watchlist => _watchlist;

  Future<void> load();                      // 从本地加载
  Future<void> addStock(String code);       // 添加并保存
  Future<void> removeStock(String code);    // 删除并保存
  bool contains(String code);               // 判断是否自选
}
```

### 状态管理

- WatchlistService 通过 Provider 注入，继承 ChangeNotifier
- 自选股变更时调用 notifyListeners() 通知 UI 刷新
- 全市场页面通过 WatchlistService.contains() 判断高亮

### 股票代码校验

```dart
bool isValidStockCode(String code) {
  if (code.length != 6) return false;
  if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;
  // 深圳: 0/3 开头, 上海: 6 开头
  return code.startsWith('0') || code.startsWith('3') || code.startsWith('6');
}

int getMarket(String code) {
  // 深圳=0, 上海=1
  return code.startsWith('6') ? 1 : 0;
}
```

## UI 高亮样式

全市场列表中自选股的高亮效果：

```dart
DataRow(
  color: WidgetStateProperty.all(
    isWatchlist
      ? Colors.amber.withOpacity(0.15)  // 自选股高亮
      : null,
  ),
  // ...
)
```
