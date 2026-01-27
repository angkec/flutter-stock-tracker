# 盯喵数据架构重构设计

## 1. 概述与问题分析

### 1.1 当前架构问题

**数据管理混乱**
- 数据拉取和数据处理混在一起，职责不清晰
- 不同业务服务（StockService、IndustryRankService、BreakoutService）各自拉取数据，导致重复请求
- 例如：同一只股票的1分钟K线被 StockService（240条）、HistoricalKlineService（800条/页）重复拉取

**持久化不稳定**
- 元数据和数据文件分两步保存，中间崩溃导致状态不一致
- 迁移时先删除旧数据再写新数据，写入失败造成永久数据丢失
- SharedPreferences 写入大数据无大小校验，Android 6KB 限制导致静默失败
- 内存状态与磁盘状态分离，写入失败后数据不一致

**增量更新失败**
- 无事务保证，部分写入导致数据损坏
- 无 checksum 校验，数据完整性无法验证
- Debounce 保存机制，app 退出前可能丢失最近的修改

**关键问题汇总（来自代码分析）**

| 问题 | 严重程度 | 文件 | 行号 | 影响 |
|------|----------|------|------|--------|
| Race condition: metadata saved but K-line save fails | CRITICAL | historical_kline_service.dart | 471-497 | 数据损坏 |
| Large data write to SharedPreferences without size check | CRITICAL | market_data_provider.dart | 297 | 静默数据丢失 |
| Config updated in memory but SharedPreferences write fails | HIGH | industry_rank_service.dart | 250-259 | 状态分离 |
| Old data deleted before new data persists | HIGH | historical_kline_service.dart | 434-435 | 永久数据丢失 |
| No validation that persistence callbacks succeed | HIGH | stock_service.dart | 238 | 失败被忽略 |
| K-line data fetched 3x by different services | MEDIUM | Multiple services | N/A | 浪费带宽 |

---

### 1.2 重构目标

**职责分离**
- 数据层：负责数据拉取、增量更新、持久化，提供统一的数据源
- 计算层：基于数据层进行分析计算，缓存计算结果
- 展示层：监听数据状态，触发刷新，显示结果

**数据完整性保证**
- 原子写入：数据要么全部写入成功，要么完全不写入
- Checksum 校验：写入后验证数据完整性
- 事务语义：元数据和数据文件状态一致

**消除重复拉取**
- 统一的数据入口，所有服务从数据层获取 K线/行情数据
- 数据层内部管理去重和缓存
- 减少网络请求，提升性能

**可靠的增量更新**
- 按月分片存储，只修改当前月份的数据文件
- 历史数据不再改动，避免损坏风险
- 支持断点续传和错误恢复

---

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                   展示层 (Presentation)                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ Industry │  │ Breakout │  │ Pullback │  │ Stock   │ │
│  │  Screen  │  │  Screen  │  │  Screen  │  │ Detail  │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
│       │              │              │            │       │
│       └──────────────┴──────────────┴────────────┘       │
│                      订阅状态 Stream                      │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    计算层 (Analysis)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   Industry   │  │   Breakout   │  │   Pullback   │  │
│  │ RankService  │  │   Service    │  │   Service    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│         │监听数据更新事件│                │              │
│         └─────────────┬─────────────────┘              │
│                       │ 请求K线数据                     │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                     数据层 (Data)                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │            DataRepository (核心)                 │   │
│  │  · 增量拉取 K线/行情数据                         │   │
│  │  · 按月分片持久化                                │   │
│  │  · 数据完整性校验                                │   │
│  │  · 暴露 Stream<DataStatus> + 命令接口            │   │
│  └─────────────────────────────────────────────────┘   │
│                                                          │
│  持久化存储：                                            │
│  ┌──────────────┐     ┌──────────────────────────┐     │
│  │   SQLite     │     │   文件系统 (按月分片)    │     │
│  │  · 股票元数据│     │  · 000001_1min_2024-01.bin.gz │     │
│  │  · 文件索引  │     │  · 000001_1min_2024-02.bin.gz │     │
│  │  · Checksum  │     │  · ...                   │     │
│  └──────────────┘     └──────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
```

### 2.2 通信机制

**Stream + 命令模式**

数据流向：
- **向上传播**：数据层 → Stream → 计算层/展示层（状态通知）
- **向下调用**：展示层/计算层 → 命令方法 → 数据层（触发操作）

```dart
// 示例
// 1. 展示层监听数据状态
dataRepository.statusStream.listen((status) {
  if (status is DataStale) {
    showSnackBar('数据过时，请刷新');
  }
});

