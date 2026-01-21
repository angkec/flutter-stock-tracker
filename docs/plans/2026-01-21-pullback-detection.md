# 高质量回踩检测功能实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 检测并标记高质量回踩股票，在主列表显示标记，并提供独立 Tab 查看和配置

**Architecture:** 新增回踩检测服务，扩展 StockMonitorData 添加回踩标记，新建回踩 Tab 页面

**Tech Stack:** Flutter, SharedPreferences (配置持久化), TdxClient (日K数据)

---

## 回踩判断逻辑

1. **昨日高量**：昨日成交量 > 前5日均量 × volumeMultiplier (默认1.5)
2. **昨日上涨**：昨日收盘 > 昨日开盘 × (1 + minYesterdayGain) (默认3%)
3. **今日缩量**：今日成交量 < 昨日成交量
4. **今日下跌**：今日收盘 < 今日开盘
5. **跌幅限制**：今日跌幅 < 昨日涨幅 × maxDropRatio (默认0.5)
6. **量比要求**：今日日K量比 > minDailyRatio (默认0.85)

---

## Task 1: 回踩配置模型和服务

**Files:**
- Create: `lib/models/pullback_config.dart`
- Create: `lib/services/pullback_service.dart`

**Step 1: 创建配置模型**

```dart
// lib/models/pullback_config.dart
class PullbackConfig {
  final double volumeMultiplier;    // 昨日高量倍数，默认 1.5
  final double minYesterdayGain;    // 昨日最小涨幅，默认 0.03 (3%)
  final double maxDropRatio;        // 最大跌幅比例，默认 0.5
  final double minDailyRatio;       // 最小日K量比，默认 0.85

  // 构造函数、toJson、fromJson、copyWith
}
```

**Step 2: 创建回踩服务**

```dart
// lib/services/pullback_service.dart
class PullbackService extends ChangeNotifier {
  PullbackConfig _config;

  Future<void> load();  // 从 SharedPreferences 加载
  Future<void> save();  // 保存配置

  /// 检测单只股票是否为高质量回踩
  /// 需要最近7日的日K数据
  bool isPullback(List<KLine> dailyBars);
}
```

---

## Task 2: 扩展数据模型

**Files:**
- Modify: `lib/services/stock_service.dart` (StockMonitorData)
- Modify: `lib/providers/market_data_provider.dart`

**Step 1: 扩展 StockMonitorData**

添加 `isPullback` 字段：

```dart
class StockMonitorData {
  // ... existing fields
  final bool isPullback;  // 是否为高质量回踩
}
```

**Step 2: 在 MarketDataProvider 中集成回踩检测**

刷新数据时，对每只股票检测回踩状态。
需要额外获取日K数据（可批量或按需）。

---

## Task 3: 主列表标记显示

**Files:**
- Modify: `lib/widgets/stock_table.dart`

**修改内容：**
- 在股票名称后添加 `*` 标记（当 isPullback 为 true）
- 如：`平安银行*`

---

## Task 4: 回踩 Tab 页面

**Files:**
- Create: `lib/screens/pullback_screen.dart`
- Modify: `lib/screens/main_screen.dart`

**Step 1: 创建回踩页面**

- 顶部：配置按钮（打开配置对话框）
- 列表：显示所有 isPullback 为 true 的股票
- 使用与主列表相同的 StockTable 组件

**Step 2: 添加到主页面 Tab**

在 MainScreen 中添加「回踩」Tab。

---

## Task 5: 配置对话框

**Files:**
- Create: `lib/widgets/pullback_config_dialog.dart`

**内容：**
- 4 个可调整参数的输入框/滑块
- 保存/取消按钮
- 恢复默认按钮

---

## Task 6: 数据获取优化

**Files:**
- Modify: `lib/services/stock_service.dart`
- Modify: `lib/providers/market_data_provider.dart`

**问题：** 需要获取每只股票的日K数据来判断回踩，数据量大。

**方案：**
- 在全市场扫描时，批量获取日K数据
- 或先用分钟数据筛选候选，再精确判断
- 缓存日K数据减少请求

---

## 验收标准

1. 主列表中回踩股票显示 `*` 标记
2. 回踩 Tab 显示所有符合条件的股票
3. 可在配置对话框调整4个参数
4. 配置持久化保存
5. 刷新数据后自动更新回踩状态
