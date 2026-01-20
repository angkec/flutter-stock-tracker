# 股票详情页设计

## 概述

点击某只个股后推入详情页，展示 K 线图和量比历史数据。

## 功能需求

### K 线图
- 静态显示最近 30 根 K 线
- 支持日线/周线切换
- 使用 CustomPaint 自绘，无第三方依赖
- 涨红跌绿（中国股市惯例）

### 量比历史
- 显示最近 20 天的量比值
- 列表形式展示：日期 + 星期 + 量比
- 量比 ≥ 1.0 红色，< 1.0 绿色

### 页面布局
- 上下布局，可滚动
- 顶部：AppBar（股票名称 + 代码）
- 中部：K 线图 + 切换按钮
- 底部：量比历史列表

## 技术设计

### 页面结构

```
StockDetailScreen
├── AppBar (股票名称 + 代码)
├── K线图区域
│   ├── 切换按钮 (日线/周线)
│   └── KLineChart (CustomPaint)
└── 量比历史区域
    ├── 标题栏 "量比历史"
    └── 列表 (20天数据)
```

### K 线图组件

**接口：**
```dart
KLineChart(
  bars: List<KLine>,
  width: double,
  height: double,  // 建议 200-250
)
```

**绘制逻辑：**
1. 计算价格范围（最高/最低价，上下留 5% 边距）
2. 绘制每根 K 线：
   - 实体：开盘到收盘的矩形
   - 影线：最高/最低价的细线
   - 颜色：close >= open 红色，否则绿色
3. K 线宽度：`(chartWidth - padding) / barCount * 0.8`
4. 底部日期标注：每隔 5-10 根显示一个日期

**颜色常量：**
```dart
const kUpColor = Color(0xFFFF4444);   // 涨 - 红
const kDownColor = Color(0xFF00AA00); // 跌 - 绿
```

### 量比历史

**数据模型：**
```dart
class DailyRatio {
  final DateTime date;
  final double? ratio;  // null 表示无法计算
}
```

**计算流程：**
1. 请求 20 天的 1 分钟 K 线（约 4800 根，分批请求）
2. 按交易日分组
3. 每天调用 `calculateRatio` 计算量比
4. 返回 `List<DailyRatio>`

**列表 UI：**
```
┌─────────────────────────────┐
│  01-20 周一    1.85         │
│  01-17 周五    0.72         │
│  01-16 周四    2.31         │
└─────────────────────────────┘
```

### 数据服务

**新增方法（StockService）：**
```dart
Future<List<KLine>> getKLines({
  required Stock stock,
  required int category,
  int count = 30,
});

Future<List<DailyRatio>> getRatioHistory({
  required Stock stock,
  int days = 20,
});
```

### 状态管理

**StockDetailScreen（StatefulWidget）：**
- `_dailyBars` / `_weeklyBars` - 日线/周线数据
- `_ratioHistory` - 量比历史
- `_isLoadingKLine` / `_isLoadingRatio` - 加载状态
- `_klineError` / `_ratioError` - 错误信息

### 错误处理

| 场景 | 处理方式 |
|------|---------|
| 网络超时 | 显示错误提示 + 重试按钮 |
| 数据为空 | 显示「暂无数据」|
| 部分失败 | 成功部分正常显示，失败部分显示错误 |

## 文件规划

### 新增文件
- `lib/screens/stock_detail_screen.dart` - 详情页
- `lib/widgets/kline_chart.dart` - K 线图组件
- `lib/widgets/ratio_history_list.dart` - 量比历史列表
- `lib/models/daily_ratio.dart` - 量比数据模型

### 修改文件
- `lib/services/stock_service.dart` - 添加 getKLines、getRatioHistory
- `lib/widgets/stock_table.dart` - 添加点击跳转逻辑