// 2. 用户点击刷新按钮
onRefreshPressed() {
  await dataRepository.fetchMissingData(dateRange);
}

// 3. 数据层拉取完成后发出事件
dataRepository.dataUpdatedStream.emit(DataUpdatedEvent(...));

// 4. 计算层监听到事件，重新计算
industryRankService.dataUpdatedStream.listen((event) {
  recalculateRanking(event.date);
});
```

---

## 3. 数据层详细设计

### 3.1 持久化方案：SQLite + 按月分片文件

**存储结构**

```
app_documents/
└─ market_data/
    ├─ market_data.db (SQLite数据库)
    └─ klines/
        ├─ 000001_1min_2024-01.bin.gz
        ├─ 000001_1min_2024-02.bin.gz
        ├─ 000001_daily_2024.bin.gz
        ├─ 000002_1min_2024-01.bin.gz
        └─ ...
```

**SQLite 表结构**

```sql
-- 股票基本信息
CREATE TABLE stocks (
  code TEXT PRIMARY KEY,
  name TEXT,
  market INTEGER,
  created_at INTEGER
);

-- K线文件索引
CREATE TABLE kline_files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  stock_code TEXT NOT NULL,
  data_type TEXT NOT NULL,  -- '1min' or 'daily'
  year_month TEXT NOT NULL, -- '2024-01'
  file_path TEXT NOT NULL,
  start_date INTEGER,       -- Unix timestamp
  end_date INTEGER,
  record_count INTEGER,
  checksum TEXT,            -- SHA256
  file_size INTEGER,
  created_at INTEGER,
  updated_at INTEGER,
  UNIQUE(stock_code, data_type, year_month)
);

CREATE INDEX idx_kline_files_stock ON kline_files(stock_code, data_type);
CREATE INDEX idx_kline_files_date ON kline_files(year_month);

-- 数据版本控制
CREATE TABLE data_versions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  version INTEGER NOT NULL,
  description TEXT,
  created_at INTEGER
);
```

---

### 3.2 数据层核心接口

```dart
/// 数据仓库 - 唯一的数据源
class DataRepository {
  // ============ 状态流 ============

  /// 数据状态流
  Stream<DataStatus> get statusStream;

  /// 数据更新事件流
  Stream<DataUpdatedEvent> get dataUpdatedStream;

  // ============ 查询接口 ============

  /// 获取K线数据（优先从缓存读取）
  ///
  /// [stockCodes] 股票代码列表
  /// [dateRange] 日期范围
  /// [dataType] 数据类型 '1min' 或 'daily'
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  });

  /// 检查数据新鲜度
  ///
  /// 返回每只股票的数据状态：
  /// - fresh: 数据完整
  /// - stale: 数据过时，需要拉取
  /// - missing: 完全缺失
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  });

  /// 获取实时行情
  Future<Map<String, Quote>> getQuotes({
    required List<String> stockCodes,
  });

  // ============ 命令接口 ============

  /// 拉取缺失数据（增量更新）
  ///
  /// [stockCodes] 需要更新的股票列表
  /// [dateRange] 需要拉取的日期范围
  /// [dataType] 数据类型
  ///
  /// 返回拉取结果统计
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  });

  /// 强制重新拉取（覆盖现有数据）
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  });

  /// 清理旧数据
  ///
  /// [beforeDate] 清理此日期之前的数据
  Future<void> cleanupOldData({
    required DateTime beforeDate,
  });
}
```

---

### 3.3 状态定义

```dart
/// 数据状态
sealed class DataStatus {
  const DataStatus();
}

/// 就绪
class DataReady extends DataStatus {
  final int dataVersion;
  const DataReady(this.dataVersion);
}

