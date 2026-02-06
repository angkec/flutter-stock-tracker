// lib/data/storage/market_database.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_schema.dart';

class MarketDatabase {
  static MarketDatabase? _instance;
  static Database? _database;
  static Future<Database>? _initFuture;

  MarketDatabase._();

  factory MarketDatabase() {
    _instance ??= MarketDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    // If initialization is in progress, wait for it
    if (_initFuture != null) {
      return await _initFuture!;
    }

    // Start initialization
    _initFuture = _initDatabase();
    try {
      _database = await _initFuture!;
      return _database!;
    } finally {
      _initFuture = null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, DatabaseSchema.databaseName);

    return await openDatabase(
      path,
      version: DatabaseSchema.version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 创建表
    await db.execute(DatabaseSchema.createStocksTable);
    await db.execute(DatabaseSchema.createKlineFilesTable);
    await db.execute(DatabaseSchema.createDataVersionsTable);
    await db.execute(DatabaseSchema.createDateCheckStatusTable); // 新增
    await db.execute(DatabaseSchema.createIndustryBuildupDailyTable);

    // 创建索引
    await db.execute(DatabaseSchema.createKlineFilesStockIndex);
    await db.execute(DatabaseSchema.createKlineFilesDateIndex);
    await db.execute(DatabaseSchema.createDateCheckStatusIndex); // 新增
    await db.execute(DatabaseSchema.createIndustryBuildupDateRankIndex);
    await db.execute(DatabaseSchema.createIndustryBuildupIndustryDateIndex);

    // 插入初始版本
    await db.rawInsert(DatabaseSchema.insertInitialVersion, [
      DateTime.now().millisecondsSinceEpoch,
    ]);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Version 1 -> 2: Add date_check_status table
      await db.execute(DatabaseSchema.createDateCheckStatusTable);
      await db.execute(DatabaseSchema.createDateCheckStatusIndex);
    }
    if (oldVersion < 3) {
      // Version 2 -> 3: Add industry buildup daily table
      await db.execute(DatabaseSchema.createIndustryBuildupDailyTable);
      await db.execute(DatabaseSchema.createIndustryBuildupDateRankIndex);
      await db.execute(DatabaseSchema.createIndustryBuildupIndustryDateIndex);
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _initFuture = null;
  }

  // 重置单例（仅用于测试）
  static void resetInstance() {
    _instance = null;
    _database = null;
    _initFuture = null;
  }

  // 获取当前数据版本
  Future<int> getCurrentVersion() async {
    final db = await database;
    final result = await db.query(
      'data_versions',
      columns: ['version'],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (result.isEmpty) return DatabaseSchema.version;
    return result.first['version'] as int;
  }

  // 增加数据版本
  Future<int> incrementVersion(String description) async {
    final db = await database;
    final currentVersion = await getCurrentVersion();
    final newVersion = currentVersion + 1;

    await db.insert('data_versions', {
      'version': newVersion,
      'description': description,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    return newVersion;
  }
}
