# 分钟数据缺失检测设计

## 问题背景

当前 `checkFreshness` 逻辑**只看最新数据的日期**，存在以下问题：

| 场景 | 当前行为 | 问题 |
|------|----------|------|
| 中间日期缺失（1/15和1/25有数据，1/16-24缺失） | `Fresh` | 只看最新日期，不检查连续性 |
| 某天只有上午数据，下午缺失 | `Fresh` | 不检查分钟数据完整性 |
| 跨月数据中间月份缺失 | `Fresh` | 不检查月份连续性 |
| 周五数据在周一检查 | `Stale` | 不考虑周末非交易日 |

## 设计目标

1. 精确检测分钟数据缺失（按天粒度）
2. 缓存检测结果，避免重复扫描
3. 区分交易日和非交易日
4. 正确处理当天交易进行中的情况

## 数据模型

### 日期状态枚举

```dart
// lib/data/models/day_data_status.dart

/// 单日数据状态
enum DayDataStatus {
  complete,    // 数据完整（分钟K线 >= 220）
  incomplete,  // 历史日期数据不完整（< 220，需要补全）
  missing,     // 完全没有数据
  inProgress,  // 当天，交易进行中（不视为缺失）
}

/// 日期缺失检测结果
class MissingDatesResult {
  /// 缺失的日期列表（完全没有数据）
  final List<DateTime> missingDates;

  /// 不完整的日期列表（数据 < 220，需要重新拉取）
  final List<DateTime> incompleteDates;

  /// 完整的日期列表
  final List<DateTime> completeDates;

  const MissingDatesResult({
    required this.missingDates,
    required this.incompleteDates,
    required this.completeDates,
  });

  /// 是否全部完整
  bool get isComplete => missingDates.isEmpty && incompleteDates.isEmpty;

  /// 需要拉取的日期（合并 missing + incomplete）
  List<DateTime> get datesToFetch => [...missingDates, ...incompleteDates]..sort();

  /// 需要拉取的日期数量
  int get fetchCount => missingDates.length + incompleteDates.length;
}
```

## 数据库变更

### 新增表

```sql
-- database_schema.dart 升级到 version 2

CREATE TABLE date_check_status (
  stock_code TEXT NOT NULL,
  data_type TEXT NOT NULL,      -- 'oneMinute' / 'daily'
  date INTEGER NOT NULL,        -- 日期时间戳（只保留日期部分）
  status TEXT NOT NULL,         -- 'complete' / 'incomplete' / 'missing'
  bar_count INTEGER DEFAULT 0,  -- 实际K线数量
  checked_at INTEGER NOT NULL,  -- 检测时间戳
  PRIMARY KEY (stock_code, data_type, date)
);

-- 快速查询未完成的日期
CREATE INDEX idx_date_check_pending
  ON date_check_status(stock_code, data_type, status)
  WHERE status != 'complete';
```

### 缓存策略

| 状态 | 是否缓存 | 下次检测行为 |
|------|----------|--------------|
| `complete` | ✅ 永久缓存 | 跳过 |
| `incomplete` | ✅ 缓存 | 重新检测（可能已补全） |
| `missing` | ✅ 缓存 | 重新检测（可能已拉取） |
| `inProgress` | ❌ 不缓存 | 次日重新检测 |

## API 设计

### DataRepository 接口新增

```dart
abstract class DataRepository {
  // ... 现有方法保持不变 ...

  /// 查找缺失的分钟数据日期
  ///
  /// [stockCode] 股票代码
  /// [dateRange] 检测的日期范围
  ///
  /// 利用缓存加速：已标记为 complete 的日期会跳过
  Future<MissingDatesResult> findMissingMinuteDates({
    required String stockCode,
    required DateRange dateRange,
  });

  /// 批量查找多只股票的缺失日期
  Future<Map<String, MissingDatesResult>> findMissingMinuteDatesBatch({
    required List<String> stockCodes,
    required DateRange dateRange,
    ProgressCallback? onProgress,
  });

  /// 获取交易日列表（从日K数据推断）
  ///
  /// 某天只要有任意股票有日K数据，就认为是交易日
  Future<List<DateTime>> getTradingDates(DateRange dateRange);
}
```

