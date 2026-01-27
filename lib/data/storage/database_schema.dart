// lib/data/storage/database_schema.dart

class DatabaseSchema {
  static const int version = 1;
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
}