/// 数据过时
class DataStale extends DataStatus {
  final List<String> missingStockCodes;
  final DateRange missingRange;
  const DataStale({
    required this.missingStockCodes,
    required this.missingRange,
  });
}

/// 拉取中
class DataFetching extends DataStatus {
  final int current;
  final int total;
  final String currentStock;
  const DataFetching({
    required this.current,
    required this.total,
    required this.currentStock,
  });
}

/// 错误
class DataError extends DataStatus {
  final String message;
  final Exception? exception;
  const DataError(this.message, [this.exception]);
}

/// 数据更新事件
class DataUpdatedEvent {
  final List<String> stockCodes;
  final DateRange dateRange;
  final KLineDataType dataType;
  final int dataVersion;

  const DataUpdatedEvent({
    required this.stockCodes,
    required this.dateRange,
    required this.dataType,
    required this.dataVersion,
  });
}
```

---

### 3.4 增量写入流程（核心）

**按月分片 + 临时文件 + 原子重命名**

```dart
/// 增量追加K线数据
Future<void> _appendKlineData({
  required String stockCode,
  required List<KLine> newBars,
  required KLineDataType dataType,
}) async {
  // 1. 按月份分组新数据
  final barsByMonth = _groupByMonth(newBars);

  for (final entry in barsByMonth.entries) {
    final yearMonth = entry.key; // '2024-01'
    final monthBars = entry.value;

    // 2. 读取该月份的现有数据
    final existingBars = await _loadMonthlyKlineFile(
      stockCode: stockCode,
      yearMonth: yearMonth,
      dataType: dataType,
    );

    // 3. 合并去重（按时间戳）
    final merged = _mergeAndDeduplicate(existingBars, monthBars);

    // 4. 序列化 + 压缩
    final compressed = await compute(_serializeAndCompress, merged);

    // 5. 计算 checksum
    final checksum = _calculateSHA256(compressed);

    // 6. 写入临时文件
    final tempFile = File(_getTempFilePath(stockCode, yearMonth, dataType));
    await tempFile.writeAsBytes(compressed);

    // 7. 验证写入完整性
    final writtenChecksum = _calculateSHA256(await tempFile.readAsBytes());
    if (writtenChecksum != checksum) {
      await tempFile.delete();
      throw DataIntegrityException('Checksum mismatch');
    }

    // 8. 原子重命名（操作系统保证原子性）
    final targetFile = File(_getFilePath(stockCode, yearMonth, dataType));
    await tempFile.rename(targetFile.path);

    // 9. 更新 SQLite 索引（事务）
    await _db.transaction((txn) async {
      await txn.insert(
        'kline_files',
        {
          'stock_code': stockCode,
          'data_type': dataType.name,
          'year_month': yearMonth,
          'file_path': targetFile.path,
          'start_date': merged.first.datetime.millisecondsSinceEpoch,
          'end_date': merged.last.datetime.millisecondsSinceEpoch,
          'record_count': merged.length,
          'checksum': checksum,
          'file_size': compressed.length,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 更新数据版本
      await txn.rawInsert(
        'INSERT INTO data_versions (version, description, created_at) VALUES (?, ?, ?)',
        [_currentVersion + 1, 'Updated $stockCode $yearMonth', DateTime.now().millisecondsSinceEpoch],
      );
    });

    _currentVersion++;
  }
}
```

**关键保证：**
- ✅ 临时文件 + 原子重命名：确保旧数据不会损坏
- ✅ Checksum 校验：写入后验证完整性
- ✅ SQLite 事务：索引和版本号原子更新
- ✅ 按月分片：只操作当前月份文件，历史数据不动

---

### 3.5 数据新鲜度检查

```dart
/// 检查数据新鲜度（简化策略）
Future<DataFreshness> checkFreshness(
  String stockCode,
  KLineDataType dataType,
) async {
  final now = DateTime.now();

  // 周末不检查
  if (now.weekday >= 6) {
    return DataFreshness.fresh();
  }

  // 查询最新数据日期
  final result = await _db.query(
    'kline_files',
    columns: ['end_date'],
    where: 'stock_code = ? AND data_type = ?',
    whereArgs: [stockCode, dataType.name],
    orderBy: 'end_date DESC',
    limit: 1,
  );

  if (result.isEmpty) {
    return DataFreshness.missing();
  }

  final latestDate = DateTime.fromMillisecondsSinceEpoch(
    result.first['end_date'] as int,
  );

  // 简单规则：
  // - 工作日 15:00 前：本地有昨天数据即可
  // - 工作日 15:00 后：需要今天数据
  final requiredDate = now.hour < 15
      ? now.subtract(Duration(days: 1))
      : now;

  if (latestDate.isBefore(requiredDate.startOfDay)) {
    return DataFreshness.stale(
      missingRange: DateRange(latestDate.add(Duration(days: 1)), now),
    );
  }

  return DataFreshness.fresh();
}
```

---

## 4. 计算层详细设计

### 4.1 职责与原则

**计算层职责**
- 基于数据层的 K线/行情数据进行分析计算
- 持久化计算结果（带版本控制）
- 监听数据更新事件，判断是否需要重算
- 对外暴露计算结果和计算状态

**设计原则**
- 不直接拉取原始数据，只从数据层获取
- 计算结果可缓存，避免重复计算
- 算法版本化，支持批量重算
- 计算失败不影响其他模块

---

### 4.2 持久化方案

**存储结构**

```
app_documents/
└─ market_data/
    ├─ market_data.db (SQLite - 复用数据层的数据库)
    └─ analysis/
        ├─ industry_rank_2024-01.json.gz
        ├─ industry_rank_2024-02.json.gz
        ├─ breakout_signals_2024-01.json.gz
        └─ ...
```

**SQLite 表结构**

```sql
-- 计算结果索引
CREATE TABLE analysis_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  result_type TEXT NOT NULL,      -- 'industry_rank', 'breakout', 'pullback'
  date INTEGER NOT NULL,           -- Unix timestamp (按天)
  algorithm_version TEXT NOT NULL, -- 算法版本号，如 'v1.0.0'
  data_version INTEGER NOT NULL,   -- 依赖的数据版本
  file_path TEXT,                  -- 结果文件路径
  record_count INTEGER,
  created_at INTEGER,
  updated_at INTEGER,
  UNIQUE(result_type, date)
);

CREATE INDEX idx_analysis_type_date ON analysis_results(result_type, date);
CREATE INDEX idx_analysis_version ON analysis_results(algorithm_version);

-- 算法版本记录
CREATE TABLE algorithm_versions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  service_name TEXT NOT NULL,     -- 'IndustryRankService', 'BreakoutService'
  version TEXT NOT NULL,
  description TEXT,
  created_at INTEGER,
  UNIQUE(service_name, version)
);
```

---

### 4.3 计算服务接口（以 IndustryRankService 为例）

```dart
/// 行业排名服务
class IndustryRankService {
  final DataRepository _dataRepo;
  final Database _db;

