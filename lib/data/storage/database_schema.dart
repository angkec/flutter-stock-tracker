// lib/data/storage/database_schema.dart

class DatabaseSchema {
  static const int version = 6;
  static const String databaseName = 'market_data.db';

  // 股票基本信息表
  static const String createStocksTable = '''
    CREATE TABLE stocks (
      code TEXT PRIMARY KEY,
      name TEXT,
      market INTEGER,
      created_at INTEGER
    )
  ''';

  // K线文件索引表
  static const String createKlineFilesTable = '''
    CREATE TABLE kline_files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      stock_code TEXT NOT NULL,
      data_type TEXT NOT NULL,
      year_month TEXT NOT NULL,
      file_path TEXT NOT NULL,
      start_date INTEGER,
      end_date INTEGER,
      record_count INTEGER,
      checksum TEXT,
      file_size INTEGER,
      created_at INTEGER,
      updated_at INTEGER,
      UNIQUE(stock_code, data_type, year_month)
    )
  ''';

  static const String createKlineFilesStockIndex = '''
    CREATE INDEX idx_kline_files_stock
    ON kline_files(stock_code, data_type)
  ''';

  static const String createKlineFilesDateIndex = '''
    CREATE INDEX idx_kline_files_date
    ON kline_files(year_month)
  ''';

  // 数据版本控制表
  static const String createDataVersionsTable = '''
    CREATE TABLE data_versions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      version INTEGER NOT NULL,
      description TEXT,
      created_at INTEGER
    )
  ''';

  // 初始化版本记录
  static const String insertInitialVersion = '''
    INSERT INTO data_versions (version, description, created_at)
    VALUES (1, 'Initial version', ?)
  ''';

  // 日期检测状态表（新增）
  static const String createDateCheckStatusTable = '''
    CREATE TABLE date_check_status (
      stock_code TEXT NOT NULL,
      data_type TEXT NOT NULL,
      date INTEGER NOT NULL,
      status TEXT NOT NULL,
      bar_count INTEGER DEFAULT 0,
      checked_at INTEGER NOT NULL,
      PRIMARY KEY (stock_code, data_type, date)
    )
  ''';

  static const String createDateCheckStatusIndex = '''
    CREATE INDEX idx_date_check_pending
    ON date_check_status(stock_code, data_type, status)
    WHERE status != 'complete'
  ''';

  // 行业建仓雷达日结果表
  static const String createIndustryBuildupDailyTable = '''
    CREATE TABLE industry_buildup_daily (
      date INTEGER NOT NULL,
      industry TEXT NOT NULL,
      z_rel REAL NOT NULL,
      z_pos REAL NOT NULL DEFAULT 0,
      breadth REAL NOT NULL,
      breadth_gate REAL NOT NULL DEFAULT 0.5,
      q REAL NOT NULL,
      raw_score REAL NOT NULL DEFAULT 0,
      score_ema REAL NOT NULL DEFAULT 0,
      x_i REAL NOT NULL,
      x_m REAL NOT NULL,
      passed_count INTEGER NOT NULL,
      member_count INTEGER NOT NULL,
      rank INTEGER NOT NULL,
      rank_change INTEGER NOT NULL DEFAULT 0,
      rank_arrow TEXT NOT NULL DEFAULT '→',
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (date, industry)
    )
  ''';

  static const String createIndustryBuildupDateRankIndex = '''
    CREATE INDEX idx_buildup_date_rank
    ON industry_buildup_daily(date, rank)
  ''';

  static const String createIndustryBuildupIndustryDateIndex = '''
    CREATE INDEX idx_buildup_industry_date
    ON industry_buildup_daily(industry, date)
  ''';

  // 分钟线同步状态表
  static const String createMinuteSyncStateTable = '''
    CREATE TABLE minute_sync_state (
      stock_code TEXT PRIMARY KEY,
      last_complete_trading_day INTEGER,
      last_success_fetch_at INTEGER,
      last_attempt_at INTEGER,
      consecutive_failures INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const String createMinuteSyncStateUpdatedAtIndex = '''
    CREATE INDEX idx_minute_sync_state_updated_at
    ON minute_sync_state(updated_at)
  ''';

  // 日线同步状态表
  static const String createDailySyncStateTable = '''
    CREATE TABLE daily_sync_state (
      stock_code TEXT PRIMARY KEY,
      last_intraday_date INTEGER,
      last_finalized_date INTEGER,
      last_fingerprint TEXT,
      updated_at INTEGER NOT NULL
    )
  ''';

  static const String createDailySyncStateUpdatedAtIndex = '''
    CREATE INDEX idx_daily_sync_state_updated_at
    ON daily_sync_state(updated_at)
  ''';
}
