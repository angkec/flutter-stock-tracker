# 回测功能设计

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为回踩配置添加回测功能，评估当前配置在历史数据上的选股成功率

**Architecture:** 独立回测页面，复用现有缓存数据和突破检测逻辑，新增 BacktestService 处理回测计算

**Tech Stack:** Flutter, CustomPainter (图表), SharedPreferences (配置持久化)

---

## 功能概述

### 入口
多日回踩页面（BreakoutScreen）AppBar 中，配置按钮旁边新增"回测"按钮

### 核心功能
- 使用当前回踩配置检测历史突破信号
- 计算各观察周期的成功率
- 展示成功率柱状图和收益分布图
- 提供信号详情列表

---

## 数据模型

### BacktestConfig - 回测配置

```dart
/// 买入价基准枚举
enum BuyPriceReference {
  breakoutHigh,    // 突破日最高价（默认）
  breakoutClose,   // 突破日收盘价
  pullbackAverage, // 回踩期间平均价
  pullbackLow,     // 回踩期间最低价
}

/// 回测配置
class BacktestConfig {
  /// 观察周期档位（天数列表）
  final List<int> observationDays; // 默认 [3, 5, 10]

  /// 目标涨幅（成功阈值）
  final double targetGain; // 默认 0.05 (5%)

  /// 买入价基准
  final BuyPriceReference buyPriceReference; // 默认 breakoutHigh

  const BacktestConfig({
    this.observationDays = const [3, 5, 10],
    this.targetGain = 0.05,
    this.buyPriceReference = BuyPriceReference.breakoutHigh,
  });
}
```

### BacktestResult - 回测结果

```dart
/// 单周期统计结果
class PeriodStats {
  final int days;           // 观察天数
  final int successCount;   // 成功次数
  final double successRate; // 成功率
  final double avgMaxGain;  // 平均最高涨幅
  final double avgMaxDrawdown; // 平均最大回撤
}

/// 单个信号详情
class SignalDetail {
  final String stockCode;
  final String stockName;
  final DateTime breakoutDate;     // 突破日
  final DateTime signalDate;       // 信号触发日（回踩结束日）
  final double buyPrice;           // 买入价
  final Map<int, double> maxGainByPeriod;  // {天数: 最高涨幅}
  final Map<int, bool> successByPeriod;    // {天数: 是否成功}
}

/// 回测结果
class BacktestResult {
  final int totalSignals;                    // 总信号数
  final List<PeriodStats> periodStats;       // 各周期统计
  final List<SignalDetail> signals;          // 信号详情列表
  final List<double> allMaxGains;            // 所有最高涨幅（用于分布图）
}
```

---

## 成功判定逻辑

1. 根据配置确定"买入价"：
   - `breakoutHigh`: 突破日最高价
   - `breakoutClose`: 突破日收盘价
   - `pullbackAverage`: 回踩期间成交量加权平均价
   - `pullbackLow`: 回踩期间最低价

2. 从回踩结束日（信号触发日）次日开始观察

3. 计算观察期内的最高价

4. 最高涨幅 = (最高价 - 买入价) / 买入价

5. 若最高涨幅 >= 目标涨幅，则判定为"成功"

---

## 页面UI布局

### BacktestScreen 结构

```
┌─────────────────────────────────────┐
│ AppBar: 回测分析                     │
├─────────────────────────────────────┤
│ ┌─────────────┐ ┌─────────────────┐ │
│ │ 修改配置    │ │   开始回测      │ │
│ └─────────────┘ └─────────────────┘ │
├─────────────────────────────────────┤
│ 当前配置摘要（可折叠）               │
│ 量>1.5x 前高10天 回踩1-5天...       │
│ 买入价: 突破日最高 | 目标: 5%        │
│ 观察周期: 3天, 5天, 10天             │
├─────────────────────────────────────┤
│ 【回测结果区 - 回测后显示】          │
│                                     │
│ 成功率汇总卡片                       │
│ ┌───────┬───────┬───────┐          │
│ │ 3天   │ 5天   │ 10天  │          │
│ │ 45%   │ 62%   │ 78%   │          │
│ └───────┴───────┴───────┘          │
│                                     │
│ 图表区（Tab切换）                    │
│ [成功率] [收益分布]                  │
│ ┌─────────────────────────┐        │
│ │      柱状图/分布图       │        │
│ └─────────────────────────┘        │
│                                     │
│ 详情列表                            │
│ ┌─────────────────────────┐        │
│ │ 股票A  3天:+6% 5天:+8%  │        │
│ │ 股票B  3天:+2% 5天:+5%  │        │
│ │ ...                     │        │
│ └─────────────────────────┘        │
└─────────────────────────────────────┘
```

### 交互说明
- "修改配置"按钮：打开现有 BreakoutConfigSheet
- "开始回测"按钮：执行回测计算，显示结果
- 详情列表点击：可跳转到个股详情页

---

## 文件结构

### 新增文件

```
lib/
├── models/
│   └── backtest_config.dart      # BacktestConfig, BacktestResult 等模型
├── services/
│   └── backtest_service.dart     # 回测计算逻辑
├── screens/
│   └── backtest_screen.dart      # 回测页面
└── widgets/
    ├── backtest_chart.dart       # 成功率柱状图 + 收益分布图
    └── backtest_signal_list.dart # 信号详情列表
```

### 修改文件

```
lib/screens/breakout_screen.dart  # AppBar 添加回测入口按钮
```

---

## 实现任务

### Task 1: 创建数据模型
**Files:**
- Create: `lib/models/backtest_config.dart`

创建 BacktestConfig、BuyPriceReference、BacktestResult、PeriodStats、SignalDetail 模型类，包含 JSON 序列化和默认值。

### Task 2: 实现回测服务
**Files:**
- Create: `lib/services/backtest_service.dart`

实现 BacktestService：
- 加载/保存 BacktestConfig
- runBacktest() 方法：遍历历史数据，检测信号，计算成功率
- 复用 BreakoutService 的突破检测逻辑

### Task 3: 创建图表组件
**Files:**
- Create: `lib/widgets/backtest_chart.dart`

实现双图表组件：
- 成功率柱状图：展示各观察周期的成功率
- 收益分布直方图：展示涨幅分布区间

### Task 4: 创建信号列表组件
**Files:**
- Create: `lib/widgets/backtest_signal_list.dart`

实现信号详情列表：
- 显示股票代码、名称、突破日期
- 显示各周期最高涨幅和是否达标
- 点击跳转个股详情页

### Task 5: 创建回测页面
**Files:**
- Create: `lib/screens/backtest_screen.dart`

实现 BacktestScreen：
- 操作栏（修改配置、开始回测按钮）
- 配置摘要显示
- 回测参数配置（观察周期、目标涨幅、买入价基准）
- 结果展示区域（汇总卡片、图表、详情列表）

### Task 6: 添加入口按钮
**Files:**
- Modify: `lib/screens/breakout_screen.dart`

在 AppBar actions 中添加回测入口按钮，放在配置按钮旁边。

### Task 7: 注册服务
**Files:**
- Modify: `lib/main.dart`

在 Provider 中注册 BacktestService。