### API 分层

```dart
// 第一层：快速检查（现有 API，内部实现改为读取缓存）
checkFreshness()
  → 读取 date_check_status 缓存
  → 返回 Fresh / Stale / Missing

// 第二层：精确检测（新增 API）
findMissingMinuteDates()
  → 实际扫描数据
  → 写入 date_check_status 缓存
  → 返回详细的缺失日期列表
```

## 检测逻辑

### findMissingMinuteDates 实现

```dart
Future<MissingDatesResult> findMissingMinuteDates({
  required String stockCode,
  required DateRange dateRange,
}) async {

  // 1. 获取交易日列表（从日K数据推断）
  final tradingDates = await getTradingDates(dateRange);

  // 2. 查询已检测状态（从 date_check_status 表）
  final checkedStatus = await _dateCheckStorage.getCheckedStatus(
    stockCode: stockCode,
    dataType: KLineDataType.oneMinute,
    dates: tradingDates,
  );

  // 3. 分类处理
  final missingDates = <DateTime>[];
  final incompleteDates = <DateTime>[];
  final completeDates = <DateTime>[];
  final toCheckDates = <DateTime>[];

  for (final date in tradingDates) {
    final status = checkedStatus[date];

    if (status == null) {
      // 未检测过，需要检测
      toCheckDates.add(date);
    } else if (status == DayDataStatus.complete) {
      // 已完整，跳过
      completeDates.add(date);
    } else {
      // incomplete 或 missing，需要重新检测
      toCheckDates.add(date);
    }
  }

  // 4. 实际检测未确认的日期
  final today = DateTime.now();

  for (final date in toCheckDates) {
    final barCount = await _countBarsForDate(
      stockCode: stockCode,
      date: date,
      dataType: KLineDataType.oneMinute,
    );

    final isToday = _isSameDay(date, today);

    DayDataStatus status;
    if (barCount == 0) {
      status = DayDataStatus.missing;
      missingDates.add(date);
    } else if (barCount >= 220) {
      status = DayDataStatus.complete;
      completeDates.add(date);
    } else if (isToday) {
      // 当天数据不完整是正常的（交易进行中）
      status = DayDataStatus.inProgress;
      // 不加入任何列表，也不缓存
    } else {
      status = DayDataStatus.incomplete;
      incompleteDates.add(date);
    }

    // 5. 保存检测状态（inProgress 不保存）
    if (status != DayDataStatus.inProgress) {
      await _dateCheckStorage.saveCheckStatus(
        stockCode: stockCode,
        dataType: KLineDataType.oneMinute,
        date: date,
        status: status,
        barCount: barCount,
      );
    }
  }

  return MissingDatesResult(
    missingDates: missingDates,
    incompleteDates: incompleteDates,
    completeDates: completeDates,
  );
}
```

### checkFreshness 改进

```dart
Future<Map<String, DataFreshness>> checkFreshness({
  required List<String> stockCodes,
  required KLineDataType dataType,
}) async {
  final result = <String, DataFreshness>{};

  for (final stockCode in stockCodes) {
    // 1. 查询未完成的日期（排除当天）
    final pendingDates = await _dateCheckStorage.getPendingDates(
      stockCode: stockCode,
      dataType: dataType,
      excludeToday: true,
    );

    if (pendingDates.isNotEmpty) {
      // 有未完成的历史日期 → Stale
      result[stockCode] = Stale(
        missingRange: DateRange(
          pendingDates.first,
          pendingDates.last,
        ),
      );
      continue;
    }

    // 2. 检查最新检测日期
    final latestCheckedDate = await _dateCheckStorage.getLatestCheckedDate(
      stockCode: stockCode,
      dataType: dataType,
    );

    if (latestCheckedDate == null) {
      // 从未检测过 → Missing
      result[stockCode] = const Missing();
      continue;
    }

    // 3. 判断是否有新的未检测日期
    final now = DateTime.now();
    final daysSinceLastCheck = now.difference(latestCheckedDate).inDays;

    if (daysSinceLastCheck > 1) {
      // 可能有新的交易日未检测 → Stale
      result[stockCode] = Stale(
        missingRange: DateRange(
          latestCheckedDate.add(const Duration(days: 1)),
          now,
        ),
      );
    } else {
      // 数据完整 → Fresh
      result[stockCode] = const Fresh();
    }
  }

  return result;
}
```

