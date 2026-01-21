# 数据日期回退功能设计

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 当今天没有分钟K线数据时（早盘前、周末、节假日），自动回退到最近有数据的交易日，并在状态栏显示数据日期提示。

**Architecture:** 在 StockService 数据获取层增加日期回退逻辑，通过 MarketDataProvider 暴露数据日期，StatusBar 根据日期显示提示。

**Tech Stack:** Flutter, Provider

---

## Task 1: 扩展返回类型

**Files:**
- Modify: `lib/services/stock_service.dart`

**Changes:**
新增 `MonitorDataResult` 类封装返回结果：

```dart
/// 监控数据结果（包含数据日期）
class MonitorDataResult {
  final List<StockMonitorData> data;
  final DateTime dataDate;  // 实际数据日期

  MonitorDataResult({required this.data, required this.dataDate});
}
```

---

## Task 2: 修改 batchGetMonitorData 支持日期回退

**Files:**
- Modify: `lib/services/stock_service.dart`

**Changes:**
1. 修改 `batchGetMonitorData` 返回 `MonitorDataResult`
2. 添加日期回退逻辑：
   - 收集所有K线数据中出现的日期
   - 优先使用今天，如果今天无数据则用最近的日期
   - 用选定日期过滤K线

**伪代码：**
```dart
Future<MonitorDataResult> batchGetMonitorData(...) async {
  final today = DateTime.now();
  final allDates = <String>{};  // 收集所有日期
  final stockBarsMap = <int, List<KLine>>{};  // 暂存所有K线

  // 第一遍：收集数据和日期
  await _pool.batchGetSecurityBarsStreaming(
    onStockBars: (index, bars) {
      stockBarsMap[index] = bars;
      for (final bar in bars) {
        allDates.add(_formatDate(bar.datetime));
      }
    },
  );

  // 确定使用哪个日期
  final todayKey = _formatDate(today);
  final sortedDates = allDates.toList()..sort((a, b) => b.compareTo(a));
  final targetDate = sortedDates.contains(todayKey)
      ? todayKey
      : (sortedDates.isNotEmpty ? sortedDates.first : todayKey);

  // 第二遍：用目标日期过滤并计算
  for (final entry in stockBarsMap.entries) {
    final bars = entry.value.where((b) => _formatDate(b.datetime) == targetDate).toList();
    // ... 计算 ratio 等
  }

  return MonitorDataResult(data: results, dataDate: _parseDate(targetDate));
}
```

---

## Task 3: 更新 MarketDataProvider

**Files:**
- Modify: `lib/providers/market_data_provider.dart`

**Changes:**
1. 新增状态变量 `DateTime? _dataDate`
2. 新增 getter `DateTime? get dataDate => _dataDate`
3. 在 `refresh()` 中保存返回的 `dataDate`
4. 缓存也需要保存/恢复 `dataDate`

---

## Task 4: 更新 StatusBar 显示

**Files:**
- Modify: `lib/widgets/status_bar.dart`

**Changes:**
根据 `dataDate` 是否为今天决定显示格式：

```dart
// 判断是否是历史数据
bool _isHistoricalData(DateTime? dataDate) {
  if (dataDate == null) return false;
  final today = DateTime.now();
  return dataDate.year != today.year ||
         dataDate.month != today.month ||
         dataDate.day != today.day;
}

// 显示逻辑
if (provider.updateTime != null && !provider.isLoading) {
  final isHistorical = _isHistoricalData(provider.dataDate);
  Text(
    isHistorical
      ? '${provider.dataDate!.month.toString().padLeft(2, '0')}-${provider.dataDate!.day.toString().padLeft(2, '0')} ${provider.updateTime!}'
      : provider.updateTime!,
    style: TextStyle(
      color: isHistorical ? Colors.orange : onSurfaceVariant,
      fontFamily: 'monospace',
    ),
  ),
}
```

---

## 验收标准

1. 正常交易时段：显示今天数据，时间格式 "10:30:25"
2. 早盘前/周末/节假日：显示最近交易日数据，格式 "01-20 10:30:25"（橙色）
3. 缓存恢复后也能正确显示数据日期
