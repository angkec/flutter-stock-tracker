# 突破日分钟量比条件设计

## 1. 功能概述

在多日回踩配置的「突破日条件」中增加「最小分钟量比」，用于过滤突破日当天分钟涨跌量比不达标的股票。

## 2. 数据流

```
HistoricalKlineService (已有)
    ↓ getDailyVolumes() 返回 { dateKey: (up, down) }
    ↓ 新增 getDailyRatio(stockCode, date)
BreakoutService
    ↓ 检测突破日时调用
    ↓ 过滤 ratio < minBreakoutMinuteRatio 的情况
```

利用现有计算层缓存，无需额外拉取数据。

## 3. 改动范围

| 文件 | 改动 |
|------|------|
| `lib/models/breakout_config.dart` | 新增 `minBreakoutMinuteRatio` 字段，`BreakoutDetectionResult` 新增 `minuteRatioCheck` |
| `lib/services/historical_kline_service.dart` | 新增 `getDailyRatio()` 方法 |
| `lib/services/breakout_service.dart` | 注入 `HistoricalKlineService`，检测时过滤，`getDetectionResult()` 返回分钟量比检测项 |
| `lib/widgets/breakout_config_dialog.dart` | 新增配置输入框 |
| `lib/main.dart` | 注入 `HistoricalKlineService` 到 `BreakoutService` |

## 4. 具体实现

### 4.1 BreakoutConfig 新增字段

```dart
// lib/models/breakout_config.dart

class BreakoutConfig {
  // === 突破日条件 === 区块内新增：
  /// 突破日最小分钟量比（0=不检测）
  final double minBreakoutMinuteRatio;

  const BreakoutConfig({
    // ... 已有参数 ...
    this.minBreakoutMinuteRatio = 0,  // 默认不检测，保持向后兼容
  });

  // copyWith、toJson、fromJson 同步更新
}
```

### 4.2 BreakoutDetectionResult 新增字段

```dart
// lib/models/breakout_config.dart

class BreakoutDetectionResult {
  // ... 已有字段 ...

  /// 分钟量比检测（突破日）
  final DetectionItem? minuteRatioCheck;

  const BreakoutDetectionResult({
    // ... 已有参数 ...
    this.minuteRatioCheck,
  });

  /// 突破日条件是否全部通过
  bool get breakoutPassed =>
      isUpDay.passed &&
      volumeCheck.passed &&
      (maBreakCheck?.passed ?? true) &&
      (highBreakCheck?.passed ?? true) &&
      (upperShadowCheck?.passed ?? true) &&
      (minuteRatioCheck?.passed ?? true);  // 新增

  /// 获取所有检测项
  List<DetectionItem> get allItems => [
    isUpDay,
    volumeCheck,
    if (maBreakCheck != null) maBreakCheck!,
    if (highBreakCheck != null) highBreakCheck!,
    if (upperShadowCheck != null) upperShadowCheck!,
    if (minuteRatioCheck != null) minuteRatioCheck!,  // 新增
  ];
}
```

### 4.3 HistoricalKlineService 新增方法

```dart
// lib/services/historical_kline_service.dart

/// 获取某只股票某日的分钟量比
/// 返回 null 表示数据不足或无法计算（涨停/跌停等）
Future<double?> getDailyRatio(String stockCode, DateTime date) async {
  final volumes = await getDailyVolumes(stockCode);
  final dateKey = formatDate(date);
  final dayVolume = volumes[dateKey];
  if (dayVolume == null || dayVolume.down == 0 || dayVolume.up == 0) {
    return null;
  }
  return dayVolume.up / dayVolume.down;
}
```

### 4.4 BreakoutService 改动

```dart
// lib/services/breakout_service.dart

class BreakoutService extends ChangeNotifier {
  // 新增依赖
  HistoricalKlineService? _historicalKlineService;

  void setHistoricalKlineService(HistoricalKlineService service) {
    _historicalKlineService = service;
  }

  // isBreakoutPullback() 改为异步，新增股票代码参数
  Future<bool> isBreakoutPullback(List<KLine> dailyBars, {String? stockCode}) async {
    // ... 原有逻辑 ...

    // 新增：检测突破日分钟量比
    if (_config.minBreakoutMinuteRatio > 0 &&
        stockCode != null &&
        _historicalKlineService != null) {
      final ratio = await _historicalKlineService!.getDailyRatio(
        stockCode,
        breakoutBar.datetime,
      );
      if (ratio == null || ratio < _config.minBreakoutMinuteRatio) {
        continue;  // 不满足条件，检查下一个可能的突破日
      }
    }

    // ... 后续逻辑 ...
  }

  // findBreakoutDays() 同样改为异步
  Future<Set<int>> findBreakoutDays(List<KLine> dailyBars, {String? stockCode}) async {
    // 类似改动
  }

  // getDetectionResult() 改为异步，新增股票代码参数
  Future<BreakoutDetectionResult?> getDetectionResult(
    List<KLine> dailyBars,
    int index,
    {String? stockCode}
  ) async {
    // ... 原有检测逻辑 ...

    // 新增：分钟量比检测
    DetectionItem? minuteRatioCheck;
    if (_config.minBreakoutMinuteRatio > 0 &&
        stockCode != null &&
        _historicalKlineService != null) {
      final ratio = await _historicalKlineService!.getDailyRatio(
        stockCode,
        bar.datetime,
      );
      minuteRatioCheck = DetectionItem(
        name: '分钟量比',
        passed: ratio != null && ratio >= _config.minBreakoutMinuteRatio,
        detail: ratio != null
          ? '${ratio.toStringAsFixed(2)} (需≥${_config.minBreakoutMinuteRatio})'
          : '数据不足',
      );
    }

    return BreakoutDetectionResult(
      // ... 原有字段 ...
      minuteRatioCheck: minuteRatioCheck,
    );
  }
}
```

### 4.5 依赖注入 (main.dart)

```dart
// lib/main.dart

// 在 BreakoutService 创建后注入 HistoricalKlineService
ChangeNotifierProvider<BreakoutService>(
  create: (_) {
    final service = BreakoutService();
    return service;
  },
),

// 在 MarketDataProvider 的 ProxyProvider 中注入
ChangeNotifierProxyProvider5<...>(
  update: (context, ..., previous) {
    final breakoutService = context.read<BreakoutService>();
    final historicalKlineService = context.read<HistoricalKlineService>();
    breakoutService.setHistoricalKlineService(historicalKlineService);
    // ...
  },
),
```

### 4.6 配置界面 (breakout_config_dialog.dart)

在「突破日条件」ExpansionTile 内，「最大上引线比例」下方新增：

```dart
_buildTextField(
  controller: _minBreakoutMinuteRatioController,
  label: '最小分钟量比',
  hint: '突破日分钟涨跌量比，0=不检测',
  suffix: '',
),
```

## 5. 调用方适配

由于方法改为异步，以下调用方需要适配：

| 文件 | 方法 | 改动 |
|------|------|------|
| `market_data_provider.dart` | `_applyBreakoutDetection()` | 改为 async，await 调用 |
| `stock_detail_screen.dart` | `getDetectionResult` 回调 | 改为 FutureBuilder 或预加载 |
| `backtest_service.dart` | 回测逻辑 | await 调用 |

## 6. 默认值与兼容性

- `minBreakoutMinuteRatio` 默认值为 `0`（不检测）
- `fromJson` 解析时若字段不存在，使用默认值 `0`
- 现有用户配置不受影响
