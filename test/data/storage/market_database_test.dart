// test/data/storage/market_database_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/database_schema.dart';

void main() {
  setUpAll(() {
    // 初始化 FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    // 清理单例和数据库文件
    final db = MarketDatabase();
    try {
      await db.close();
    } catch (_) {}

    // 重置单例
    MarketDatabase.resetInstance();

    // 删除测试数据库文件
    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/${DatabaseSchema.databaseName}';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  group('MarketDatabase', () {
    test('should create database with correct schema', () async {
      final db = MarketDatabase();
      final database = await db.database;

      // 验证表存在
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'"
      );

      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames, contains('stocks'));
      expect(tableNames, contains('kline_files'));
      expect(tableNames, contains('data_versions'));

      await db.close();
    });

    test('should initialize with version 1', () async {
      final db = MarketDatabase();
      final version = await db.getCurrentVersion();

      expect(version, equals(1));

      await db.close();
    });

    test('should increment version correctly', () async {
      final db = MarketDatabase();
      final initialVersion = await db.getCurrentVersion();

      final newVersion = await db.incrementVersion('Test increment');

      expect(newVersion, equals(initialVersion + 1));
      expect(await db.getCurrentVersion(), equals(newVersion));

      await db.close();
    });
  });
}
