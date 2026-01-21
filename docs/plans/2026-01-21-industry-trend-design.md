# 行业量比趋势功能设计

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为行业热力图添加量比趋势功能，展示行业资金流入的历史变化

**Architecture:** 从TDX拉取分钟K线计算每日分钟涨跌量比，按行业聚合后本地缓存，在行业列表显示迷你趋势图，点击进入详情页

**Tech Stack:** Flutter, TDX API, SharedPreferences/SQLite

---

## 1. 数据模型

### IndustryTrendData
```dart
class IndustryTrendData {
  final String industry;              // 行业名称
  final List<DailyRatioPoint> points; // 每日数据点（按日期升序）
}

class DailyRatioPoint {
  final DateTime date;
  final double ratioAbovePercent;     // 量比>1股票占比 (0-100)
  final int totalStocks;              // 行业总股票数
  final int ratioAboveCount;          // 量比>1的股票数
}
```

### 缓存结构
- 按日期存储，每天一个快照
- 保留最近30天数据
- 今天数据实时计算，不缓存

## 2. 计算逻辑

### 每日分钟涨跌量比（每只股票）
```
1. 筛选出该天的所有分钟K线
2. 上涨分钟总量 = sum(close > open 的分钟成交量)
3. 下跌分钟总量 = sum(close < open 的分钟成交量)
4. 当日量比 = 上涨分钟总量 / 下跌分钟总量
5. 量比 > 1 表示资金主动买入
```

### 行业聚合
```
对于每个行业的每一天:
ratioAbovePercent = (量比>1的股票数 / 行业总股票数) * 100
```

## 3. 数据获取

### TDX数据拉取
- 使用 `TdxPool.batchGetSecurityBars` 获取分钟K线
- category=8 (分钟K线)
- count=240*30=7200 (约30天，每天240分钟)
- 分批拉取，每批500只股票，显示进度

### 增量更新策略
1. 启动时检查本地缓存的最新日期
2. 只拉取缺失日期到昨天的数据
3. 今天的数据每次刷新时实时计算
4. 首次拉取约需2-3分钟，增量更新只需几秒

## 4. UI设计

### 行业列表改进
```
┌────┬──────────┬──────────┬────────┐
│行业│  涨跌    │   量比   │ 趋势   │
├────┼──────────┼──────────┼────────┤
│电子│ ████░░░░ │ ██████░░ │ ╱╲╱─╱  │  迷你折线图(60px)
│医药│ ███░░░░░ │ ████░░░░ │ ╲╱╲─╲  │
└────┴──────────┴──────────┴────────┘
```
- 新增趋势列，显示近15天迷你折线图
- 趋势上升红色，下降绿色

### 行业详情页面（新增）
```
┌─────────────────────────────────┐
│  ← 电子          量比趋势       │  AppBar
├─────────────────────────────────┤
│  ┌─────────────────────────┐   │
│  │     完整趋势折线图       │   │  高度约150
│  │   (30天量比>1占比)      │   │
│  └─────────────────────────┘   │
├─────────────────────────────────┤
│  今日: 65% (89/137只放量)      │  当日摘要
├─────────────────────────────────┤
│  成分股列表                     │
│  ┌───┬────┬─────┬─────┐       │
│  │代码│名称│涨跌幅│量比 │       │  复用 StockTable
│  └───┴────┴─────┴─────┘       │
└─────────────────────────────────┘
```

### 交互
- 点击行业行 → 进入详情页
- 详情页成分股列表支持长按加自选
- 点击成分股 → 进入股票详情页

## 5. 排序与筛选

### 排序选项
```dart
enum IndustrySortMode {
  ratioPercent,      // 当前量比>1占比（默认）
  trendSlope,        // 趋势斜率（近7天上升/下降幅度）
  todayChange,       // 今日变化
}
```

### 排序UI
- 点击表头切换排序方式
- 或AppBar添加排序按钮弹出选项

### 筛选功能
- 筛选趋势连续N天上升的行业
- 筛选今日占比>X%的行业

## 6. 刷新策略

### 触发时机
- 进入 IndustryScreen 时自动检查缓存状态

### 刷新逻辑
```
1. 检查本地缓存最新日期
2. 计算缺失天数 = 今天 - 缓存最新日期
3. 如果缺失天数 <= 3天：
   - 自动后台拉取增量数据
   - 显示小型加载指示器
4. 如果缺失天数 > 3天（或无缓存）：
   - 显示"更新趋势数据"按钮
   - 用户点击后开始拉取，显示进度
5. 拉取完成后刷新UI
```

### UI反馈
- 自动增量更新：趋势列显示小loading，不阻塞操作
- 手动全量更新：弹出进度对话框，显示"正在获取数据 (500/5000)"
- 更新完成：Toast提示"趋势数据已更新"

### 今日数据
- 今日数据每次进入页面时实时计算（基于已有的分钟K线缓存）
- 不需要额外拉取

## 7. 文件结构

```
lib/
├── models/
│   └── industry_trend.dart          # IndustryTrendData, DailyRatioPoint
├── services/
│   └── industry_trend_service.dart  # 数据获取、计算、缓存
├── screens/
│   ├── industry_screen.dart         # 改进：添加趋势列
│   └── industry_detail_screen.dart  # 新增：行业详情页
├── widgets/
│   ├── sparkline_chart.dart         # 迷你折线图组件
│   └── industry_trend_chart.dart    # 完整趋势图组件
```

## 8. 实现步骤

1. 创建数据模型 `IndustryTrendData`
2. 实现 `IndustryTrendService`（数据获取、计算、缓存）
3. 创建 `SparklineChart` 迷你折线图组件
4. 改进 `IndustryScreen` 添加趋势列
5. 创建 `IndustryDetailScreen` 详情页
6. 创建 `IndustryTrendChart` 完整趋势图组件
7. 添加排序功能
8. 添加筛选功能