### 交易日推断

```dart
/// 从日K数据推断交易日
Future<List<DateTime>> getTradingDates(DateRange range) async {
  // 查询所有股票的日K数据中出现的日期
  // 某天只要有任意股票有日K，就认为是交易日
  final db = await _database.database;

  final rows = await db.rawQuery('''
    SELECT DISTINCT date(datetime(start_date/1000, 'unixepoch')) as trade_date
    FROM kline_files
    WHERE data_type = 'daily'
      AND start_date >= ?
      AND end_date <= ?
    ORDER BY trade_date
  ''', [range.start.millisecondsSinceEpoch, range.end.millisecondsSinceEpoch]);

  return rows.map((row) => DateTime.parse(row['trade_date'] as String)).toList();
}
```

## 使用场景

### 场景1：App 启动

```dart
// 快速检查，利用缓存
final freshness = await repository.checkFreshness(
  stockCodes: watchlist,
  dataType: KLineDataType.oneMinute,
);

for (final entry in freshness.entries) {
  if (entry.value is Stale || entry.value is Missing) {
    // 拉取最近 N 天数据
    await repository.fetchMissingData(...);
  }
}
```

### 场景2：用户点击"检查数据完整性"

```dart
// 精确检测过去3个月
final result = await repository.findMissingMinuteDates(
  stockCode: '000001',
  dateRange: DateRange(threeMonthsAgo, today),
);

if (!result.isComplete) {
  showDialog('发现 ${result.fetchCount} 天数据缺失，是否补全？');

  if (confirmed) {
    for (final date in result.datesToFetch) {
      await repository.fetchMissingData(
        stockCodes: ['000001'],
        dateRange: DateRange(date, date),
        dataType: KLineDataType.oneMinute,
      );
    }
  }
}
```

### 场景3：后台定期扫描

```dart
// 批量检测 watchlist
final results = await repository.findMissingMinuteDatesBatch(
  stockCodes: watchlist,
  dateRange: DateRange(oneMonthAgo, today),
  onProgress: (current, total) => updateProgress(current / total),
);

// 自动补全
for (final entry in results.entries) {
  if (!entry.value.isComplete) {
    await repository.fetchMissingData(...);
  }
}
```

## 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `lib/data/models/day_data_status.dart` | 新增 | 日期状态枚举 + MissingDatesResult |
| `lib/data/storage/date_check_storage.dart` | 新增 | 检测状态的数据库操作 |
| `lib/data/storage/database_schema.dart` | 修改 | 升级到 version 2，新增表 |
| `lib/data/storage/market_database.dart` | 修改 | 添加迁移逻辑 |
| `lib/data/repository/data_repository.dart` | 修改 | 新增接口方法 |
| `lib/data/repository/market_data_repository.dart` | 修改 | 实现新接口 + 改进 checkFreshness |
| `test/data/repository/data_freshness_test.dart` | 修改 | 更新测试用例 |

## 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 分钟数据完整阈值 | 220 | 每天 >= 220 根K线视为完整 |
| 理论分钟K线数 | 240 | 上午120 + 下午120 |
| 交易日来源 | 日K数据 | 从已有日K数据推断交易日 |
