import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/storage/database_schema.dart';
import 'package:stock_rtwatcher/data/storage/industry_buildup_storage.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    final db = MarketDatabase();
    try {
      await db.close();
    } catch (_) {}

    MarketDatabase.resetInstance();

    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/${DatabaseSchema.databaseName}';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  IndustryBuildupDailyRecord record({
    required DateTime date,
    required String industry,
    required double zRel,
    required int rank,
    double rawScore = 0.0,
    double scoreEma = 0.0,
    int rankChange = 0,
    String rankArrow = '→',
  }) {
    return IndustryBuildupDailyRecord(
      date: date,
      industry: industry,
      zRel: zRel,
      zPos: zRel > 0 ? zRel : 0,
      breadth: 0.5,
      breadthGate: 1.0,
      q: 0.7,
      rawScore: rawScore,
      scoreEma: scoreEma,
      xI: 0.1,
      xM: 0.02,
      passedCount: 10,
      memberCount: 20,
      rank: rank,
      rankChange: rankChange,
      rankArrow: rankArrow,
      updatedAt: DateTime(2026, 2, 6, 16, 0),
    );
  }

  group('IndustryBuildUpStorage', () {
    test('upsertDailyResults stores records and updates latest date', () async {
      final storage = IndustryBuildUpStorage();

      await storage.upsertDailyResults([
        record(date: DateTime(2026, 2, 5), industry: '半导体', zRel: 1.2, rank: 1),
        record(date: DateTime(2026, 2, 6), industry: '军工', zRel: 0.9, rank: 2),
      ]);

      final latestDate = await storage.getLatestDate();

      expect(latestDate, isNotNull);
      expect(latestDate!.year, 2026);
      expect(latestDate.month, 2);
      expect(latestDate.day, 6);
    });

    test('getLatestBoard returns latest day sorted by rank asc', () async {
      final storage = IndustryBuildUpStorage();

      await storage.upsertDailyResults([
        record(date: DateTime(2026, 2, 6), industry: '军工', zRel: 1.1, rank: 2),
        record(date: DateTime(2026, 2, 6), industry: '半导体', zRel: 1.4, rank: 1),
        record(date: DateTime(2026, 2, 6), industry: '医药', zRel: 0.8, rank: 3),
      ]);

      final board = await storage.getLatestBoard(limit: 2);

      expect(board.length, 2);
      expect(board[0].industry, '半导体');
      expect(board[0].rank, 1);
      expect(board[1].industry, '军工');
      expect(board[1].rank, 2);
    });

    test('getIndustryTrend returns ascending zRel values by date', () async {
      final storage = IndustryBuildUpStorage();

      await storage.upsertDailyResults([
        record(
          date: DateTime(2026, 2, 4),
          industry: '半导体',
          zRel: 0.4,
          rawScore: 0.2,
          scoreEma: 0.2,
          rank: 3,
        ),
        record(
          date: DateTime(2026, 2, 5),
          industry: '半导体',
          zRel: 0.9,
          rawScore: 0.4,
          scoreEma: 0.3,
          rank: 2,
        ),
        record(
          date: DateTime(2026, 2, 6),
          industry: '半导体',
          zRel: 1.3,
          rawScore: 0.6,
          scoreEma: 0.5,
          rank: 1,
        ),
      ]);

      final trend = await storage.getIndustryTrend('半导体', days: 2);
      final rawTrend = await storage.getIndustryRawScoreTrend('半导体', days: 2);
      final emaTrend = await storage.getIndustryScoreEmaTrend('半导体', days: 2);
      final rankTrend = await storage.getIndustryRankTrend('半导体', days: 2);

      expect(trend, [0.9, 1.3]);
      expect(rawTrend, [0.4, 0.6]);
      expect(emaTrend, [0.3, 0.5]);
      expect(rankTrend, [2.0, 1.0]);
    });
  });
}