  // 当前算法版本
  static const String algorithmVersion = 'v1.0.0';

  // ============ 状态流 ============

  /// 计算状态流
  Stream<AnalysisStatus> get statusStream => _statusController.stream;
  final _statusController = StreamController<AnalysisStatus>.broadcast();

  /// 计算结果流
  Stream<IndustryRankResult> get resultStream => _resultController.stream;
  final _resultController = StreamController<IndustryRankResult>.broadcast();

  // ============ 查询接口 ============

  /// 获取指定日期的行业排名（优先从缓存）
  Future<IndustryRankResult?> getRanking({
    required DateTime date,
  }) async {
    // 1. 检查缓存
    final cached = await _loadCachedResult(date);
    if (cached != null) {
      return cached;
    }

    // 2. 缓存未命中，需要计算
    _statusController.add(AnalysisStatus.calculating());

    try {
      final result = await _calculateRanking(date);
      await _saveResult(date, result);
      _statusController.add(AnalysisStatus.ready(result));
      return result;
    } catch (e) {
      _statusController.add(AnalysisStatus.error(e.toString()));
      return null;
    }
  }

  /// 获取日期范围的排名数据（用于回测）
  Future<List<IndustryRankResult>> getRankingRange({
    required DateRange dateRange,
  }) async {
    final results = <IndustryRankResult>[];

    for (var date = dateRange.start;
         date.isBefore(dateRange.end);
         date = date.add(Duration(days: 1))) {
      final result = await getRanking(date: date);
      if (result != null) {
        results.add(result);
      }
    }

    return results;
  }

