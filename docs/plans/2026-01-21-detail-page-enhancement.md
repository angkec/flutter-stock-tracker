# 详情页增强实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为详情页添加分时图和板块热度条，提升短线交易和量比分析体验

**Architecture:** 在现有 K 线切换中增加分时图选项，新增板块热度组件显示行业内量比分布

**Tech Stack:** Flutter, TdxClient (分时数据), IndustryService (行业归属)

---

## Task 1: 分时图数据模型和获取

**Files:**
- Create: `lib/widgets/minute_chart.dart`
- Modify: `lib/screens/stock_detail_screen.dart`

**Step 1: 创建分时图组件骨架**

```dart
// lib/widgets/minute_chart.dart
import 'package:flutter/material.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class MinuteChart extends StatelessWidget {
  final List<KLine> bars;
  final double preClose; // 昨收价，用于计算涨跌
  final double height;

  const MinuteChart({
    super.key,
    required this.bars,
    required this.preClose,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    // TODO: 实现
  }
}
```

**Step 2: 在详情页加载当日分钟数据**

详情页已有 `_loadRatioHistory` 获取分钟数据，需要：
- 提取当日的分钟 K 线数据
- 传递给分时图组件

**Step 3: 修改 K 线切换逻辑**

将 `_showDaily` (bool) 改为枚举或 int：
- 0 = 分时
- 1 = 日线
- 2 = 周线

---

## Task 2: 实现分时图绘制

**Files:**
- Modify: `lib/widgets/minute_chart.dart`

**功能：**
1. 价格走势线（白色）
2. 均价线（黄色）- 累计成交额 / 累计成交量
3. 底部成交量柱（红涨绿跌，相对昨收）
4. 中间虚线（昨收价位置）
5. Y 轴显示价格范围

**绘制逻辑：**
- X 轴：09:30 - 15:00，共 240 分钟
- 价格线：连接每分钟收盘价
- 均价线：每个点 = 累计成交额 / 累计成交量
- 量柱：当前价 >= 昨收为红色，否则绿色

---

## Task 3: 板块热度数据获取

**Files:**
- Modify: `lib/services/industry_service.dart`
- Modify: `lib/providers/market_data_provider.dart`

**Step 1: 在 IndustryService 添加获取同行业股票方法**

```dart
List<String> getStocksByIndustry(String industry);
```

**Step 2: 在 MarketDataProvider 添加计算板块热度方法**

```dart
/// 获取板块热度（量比>=1 和 <1 的股票数量）
(int hot, int cold) getIndustryHeat(String industry);
```

遍历当前已有的监控数据，按行业筛选并统计。

---

## Task 4: 板块热度条组件

**Files:**
- Create: `lib/widgets/industry_heat_bar.dart`
- Modify: `lib/screens/stock_detail_screen.dart`

**Step 1: 创建热度条组件**

```dart
class IndustryHeatBar extends StatelessWidget {
  final String industryName;
  final int hotCount;  // 量比 >= 1
  final int coldCount; // 量比 < 1

  // 显示：行业名称 + 进度条 + 数字
}
```

**Step 2: 在详情页添加热度条**

- 放在 K 线图下方
- 从 MarketDataProvider 获取数据
- 如果行业为空则不显示

---

## Task 5: 整合和测试

**Files:**
- Modify: `lib/screens/stock_detail_screen.dart`

**验收标准：**
1. 分时 | 日线 | 周线 切换正常
2. 分时图显示价格线、均价线、量柱
3. 板块热度条显示行业名和红绿进度条
4. 量比历史保持正常功能
5. 下拉刷新更新所有数据
