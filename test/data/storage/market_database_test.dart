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
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      final tableNames = tables.map((t) => t['name'] as String).toList();
      expect(tableNames, contains('stocks'));
      expect(tableNames, contains('kline_files'));
      expect(tableNames, contains('data_versions'));
      expect(tableNames, contains('date_check_status'));
      expect(tableNames, contains('industry_buildup_daily'));

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

  group('Database schema version 2', () {
    late MarketDatabase database;

    setUp(() {
      database = MarketDatabase();
    });

    test('should have date_check_status table after initialization', () async {
      final db = await database.database;

      // Query sqlite_master to check if table exists
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='date_check_status'",
      );

      expect(tables, isNotEmpty);
      expect(tables.first['name'], equals('date_check_status'));
    });

    test('date_check_status table should have correct columns', () async {
      final db = await database.database;

      final columns = await db.rawQuery("PRAGMA table_info(date_check_status)");
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, contains('stock_code'));
      expect(columnNames, contains('data_type'));
      expect(columnNames, contains('date'));
      expect(columnNames, contains('status'));
      expect(columnNames, contains('bar_count'));
      expect(columnNames, contains('checked_at'));
    });
  });

  group('Database schema version 4', () {
    late MarketDatabase database;

    setUp(() {
      database = MarketDatabase();
    });

    test(
      'should have industry_buildup_daily table after initialization',
      () async {
        final db = await database.database;

        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='industry_buildup_daily'",
        );

        expect(tables, isNotEmpty);
        expect(tables.first['name'], equals('industry_buildup_daily'));
      },
    );

    test('industry_buildup_daily table should have correct columns', () async {
      final db = await database.database;

      final columns = await db.rawQuery(
        "PRAGMA table_info(industry_buildup_daily)",
      );
      final columnNames = columns.map((c) => c['name'] as String).toList();

      expect(columnNames, contains('date'));
      expect(columnNames, contains('industry'));
      expect(columnNames, contains('z_rel'));
      expect(columnNames, contains('z_pos'));
      expect(columnNames, contains('breadth'));
      expect(columnNames, contains('breadth_gate'));
      expect(columnNames, contains('q'));
      expect(columnNames, contains('raw_score'));
      expect(columnNames, contains('score_ema'));
      expect(columnNames, contains('x_i'));
      expect(columnNames, contains('x_m'));
      expect(columnNames, contains('passed_count'));
      expect(columnNames, contains('member_count'));
      expect(columnNames, contains('rank'));
      expect(columnNames, contains('rank_change'));
      expect(columnNames, contains('rank_arrow'));
      expect(columnNames, contains('updated_at'));
    });
  });
}
