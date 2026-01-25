# 历史分钟K线数据统一管理

## 背景

当前 `IndustryTrendService` 和 `IndustryRankService` 各自独立拉取相同的分钟K线数据，存在以下问题：
1. 数据重复拉取，浪费带宽和时间
2. 两个服务的缓存独立管理，逻辑分散
3. 用户需要在行业页面分别触发两次数据拉取

## 设计目标

1. 合并为一次数据拉取，统一管理原始分钟K线
2. 支持增量拉取（只拉缺失的日期）
3. 数据管理集中到数据管理页面
4. 行业页面只负责重算和展示

## 架构设计

### 1. 新增 HistoricalKlineService

**职责：**
- 存储和管理原始分钟K线数据（持久化到本地）
- 支持增量拉取（判断缺失日期，只拉新数据）
- 提供数据查询接口给其他服务
- 自动清理超过30天的旧数据

**数据结构：**
```dart
class HistoricalKlineService extends ChangeNotifier {
  // 存储：按股票代码索引
  // stockCode -> List<KLine> (按时间升序排列)
  Map<String, List<KLine>> _stockBars;

  // 元数据
  DateTime? _lastFetchTime;      // 最后拉取时间
  Set<String> _completeDates;    // 已完整拉取的日期集合

  bool _isLoading;
}
```

**核心方法：**
```dart
/// 从本地缓存加载
Future<void> load();

/// 增量拉取缺失的日期
/// 返回本次拉取的天数
Future<int> fetchMissingDays(
  TdxPool pool,
  List<Stock> stocks,
  void Function(int current, int total)? onProgress,
);

/// 获取缺失天数（用于UI提示）
int getMissingDays();

/// 获取某只股票某天的K线
List<KLine> getBarsForDate(String stockCode, String dateKey);

/// 获取某只股票所有日期的涨跌量汇总
/// 返回 { dateKey: (upVolume, downVolume) }
Map<String, ({double up, double down})> getDailyVolumes(String stockCode);

/// 获取数据覆盖范围
({String? earliest, String? latest}) getDateRange();

/// 获取缓存大小（字节）
int getCacheSize();

/// 清空缓存
Future<void> clear();
```

**增量拉取逻辑：**
1. 计算需要覆盖的日期范围（最近30个交易日）
2. 对比 `_completeDates`，找出缺失的日期
3. 根据缺失天数计算需要拉取的K线页数
4. 拉取数据，合并到现有缓存
5. 更新 `_completeDates`

**存储格式（SharedPreferences 或文件）：**
```json
{
  "version": 1,
  "lastFetchTime": "2025-01-25T10:30:00",
  "completeDates": ["2025-01-24", "2025-01-23", ...],
  "stocks": {
    "000001": [
      {"dt": "2025-01-24 09:31", "o": 10.5, "h": 10.6, "l": 10.4, "c": 10.55, "v": 1000, "a": 10500},
      ...
    ],
    ...
  }
}
```

### 2. 改造 IndustryTrendService

**移除：**
- `fetchHistoricalData()` 方法
- 原始K线数据的存储和管理逻辑

**保留：**
- `calculateTodayTrend()` - 计算今日实时趋势（使用 StockMonitorData）
- `_trendData` 缓存 - 存储计算后的日度指标

**新增：**
```dart
/// 从历史K线数据重新计算趋势
/// 读取 HistoricalKlineService 的数据，计算 ratioAbovePercent
Future<void> recalculateFromKlineData(
  HistoricalKlineService klineService,
  List<StockMonitorData> stocks, // 用于获取行业分类
);
```

**计算逻辑：**
1. 从 `HistoricalKlineService` 获取每只股票的日度涨跌量
2. 计算每只股票每天的 ratio = upVolume / downVolume
3. 按行业分组，统计 ratio > 1 的股票占比
4. 更新 `_trendData` 缓存

### 3. 改造 IndustryRankService

**移除：**
- `fetchHistoricalData()` 方法
- 原始K线数据的存储和管理逻辑

**保留：**
- `calculateTodayRanks()` - 计算今日实时排名（使用 StockMonitorData）
- `_historyData` 缓存 - 存储历史排名数据

**新增：**
```dart
/// 从历史K线数据重新计算排名
/// 读取 HistoricalKlineService 的数据，计算聚合量比并排名
Future<void> recalculateFromKlineData(
  HistoricalKlineService klineService,
  List<StockMonitorData> stocks, // 用于获取行业分类
);
```

**计算逻辑：**
1. 从 `HistoricalKlineService` 获取每只股票的日度涨跌量
2. 按行业汇总：Σ涨量 / Σ跌量
3. 按聚合量比排名
4. 更新 `_historyData` 缓存

### 4. 改造 DataManagementScreen

**新增缓存项：**
```
┌─────────────────────────────────────────────┐
│  历史分钟K线                                 │
│  已覆盖: 2025-01-10 ~ 2025-01-24            │
│  缺失: 2天    大小: 856 MB                  │
│                          [拉取缺失] [清空]   │
└─────────────────────────────────────────────┘
```

**交互：**
- 点击"拉取缺失"：调用 `HistoricalKlineService.fetchMissingDays()`，显示进度
- 拉取完成后：自动触发 `IndustryTrendService` 和 `IndustryRankService` 重算

### 5. 改造 IndustryScreen

**移除：**
- `_fetchTrendData()` 方法
- `_fetchRankData()` 方法
- 相关的进度对话框逻辑

**新增：**
数据过期提示横幅（当 `HistoricalKlineService.getMissingDays() > 0` 时显示）：
```
┌─────────────────────────────────────────────┐
│ ⚠️ 历史数据缺失 3 天，部分趋势可能不准确      │
│                              [前往更新]      │
└─────────────────────────────────────────────┘
```

**保留：**
- 刷新按钮：触发重算（不拉取数据）
- Tab 切换和列表展示逻辑

## 数据流

```
┌──────────────────┐
│ DataManagement   │ ──拉取──▶ ┌─────────────────────┐
│ Screen           │           │ HistoricalKline     │
└──────────────────┘           │ Service             │
                               │ (原始分钟K线存储)    │
                               └─────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
           ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
           │ IndustryTrend │   │ IndustryRank  │   │ 其他服务...    │
           │ Service       │   │ Service       │   │               │
           │ (计算占比)     │   │ (计算聚合量比) │   │               │
           └───────────────┘   └───────────────┘   └───────────────┘
                    │                   │
                    ▼                   ▼
           ┌─────────────────────────────────────┐
           │         IndustryScreen              │
           │         (展示 + 重算)                │
           └─────────────────────────────────────┘
```

## 实现步骤

1. **创建 HistoricalKlineService**
   - 实现数据结构和持久化
   - 实现增量拉取逻辑
   - 添加到 Provider

2. **改造 DataManagementScreen**
   - 新增历史K线缓存管理项
   - 实现拉取和清空功能

3. **改造 IndustryTrendService**
   - 移除数据拉取逻辑
   - 添加 `recalculateFromKlineData()` 方法

4. **改造 IndustryRankService**
   - 移除数据拉取逻辑
   - 添加 `recalculateFromKlineData()` 方法

5. **改造 IndustryScreen**
   - 移除拉取相关代码
   - 添加数据过期提示横幅
   - 调整刷新按钮为重算

6. **测试和清理**
   - 端到端测试数据流
   - 清理废弃代码