  // ============ 命令接口 ============

  /// 强制重新计算（忽略缓存）
  Future<void> recalculate({
    required DateTime date,
  }) async {
    await _invalidateCache(date);
    await getRanking(date: date);
  }

  /// 批量重算（算法版本更新后）
  Future<void> recalculateAll({
    required DateRange dateRange,
    ProgressCallback? onProgress,
  }) async {
    final dates = _generateTradingDays(dateRange);

    for (var i = 0; i < dates.length; i++) {
      await recalculate(date: dates[i]);
      onProgress?.call(i + 1, dates.length);
    }
  }

  // ============ 内部实现 ============

  /// 初始化 - 监听数据更新事件
  void _init() {
    _dataRepo.dataUpdatedStream.listen((event) {
      _onDataUpdated(event);
    });
  }

  /// 数据更新事件处理
  Future<void> _onDataUpdated(DataUpdatedEvent event) async {
    // 检查受影响的日期
    for (var date = event.dateRange.start;
         date.isBefore(event.dateRange.end);
         date = date.add(Duration(days: 1))) {

      final cached = await _getCachedMetadata(date);

      // 判断是否需要重算
      if (cached == null ||
          cached.dataVersion < event.dataVersion ||
          cached.algorithmVersion != algorithmVersion) {

        // 标记缓存失效
        _statusController.add(AnalysisStatus.stale(date));

        // 可选：自动重算（也可以等展示层触发）
        // await recalculate(date: date);
      }
    }
  }

  /// 执行计算（混合策略）
  Future<IndustryRankResult> _calculateRanking(DateTime date) async {
    final stockCodes = await _getActiveStockCodes();

    // 根据数据量选择计算策略
    if (stockCodes.length <= 200) {
      // 少量股票：主线程直接计算
      return _calculateInMainThread(date, stockCodes);
    } else {
      // 大量股票：分批计算
      return _calculateInBatches(date, stockCodes);
    }
  }

  /// 主线程直接计算（少量股票）
  Future<IndustryRankResult> _calculateInMainThread(
    DateTime date,
    List<String> stockCodes,
  ) async {
    final klineData = await _dataRepo.getKlines(
      stockCodes: stockCodes,
      dateRange: DateRange(date.subtract(Duration(days: 60)), date),
      dataType: KLineDataType.oneMinute,
    );

    final metrics = <String, StockMetrics>{};
    for (final entry in klineData.entries) {
      metrics[entry.key] = _calculateStockMetrics(entry.value, date);
    }

    return _aggregateIndustryRanking(metrics);
  }

  /// 分批计算（大量股票）
  Future<IndustryRankResult> _calculateInBatches(
    DateTime date,
    List<String> stockCodes,
  ) async {
    const batchSize = 100;
    final allMetrics = <String, StockMetrics>{};

    for (var i = 0; i < stockCodes.length; i += batchSize) {
      final batch = stockCodes.skip(i).take(batchSize).toList();

      // 获取这批股票的 K线
      final klineData = await _dataRepo.getKlines(
        stockCodes: batch,
        dateRange: DateRange(date.subtract(Duration(days: 60)), date),
        dataType: KLineDataType.oneMinute,
      );

      // 计算这批的指标
      for (final code in batch) {
        allMetrics[code] = _calculateStockMetrics(klineData[code]!, date);
      }

      // Yield 让 UI 刷新
      await Future.delayed(Duration.zero);

      // 更新进度
      _statusController.add(
        AnalysisCalculating('已处理 ${allMetrics.length}/${stockCodes.length} 只股票'),
      );
    }

    // 汇总行业排名
    return _aggregateIndustryRanking(allMetrics);
  }

