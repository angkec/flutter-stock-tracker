# 早盘数据回退问题调试

## 问题描述

早上10:30之前拉取分钟K线数据时，今日数据不足（通常只有1-2根K线），应该自动回退到昨日数据。但目前回退后显示0条数据。

**用户反馈：**
- 能看到"历史"badge（说明回退日期被正确设置）
- 但各个界面为空，数据管理页显示0个股票

## 已完成的修改

### 1. 回退逻辑 (`lib/services/stock_service.dart`)

修改了 `batchGetMonitorData` 方法：
- 统计今日数据充足的股票数量
- 如果 < 10% 的股票有足够今日数据，触发回退
- 使用最近的非今日日期作为目标日期

```dart
final useFallback = todayValidCount < stocks.length * 0.1;
```

### 2. 历史数据标识 (`lib/widgets/status_bar.dart`)

增强了历史数据的UI显示：
- 显示"历史"badge + 日期
- 使用醒目的颜色（黄色/橙色）

### 3. 添加了调试代码

在以下位置添加了 `print()` 语句（以 🔍 开头）：
- `lib/services/stock_service.dart` - batchGetMonitorData 方法
- `lib/providers/market_data_provider.dart` - refresh 方法

## 待调试

### 测试步骤

1. 早上10:30之前运行：
```bash
flutter run -d macos
```

2. 点击刷新按钮

3. 查看终端输出的调试信息

### 预期调试输出

```
🔍 [MarketDataProvider.refresh] Called at ...
🔍 [MarketDataProvider.refresh] Got XXXX stocks
🔍 [batchGetMonitorData] Called with XXXX stocks
🔍 [batchGetMonitorData] Fetch complete: stockBarsMap=XXX, emptyBars=XXX
🔍 [batchGetMonitorData] todayValidCount=XXX, useFallback=XXX
🔍 [batchGetMonitorData] allDates count=XXX, dates=XXX
🔍 [batchGetMonitorData] Using fallback date: XXXX-XX-XX
🔍 [batchGetMonitorData] Processing stats: emptyTargetBars=XXX, nullRatio=XXX
🔍 [batchGetMonitorData] Final results count: XXX
```

### 关键诊断点

| 变量 | 正常值 | 问题指示 |
|------|--------|----------|
| `stockBarsMap` | ~5000 | 0 = 数据未下载 |
| `allDates count` | 2+ | 0 = 无日期数据 |
| `useFallback` | true（早盘） | false = 回退未触发 |
| `emptyTargetBars` | < 100 | 很大 = 目标日期无数据 |
| `nullRatio` | < 500 | 很大 = 数据质量问题 |
| `Final results` | > 4000 | 0 = 问题所在 |

## 独立测试验证

之前用独立测试脚本验证过逻辑是正确的：

```
Current time: 2026-01-22 09:10:14
Stock 000001: 240 total, 1 today -> Insufficient
Stock 000002: 240 total, 1 today -> Insufficient
Stock 600000: 240 total, 1 today -> Insufficient

Today valid count: 0/3
Should use fallback: true
Selected target date: 2026-01-21

Processing for target date:
Stock 000001: 239 bars -> Ratio: 0.68, VALID
Stock 000002: 239 bars -> Ratio: 2.02, VALID
Stock 600000: 239 bars -> Ratio: 0.43, VALID

Final: 3/3 valid results
```

测试脚本逻辑正确，但实际应用中可能有差异（并行请求、连接池等）。

## 可能的问题原因

1. **连接池问题** - 并行请求可能有错误被静默处理
2. **回调时序** - 异步回调可能有竞态条件
3. **数据过滤** - 目标日期过滤可能有边界问题

## 调试完成后

问题解决后，删除所有 `print()` 调试语句：
```bash
# 搜索并删除调试代码
grep -n "print('🔍" lib/services/stock_service.dart lib/providers/market_data_provider.dart
```

## 相关文件

- `lib/services/stock_service.dart` - 数据获取和回退逻辑
- `lib/providers/market_data_provider.dart` - 刷新流程
- `lib/widgets/status_bar.dart` - 历史数据显示
- `lib/services/tdx_pool.dart` - TDX连接池
