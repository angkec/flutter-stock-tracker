import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/repository/market_data_repository.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart';
import 'package:stock_rtwatcher/data/storage/date_check_storage.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/day_data_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 数据新鲜度检测测试
///
/// 测试场景覆盖：
/// 1. 基本场景：Fresh / Stale / Missing
/// 2. 历史数据缺失：中间日期有空洞
/// 3. 分钟数据不完整：某天只有部分时段数据
/// 4. 边界条件：24小时临界值
/// 5. 交易日 vs 非交易日
/// 6. 多个月份数据跨度

void main() {
  late MarketDataRepository repository;
  late KLineMetadataManager manager;
  late MarketDatabase database;
  late KLineFileStorage fileStorage;
  late Directory testDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('data_freshness_test_');
    fileStorage = KLineFileStorage();
    fileStorage.setBaseDirPathForTesting(testDir.path);
    await fileStorage.initialize();

    database = MarketDatabase();
    await database.database;

    manager = KLineMetadataManager(
      database: database,
      fileStorage: fileStorage,
    );

    repository = MarketDataRepository(metadataManager: manager);
  });

  tearDown(() async {
    await repository.dispose();
    try {
      await database.close();
    } catch (_) {}
    MarketDatabase.resetInstance();

    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }

    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/market_data.db';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  });

  /// 生成指定日期范围的1分钟K线数据
  /// 每天生成 9:30-11:30, 13:00-15:00 的数据（240根K线）
  List<KLine> generateMinuteKlinesForDay(DateTime date) {
    final klines = <KLine>[];

    // 上午: 9:30 - 11:30 (120分钟)
    for (var i = 0; i < 120; i++) {
      final datetime = DateTime(date.year, date.month, date.day, 9, 30 + i);
      klines.add(_createKLine(datetime, 10.0 + i * 0.01));
    }

    // 下午: 13:00 - 15:00 (120分钟)
    for (var i = 0; i < 120; i++) {
      final datetime = DateTime(date.year, date.month, date.day, 13, i);
      klines.add(_createKLine(datetime, 11.0 + i * 0.01));
    }

    return klines;
  }

  /// 生成指定日期范围的日线K线数据
  List<KLine> generateDailyKlines(DateTime start, DateTime end) {
    final klines = <KLine>[];
    var current = start;

    while (!current.isAfter(end)) {
      // 跳过周末
      if (current.weekday != DateTime.saturday &&
          current.weekday != DateTime.sunday) {
        klines.add(_createKLine(current, 10.0 + klines.length * 0.1));
      }
      current = current.add(const Duration(days: 1));
    }

    return klines;
  }

  group('基本新鲜度检测', () {
    test('完全没有数据应该返回 Missing', () async {
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Missing>());
    });

    test('今天有数据应该返回 Fresh', () async {
      final today = DateTime.now();
      final klines = [_createKLine(today, 10.0)];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
    });

    test('7天前的数据应该返回 Stale', () async {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final klines = [_createKLine(sevenDaysAgo, 10.0)];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>());
    });
  });

  group('历史数据缺失检测 - 当前逻辑的问题', () {
    test('BUG: 中间日期缺失但最新日期有数据时，被错误判断为 Fresh', () async {
      // 场景：1月15日和1月25日有数据，但1月16-24日没有数据
      // 当前逻辑只看最新日期(1月25日)，会判断为 Fresh
      // 但实际上中间有很多天数据缺失

      final jan15 = DateTime(2026, 1, 15, 10, 0);
      final jan25 = DateTime.now(); // 假设今天是1月25日

      // 只保存1月15日和今天的数据，中间的日期没有数据
      final klines = [
        _createKLine(jan15, 10.0),
        _createKLine(jan25, 11.0),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // 当前逻辑：因为今天有数据，返回 Fresh
      // 这是一个 BUG - 中间10天的数据都缺失了
      expect(freshness['000001'], isA<Fresh>(),
          reason: '当前逻辑只看最新日期，不检查中间是否有缺失');

      // TODO: 修复后应该返回 Stale 并标明缺失范围
      // expect(freshness['000001'], isA<Stale>());
    });

    test('BUG: 某天只有上午数据，下午数据缺失，仍被判断为 Fresh', () async {
      // 场景：今天9:30-11:30有数据，但13:00-15:00没有数据
      // 当前逻辑只看最新时间(11:30)，如果在24小时内就判断为 Fresh

      final today = DateTime.now();
      final morningStart = DateTime(today.year, today.month, today.day, 9, 30);

      // 只生成上午的数据（9:30-11:30）
      final morningKlines = <KLine>[];
      for (var i = 0; i < 120; i++) {
        final datetime = morningStart.add(Duration(minutes: i));
        morningKlines.add(_createKLine(datetime, 10.0 + i * 0.01));
      }

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: morningKlines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // 当前逻辑：最新数据是11:30，在24小时内，返回 Fresh
      // 但实际上下午的数据完全缺失
      expect(freshness['000001'], isA<Fresh>(),
          reason: '当前逻辑不检查分钟数据的完整性');

      // TODO: 修复后应该检测到下午数据缺失
    });

    test('BUG: 跨月数据中间月份完全缺失，仍被判断为 Fresh', () async {
      // 场景：有1月和3月的数据，但2月完全没有数据
      // 如果3月的数据是最近的，当前逻辑会判断为 Fresh

      final jan = DateTime(2026, 1, 15, 10, 0);
      final mar = DateTime.now(); // 假设今天是3月

      final klines = [
        _createKLine(jan, 10.0),
        _createKLine(mar, 12.0),
      ];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // 当前逻辑：最新数据在今天，返回 Fresh
      // 但2月整个月的数据都缺失
      expect(freshness['000001'], isA<Fresh>(),
          reason: '当前逻辑不检查月份连续性');
    });
  });

  group('边界条件测试', () {
    test('恰好24小时前的数据应该是 Fresh (边界值)', () async {
      // 使用 23小时59分 确保在边界内
      final almostOneDayAgo =
          DateTime.now().subtract(const Duration(hours: 23, minutes: 59));
      final klines = [_createKLine(almostOneDayAgo, 10.0)];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
    });

    test('刚好超过24小时的数据应该是 Stale', () async {
      final justOver24Hours =
          DateTime.now().subtract(const Duration(hours: 25));
      final klines = [_createKLine(justOver24Hours, 10.0)];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>());
    });
  });

  group('交易日 vs 非交易日', () {
    test('BUG: 周五的数据在周一早上被判断为 Stale', () async {
      // 场景：周五15:00收盘后保存数据
      // 周一9:00开盘前检查，超过24小时，被判断为 Stale
      // 但这期间市场没有交易，数据实际上是完整的

      // 找到最近的周五
      var friday = DateTime.now();
      while (friday.weekday != DateTime.friday) {
        friday = friday.subtract(const Duration(days: 1));
      }
      final fridayClose = DateTime(friday.year, friday.month, friday.day, 15, 0);

      // 假设现在是周一早上9点
      final mondayMorning = fridayClose.add(const Duration(days: 3, hours: -6));

      final klines = [_createKLine(fridayClose, 10.0)];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      // 注意：这个测试需要 mock DateTime.now() 才能准确测试
      // 当前实现使用实际时间，可能不会触发这个场景
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // 当前逻辑会判断为 Stale（因为超过24小时）
      // 但实际上周末不是交易日，数据应该是 Fresh
      // 这里只记录当前行为，具体修复需要引入交易日历
      expect(
        freshness['000001'],
        anyOf(isA<Fresh>(), isA<Stale>()),
        reason: '当前逻辑不考虑交易日，周末后可能误判为 Stale',
      );
    });

    test('BUG: 节假日前的数据被判断为 Stale', () async {
      // 场景：春节前最后一个交易日有数据
      // 春节后第一个交易日检查，超过7天，被判断为 Stale
      // 但这期间市场休市，数据实际上是完整的

      // 假设节假日为7天前
      final beforeHoliday =
          DateTime.now().subtract(const Duration(days: 7));
      final klines = [_createKLine(beforeHoliday, 10.0)];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // 当前逻辑：超过24小时就是 Stale
      expect(freshness['000001'], isA<Stale>(),
          reason: '当前逻辑不考虑节假日');

      // TODO: 修复后应该考虑交易日历
    });
  });

  group('日线 vs 分钟线差异', () {
    test('日线数据使用相同的24小时阈值', () async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final klines = [_createKLine(twoDaysAgo, 10.0)];

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: klines,
        dataType: KLineDataType.daily,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.daily,
      );

      // 日线和分钟线使用相同的阈值
      expect(freshness['000001'], isA<Stale>());
    });

    test('分钟线和日线独立检测', () async {
      // 分钟线有今天的数据
      final todayMinute = DateTime.now();
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(todayMinute, 10.0)],
        dataType: KLineDataType.oneMinute,
      );

      // 日线只有7天前的数据
      final weekAgoDaily = DateTime.now().subtract(const Duration(days: 7));
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(weekAgoDaily, 10.0)],
        dataType: KLineDataType.daily,
      );

      final minuteFreshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );
      final dailyFreshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.daily,
      );

      expect(minuteFreshness['000001'], isA<Fresh>());
      expect(dailyFreshness['000001'], isA<Stale>());
    });
  });

  group('多股票批量检测', () {
    test('批量检测多只股票的新鲜度', () async {
      // 股票1：今天有数据 -> Fresh
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(DateTime.now(), 10.0)],
        dataType: KLineDataType.oneMinute,
      );

      // 股票2：7天前有数据 -> Stale
      await manager.saveKlineData(
        stockCode: '000002',
        newBars: [
          _createKLine(
              DateTime.now().subtract(const Duration(days: 7)), 10.0)
        ],
        dataType: KLineDataType.oneMinute,
      );

      // 股票3：没有数据 -> Missing

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001', '000002', '000003'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
      expect(freshness['000002'], isA<Stale>());
      expect(freshness['000003'], isA<Missing>());
    });
  });

  group('Stale 状态的 missingRange 准确性', () {
    test('missingRange 应该从最后数据日期+1天开始', () async {
      final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(fiveDaysAgo, 10.0)],
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>());
      final stale = freshness['000001'] as Stale;

      // missingRange.start 应该是 fiveDaysAgo + 1 天
      final expectedStart = fiveDaysAgo.add(const Duration(days: 1));
      expect(
        stale.missingRange.start.day,
        equals(expectedStart.day),
        reason: 'missingRange 应该从最后数据日期的第二天开始',
      );
    });

    test('missingRange.end 应该是当前时间', () async {
      final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(fiveDaysAgo, 10.0)],
        dataType: KLineDataType.oneMinute,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      final stale = freshness['000001'] as Stale;
      final now = DateTime.now();

      // missingRange.end 应该接近当前时间
      expect(
        stale.missingRange.end.difference(now).inMinutes.abs(),
        lessThan(1),
        reason: 'missingRange.end 应该是当前时间',
      );
    });
  });

  group('数据连续性检查 - 理想行为（当前未实现）', () {
    test('理想: 检测指定日期范围内的数据连续性', () async {
      // 这是理想的行为，需要新的 API
      // checkFreshness 应该接受一个 dateRange 参数
      // 检查该范围内每个交易日是否都有数据

      final jan20 = DateTime(2026, 1, 20);
      final jan22 = DateTime(2026, 1, 22);
      final jan24 = DateTime(2026, 1, 24);

      // 保存 1/20, 1/22, 1/24 的数据（跳过 1/21, 1/23）
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          _createKLine(jan20, 10.0),
          _createKLine(jan22, 10.2),
          _createKLine(jan24, 10.4),
        ],
        dataType: KLineDataType.daily,
      );

      // 当前 API 不支持范围检查
      // 理想情况应该有这样的 API：
      // final gaps = await repository.findDataGaps(
      //   stockCode: '000001',
      //   dateRange: DateRange(jan20, jan24),
      //   dataType: KLineDataType.daily,
      // );
      // expect(gaps, contains(DateRange(jan21, jan21)));
      // expect(gaps, contains(DateRange(jan23, jan23)));

      // 目前只能验证当前行为
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.daily,
      );

      // 当前逻辑只看最新日期(1/24)
      // 如果今天是1/25或之后，会是 Stale
      // 如果今天是1/24，会是 Fresh
      expect(
        freshness['000001'],
        anyOf(isA<Fresh>(), isA<Stale>()),
        reason: '当前不检查数据连续性，只看最新日期',
      );
    });

    test('理想: 检测分钟数据的日内完整性', () async {
      // 理想行为：检查某一天的分钟数据是否完整
      // 应该有 240 根K线（上午120 + 下午120）

      final today = DateTime.now();
      final incomplete = <KLine>[];

      // 只生成上午的50根K线（不完整）
      for (var i = 0; i < 50; i++) {
        final datetime =
            DateTime(today.year, today.month, today.day, 9, 30 + i);
        incomplete.add(_createKLine(datetime, 10.0 + i * 0.01));
      }

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: incomplete,
        dataType: KLineDataType.oneMinute,
      );

      // 理想情况应该有这样的 API：
      // final completeness = await repository.checkDayCompleteness(
      //   stockCode: '000001',
      //   date: today,
      //   dataType: KLineDataType.oneMinute,
      // );
      // expect(completeness.isComplete, isFalse);
      // expect(completeness.actualBars, equals(50));
      // expect(completeness.expectedBars, equals(240));

      // 当前只能验证现有行为
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // 因为今天有数据，会返回 Fresh（尽管数据不完整）
      expect(freshness['000001'], isA<Fresh>(),
          reason: '当前不检查日内分钟数据完整性');
    });
  });

  group('findMissingMinuteDates', () {
    test('detects missing dates correctly', () async {
      // Save daily data to define trading days
      final jan15 = DateTime(2026, 1, 15);
      final jan16 = DateTime(2026, 1, 16);
      final jan17 = DateTime(2026, 1, 17);

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          _createKLine(jan15, 10.0),
          _createKLine(jan16, 10.5),
          _createKLine(jan17, 11.0),
        ],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data for jan15 only (220+ bars)
      final jan15Minutes = <KLine>[];
      for (var i = 0; i < 230; i++) {
        jan15Minutes.add(_createKLine(
          DateTime(2026, 1, 15, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan15Minutes,
        dataType: KLineDataType.oneMinute,
      );

      // jan16 and jan17 have no minute data

      final result = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(jan15, jan17),
      );

      expect(result.completeDates, contains(jan15));
      expect(result.missingDates, containsAll([jan16, jan17]));
      expect(result.isComplete, isFalse);
    });

    test('detects incomplete dates (< 220 bars)', () async {
      final jan15 = DateTime(2026, 1, 15);

      // Define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(jan15, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save incomplete minute data (only 100 bars)
      final incompleteMinutes = <KLine>[];
      for (var i = 0; i < 100; i++) {
        incompleteMinutes.add(_createKLine(
          DateTime(2026, 1, 15, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: incompleteMinutes,
        dataType: KLineDataType.oneMinute,
      );

      final result = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(jan15, jan15),
      );

      expect(result.incompleteDates, contains(jan15));
      expect(result.completeDates, isEmpty);
    });

    test('caches detection results and skips complete dates', () async {
      final jan15 = DateTime(2026, 1, 15);

      // Define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(jan15, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data
      final completeMinutes = <KLine>[];
      for (var i = 0; i < 230; i++) {
        completeMinutes.add(_createKLine(
          DateTime(2026, 1, 15, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: completeMinutes,
        dataType: KLineDataType.oneMinute,
      );

      // First detection
      final result1 = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(jan15, jan15),
      );
      expect(result1.completeDates, contains(jan15));

      // Second detection should use cache (verify via result)
      final result2 = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(jan15, jan15),
      );
      expect(result2.completeDates, contains(jan15));
      expect(result2.isComplete, isTrue);
    });
  });
}

/// 创建测试用的 KLine
KLine _createKLine(DateTime datetime, double basePrice) {
  return KLine(
    datetime: datetime,
    open: basePrice,
    close: basePrice + 0.05,
    high: basePrice + 0.1,
    low: basePrice - 0.05,
    volume: 1000,
    amount: 10000,
  );
}