  /// 加载缓存结果
  Future<IndustryRankResult?> _loadCachedResult(DateTime date) async {
    // 1. 查询 SQLite 索引
    final metadata = await _getCachedMetadata(date);

    if (metadata == null) return null;

    // 2. 检查版本
    if (metadata.algorithmVersion != algorithmVersion) {
      return null; // 算法版本不匹配，缓存失效
    }

    // 3. 检查数据版本
    final currentDataVersion = await _dataRepo.getCurrentVersion();
    if (metadata.dataVersion < currentDataVersion) {
      return null; // 数据已更新，缓存失效
    }

    // 4. 读取结果文件
    final file = File(metadata.filePath);
    if (!await file.exists()) return null;

    final compressed = await file.readAsBytes();
    final json = await compute(_decompress, compressed);
    return IndustryRankResult.fromJson(json);
  }

  /// 保存计算结果
  Future<void> _saveResult(DateTime date, IndustryRankResult result) async {
    final yearMonth = DateFormat('yyyy-MM').format(date);
    final filePath = path.join(
      _analysisDir,
      'industry_rank_$yearMonth.json.gz',
    );

    // 1. 序列化 + 压缩
    final json = result.toJson();
    final compressed = await compute(_compress, json);

    // 2. 写入文件
    final file = File(filePath);
    await file.writeAsBytes(compressed);

    // 3. 更新 SQLite 索引
    final dataVersion = await _dataRepo.getCurrentVersion();

    await _db.insert(
      'analysis_results',
      {
        'result_type': 'industry_rank',
        'date': date.millisecondsSinceEpoch,
        'algorithm_version': algorithmVersion,
        'data_version': dataVersion,
        'file_path': filePath,
        'record_count': result.ranks.length,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
```

---

### 4.4 计算状态定义

```dart
/// 计算状态
sealed class AnalysisStatus {
  const AnalysisStatus();
}

/// 就绪
class AnalysisReady extends AnalysisStatus {
  final dynamic result; // IndustryRankResult / BreakoutResult 等
  const AnalysisReady(this.result);
}

/// 计算中
class AnalysisCalculating extends AnalysisStatus {
  final String message;
  const AnalysisCalculating([this.message = '计算中...']);
}

/// 缓存过时
class AnalysisStale extends AnalysisStatus {
  final DateTime affectedDate;
  const AnalysisStale(this.affectedDate);
}

/// 错误
class AnalysisError extends AnalysisStatus {
  final String message;
  const AnalysisError(this.message);
}
```

---

### 4.5 其他计算服务

**BreakoutService / PullbackService**
- 接口设计类似 IndustryRankService
- 也持久化计算结果（信号检测结果）
- 监听数据更新，重新检测信号

**BacktestService**
- 不持久化结果（回测是一次性操作）
- 直接从数据层和其他计算服务获取数据
- 在 isolate 中运行回测逻辑

---

## 5. 迁移策略

### 5.1 迁移原则

**渐进式迁移**
- 不做大爆炸式重写，逐模块迁移
- 新旧架构共存期间保持功能正常
- 每个阶段都是可发布的稳定状态

**数据安全第一**
- 迁移前备份现有数据
- 保留旧数据直到新架构验证通过
- 提供回滚机制

**用户体验不降级**
- 迁移过程中 app 仍可使用
- 后台静默迁移数据
- 迁移完成前使用旧逻辑

---

### 5.2 迁移阶段

#### 阶段 1：数据层实现（2-3周）

**目标：实现新的数据层，但不影响现有功能**

**任务清单：**

1. **创建新的数据层模块**
   ```
   lib/data/
   ├── repository/
   │   ├── data_repository.dart
   │   └── data_repository_impl.dart
   ├── storage/
   │   ├── kline_storage.dart          (SQLite + 文件)
   │   └── quote_storage.dart          (实时行情)
   ├── fetcher/
   │   ├── kline_fetcher.dart          (复用 TdxClient/TdxPool)
   │   └── incremental_fetcher.dart    (增量拉取逻辑)
   └── models/
       ├── data_status.dart
       └── fetch_result.dart
   ```

2. **实现 SQLite 数据库**
   - 创建表结构（stocks, kline_files, data_versions）
   - 实现索引管理
   - 实现事务封装

3. **实现按月分片文件存储**
   - 临时文件 + 原子重命名
   - Checksum 校验
   - 压缩/解压缩

4. **实现增量拉取逻辑**
   - 数据新鲜度检查
   - 去重合并
   - 进度通知

5. **编写单元测试**
   - 测试写入安全性（模拟崩溃）
   - 测试增量更新
   - 测试数据完整性校验

**验收标准：**
- ✅ 所有单元测试通过
- ✅ 可以独立拉取和存储 K线数据
- ✅ 不影响现有功能（还未接入业务层）

---

#### 阶段 2：数据迁移工具（1周）

**目标：将现有数据迁移到新存储格式**

**任务清单：**

1. **实现数据迁移服务**
   ```dart
   class DataMigrationService {
     /// 迁移 HistoricalKlineService 的数据到新格式
     Future<MigrationResult> migrateHistoricalKlines();

     /// 迁移 MarketDataProvider 的缓存
     Future<MigrationResult> migrateMarketDataCache();

     /// 验证迁移结果
     Future<bool> verifyMigration();
   }
   ```

2. **在 DataManagementScreen 添加迁移入口**
   ```dart
   // 显示迁移按钮
   ElevatedButton(
     onPressed: () => _startMigration(),
     child: Text('迁移到新数据格式'),
   )
   ```

3. **后台迁移 + 进度显示**
   - 不阻塞 UI
   - 显示迁移进度
   - 支持暂停/恢复

**验收标准：**
- ✅ 旧数据完整迁移到新格式
- ✅ 新旧数据对比一致
- ✅ 旧数据保留（未删除）

---

#### 阶段 3：计算层改造（2-3周）

**目标：改造现有计算服务，使用新数据层**

**任务清单：**

1. **改造 IndustryRankService**
   - 移除自己拉取 K线的逻辑
   - 从 `DataRepository` 获取数据
   - 实现计算结果持久化
   - 监听数据更新事件

2. **改造 BreakoutService**
   - 同上

3. **改造 PullbackService**
   - 同上

4. **实现混合计算策略**
   ```dart
   // 根据数据量选择计算方式
   if (stockCodes.length <= 200) {
     return _calculateInMainThread(date, stockCodes);
   } else {
     return _calculateInBatches(date, stockCodes);
   }
   ```

5. **保留旧逻辑作为 fallback**
   ```dart
   try {
     // 尝试用新数据层
     result = await _calculateWithNewDataLayer(date);
   } catch (e) {
     // 失败时回退到旧逻辑
     debugPrint('New data layer failed, fallback to old: $e');
     result = await _calculateWithOldDataLayer(date);
   }
   ```

**验收标准：**
- ✅ 计算结果与旧逻辑一致
- ✅ 性能不降级（应该更快）
- ✅ 有 fallback 保证稳定性

---

#### 阶段 4：展示层接入（1-2周）

**目标：UI 监听新的状态流，触发新的命令**

**任务清单：**

1. **改造 MarketDataProvider**
   ```dart
   class MarketDataProvider extends ChangeNotifier {
     final DataRepository _dataRepo;

     void init() {
       // 监听数据状态
       _dataRepo.statusStream.listen((status) {
         if (status is DataStale) {
           _showStaleDataBanner = true;
           notifyListeners();
         }
       });
     }

     Future<void> refresh() async {
       // 使用新数据层拉取
       await _dataRepo.fetchMissingData(...);
     }
   }
   ```

2. **更新各个 Screen**
   - IndustryScreen
   - BreakoutScreen
   - StockDetailScreen
   - 显示"数据过时"提示
   - 响应刷新命令

3. **移除旧的拉取逻辑**
   ```dart
   // 删除：
   // - StockService.batchGetMonitorData()
   // - MarketDataProvider._fetchDailyBars()
   // - 各种 onBarsData 回调
   ```

**验收标准：**
- ✅ UI 功能完全正常
- ✅ 没有重复拉取
- ✅ 数据刷新逻辑清晰

---

#### 阶段 5：清理与优化（1周）

**目标：删除旧代码，优化性能**

**任务清单：**

1. **删除旧数据管理代码**
   - HistoricalKlineService（旧版）
   - MarketDataProvider 中的 dailyBarsCache
   - SharedPreferences 中的大数据缓存

2. **清理旧数据文件**
   ```dart
   // 提供工具清理旧的 SharedPreferences 数据
   Future<void> cleanupOldCache() async {
     final prefs = await SharedPreferences.getInstance();
     await prefs.remove('historical_kline_cache_v1');
     await prefs.remove('daily_bars_cache_v1');
     await prefs.remove('market_data_cache');
   }
   ```

3. **性能测试**
   - 对比迁移前后的启动速度
   - 对比刷新速度
   - 对比内存占用

4. **用户指南**
   - 更新 DataManagementScreen 说明文字
   - 添加"数据管理"帮助文档

**验收标准：**
- ✅ 代码库清理干净
- ✅ 性能有提升
- ✅ 用户体验优化

---

### 5.3 风险控制

**回滚机制**

```dart
class DataLayerConfig {
  // 功能开关
  static bool useNewDataLayer = true;

  // 在发现问题时可以快速切回旧逻辑
  static void rollback() {
    useNewDataLayer = false;
    debugPrint('Rolled back to old data layer');
  }
}

// 业务代码中
if (DataLayerConfig.useNewDataLayer) {
  return await _newLogic();
} else {
  return await _oldLogic();
}
```

**灰度发布**
- 先在少数用户（beta）上验证
- 逐步扩大到全部用户
- 监控崩溃率和性能指标

**数据备份**
```dart
// 迁移前自动备份
Future<void> backupOldData() async {
  final backupDir = Directory('${appDir}/backup_${DateTime.now().millisecondsSinceEpoch}');
  await backupDir.create(recursive: true);

  // 复制旧数据文件
  // ...
}
```

---

### 5.4 时间估算

| 阶段 | 时间 | 里程碑 |
|------|------|--------|
| 阶段1：数据层实现 | 2-3周 | 新数据层可用 |
| 阶段2：数据迁移 | 1周 | 旧数据迁移完成 |
| 阶段3：计算层改造 | 2-3周 | 计算服务接入新数据层 |
| 阶段4：展示层接入 | 1-2周 | UI 完全使用新架构 |
| 阶段5：清理与优化 | 1周 | 旧代码删除 |
| **总计** | **7-10周** | **重构完成** |

---

### 5.5 成功指标

**功能指标**
- ✅ 数据不再重复拉取
- ✅ 持久化成功率 100%（无数据丢失）
- ✅ 增量更新可靠（支持断点续传）

**性能指标**
- ✅ 启动速度提升 30%+
- ✅ 数据刷新速度提升 50%+
- ✅ 内存占用降低 20%+

**代码质量**
- ✅ 职责分离清晰
- ✅ 代码可测试性提高
- ✅ 技术债降低

---

## 6. 总结

这次重构的核心思想是**职责分离 + 数据可靠性**：

1. **数据层**：统一的数据入口，按月分片 + SQLite 索引，原子写入保证安全
2. **计算层**：纯粹的计算逻辑，结果持久化 + 版本控制，混合计算策略平衡性能
3. **展示层**：监听状态，触发命令，职责单一

重构后的架构将解决当前的核心问题：
- ❌ 数据重复拉取 → ✅ 统一数据源
- ❌ 持久化失败 → ✅ 原子写入 + Checksum
- ❌ 代码混乱 → ✅ 清晰的三层分离
- ❌ 增量失败 → ✅ 按月分片 + 事务保证

---

## 附录：数据量估算

### 基本参数
- A股市场：约 5000 只股票
- 交易时间：每天 4小时 = 240 条 1分钟K线
- 交易日：约 250 天/年

### 存储场景

**场景1：监控模式（当前模式）**
- 监控股票：500-1000 只（行业排名 + 自选 + 突破股）
- 存储时长：1 年历史
- 1分钟K线：`800 只 × 240条/天 × 250天 = 4800万条`
- 单条数据：40 bytes（OHLCV + 时间戳）
- **总量：1.9 GB（未压缩）→ 压缩后约 500 MB**

**场景2：全市场模式**
- 5000 只全市场股票
- **总量：12 GB（未压缩）→ 压缩后约 3 GB**

**日K线数据**
- 5000 只 × 250 天 × 40 bytes = **50 MB/年**（可忽略）
