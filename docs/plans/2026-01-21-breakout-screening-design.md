# 放量突破筛选功能设计

## 概述

新增一个Tab页面，用于筛选"放量突破后高质量回踩"的股票。

**核心逻辑：**
1. 检测某天是否发生"放量突破"（突破均线/前高）
2. 检测从突破日到今天的"回踩质量"（跌幅、缩量、分钟量比）

## 数据模型

### BreakoutConfig

```dart
/// 放量突破配置
class BreakoutConfig {
  // === 突破日条件 ===
  /// 突破日放量倍数（突破日成交量 > 前5日均量 × 此值）
  final double breakVolumeMultiplier;  // 默认 1.5

  /// 突破N日均线（收盘价 > N日均线，0=不检测）
  final int maBreakDays;  // 默认 20

  /// 突破前N日高点（收盘价 > 前N日最高价，0=不检测）
  final int highBreakDays;  // 默认 5

  // === 回踩阶段条件 ===
  /// 最小回踩天数
  final int minPullbackDays;  // 默认 1

  /// 最大回踩天数
  final int maxPullbackDays;  // 默认 5

  /// 最大平均日跌幅（回踩期间平均每日跌幅）
  final double maxAvgDailyDrop;  // 默认 0.02 (2%)

  /// 最大平均量比（回踩期间平均成交量 / 突破日成交量）
  final double maxAvgVolumeRatio;  // 默认 0.7

  /// 最大分钟量比（今日分钟涨跌量比）
  final double maxMinuteRatio;  // 默认 1.0
}
```

## 检测服务

### BreakoutService

```dart
/// 放量突破检测服务
class BreakoutService extends ChangeNotifier {
  BreakoutConfig _config;

  /// 检测是否符合放量突破后回踩
  /// [dailyBars] 需要最近N天日K数据（按时间升序）
  /// [minuteRatio] 今日分钟涨跌量比
  /// 返回 true 表示符合条件
  bool isBreakoutPullback(List<KLine> dailyBars, double minuteRatio);
}
```

**检测逻辑：**

1. **寻找突破日**（在 maxPullbackDays+1 到 maxPullbackDays+minPullbackDays 范围内倒序查找）
   - 成交量 > 前5日均量 × breakVolumeMultiplier
   - 收盘价 > N日均线（如果 maBreakDays > 0）
   - 收盘价 > 前N日最高价（如果 highBreakDays > 0）
   - 当日上涨（收盘 > 开盘）

2. **验证回踩阶段**（从突破日+1 到今天）
   - 回踩天数在 minPullbackDays ~ maxPullbackDays 范围内
   - 平均日跌幅 <= maxAvgDailyDrop
   - 平均成交量 <= 突破日成交量 × maxAvgVolumeRatio
   - 今日分钟量比 <= maxMinuteRatio

## UI设计

### BreakoutScreen

与回踩页面保持一致风格：

```
┌─────────────────────────────────────────┐
│  AppBar: "放量突破"        [⚙️配置按钮]  │
├─────────────────────────────────────────┤
│  ℹ️ 突破量>1.5x 回踩1-5天 跌<2% 量<70%  │
│                                 12只    │
├─────────────────────────────────────────┤
│  StockTable (复用现有组件)              │
│  - 股票代码/名称                        │
│  - 涨跌幅                               │
│  - 分钟量比                             │
│  - 行业                                 │
│  - 长按添加自选                         │
└─────────────────────────────────────────┘
```

### BreakoutConfigDialog

配置弹窗包含以下字段：
- 突破日放量倍数（倍）
- 突破N日均线（天，0=不检测）
- 突破前N日高点（天，0=不检测）
- 最小回踩天数
- 最大回踩天数
- 最大平均日跌幅（%）
- 最大平均量比
- 最大分钟量比

## 数据流

```
MarketDataProvider.refresh()
       │
       ▼
下载分钟K线 → 计算分钟量比 → _allData
       │
       ▼
下载日K数据(15根) → _dailyBarsCache  ← 增加到15根
       │
       ├──→ _detectPullbacks() (现有回踩检测)
       │
       └──→ _detectBreakouts() (新增突破检测)
                  │
                  ▼
       BreakoutService.isBreakoutPullback()
                  │
                  ▼
       更新 StockMonitorData.isBreakout 字段
```

## 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/models/breakout_config.dart` | 新增 | 配置模型 |
| `lib/services/breakout_service.dart` | 新增 | 检测服务 |
| `lib/services/stock_service.dart` | 修改 | StockMonitorData 添加 isBreakout 字段 |
| `lib/providers/market_data_provider.dart` | 修改 | 添加 _detectBreakouts()，日K缓存增加到15根 |
| `lib/screens/breakout_screen.dart` | 新增 | 筛选页面 |
| `lib/widgets/breakout_config_dialog.dart` | 新增 | 配置弹窗 |
| `lib/main.dart` | 修改 | 注册 BreakoutService，添加 Tab |

## 默认配置值

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| breakVolumeMultiplier | 1.5 | 突破日成交量 > 前5日均量 × 1.5 |
| maBreakDays | 20 | 突破20日均线 |
| highBreakDays | 5 | 突破前5日高点 |
| minPullbackDays | 1 | 至少回踩1天 |
| maxPullbackDays | 5 | 最多回踩5天 |
| maxAvgDailyDrop | 0.02 | 平均日跌幅 < 2% |
| maxAvgVolumeRatio | 0.7 | 平均成交量 < 突破日的70% |
| maxMinuteRatio | 1.0 | 今日分钟量比 < 1.0 |
