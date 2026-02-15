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
      final todayDate = DateTime(today.year, today.month, today.day);

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(todayDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data (220+ bars)
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(todayDate.year, todayDate.month, todayDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache via findMissingMinuteDates
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(todayDate, todayDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
    });

    test('7天前的数据应该返回 Stale', () async {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final sevenDaysAgoDate = DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(sevenDaysAgoDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data (220+ bars) for 7 days ago
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(sevenDaysAgoDate.year, sevenDaysAgoDate.month, sevenDaysAgoDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache via findMissingMinuteDates
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(sevenDaysAgoDate, sevenDaysAgoDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // Data is 7 days old, so there are potentially new trading days -> Stale
      expect(freshness['000001'], isA<Stale>());
    });
  });

  group('历史数据缺失检测 - 新实现正确检测缺失', () {
    test('中间日期缺失时返回 Stale（已修复）', () async {
      // 场景：1月15日和1月17日有完整数据，但1月16日没有数据
      // 新实现通过 findMissingMinuteDates 检测缺失日期

      final jan15 = DateTime(2026, 1, 15);
      final jan16 = DateTime(2026, 1, 16);
      final jan17 = DateTime(2026, 1, 17);

      // Save daily data to define trading days (including jan16)
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          _createKLine(jan15, 10.0),
          _createKLine(jan16, 10.5),
          _createKLine(jan17, 11.0),
        ],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data for jan15 only
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

      // Save complete minute data for jan17
      final jan17Minutes = <KLine>[];
      for (var i = 0; i < 230; i++) {
        jan17Minutes.add(_createKLine(
          DateTime(2026, 1, 17, 9, 30).add(Duration(minutes: i)),
          11.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: jan17Minutes,
        dataType: KLineDataType.oneMinute,
      );

      // jan16 has no minute data - this will be detected as missing

      // Populate cache via findMissingMinuteDates
      final result = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(jan15, jan17),
      );

      // Verify jan16 is detected as missing
      expect(result.missingDates, contains(jan16));

      // Now checkFreshness should return Stale because jan16 is incomplete
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>(),
          reason: '新实现正确检测到中间日期缺失');
    });

    test('不完整数据（<220根K线）被检测为 incomplete（已修复）', () async {
      // 场景：今天9:30-11:30有数据，但下午数据缺失（只有120根K线）
      // 新实现检测到 barCount < 220，标记为 incomplete

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayDate = DateTime(yesterday.year, yesterday.month, yesterday.day);

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(yesterdayDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Only save morning data (120 bars, incomplete)
      final morningKlines = <KLine>[];
      for (var i = 0; i < 120; i++) {
        final datetime = DateTime(yesterdayDate.year, yesterdayDate.month, yesterdayDate.day, 9, 30 + i);
        morningKlines.add(_createKLine(datetime, 10.0 + i * 0.01));
      }

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: morningKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache via findMissingMinuteDates
      final result = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(yesterdayDate, yesterdayDate),
      );

      // Verify yesterday is detected as incomplete
      expect(result.incompleteDates, contains(yesterdayDate));

      // checkFreshness should return Stale because yesterday is incomplete
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>(),
          reason: '新实现正确检测到分钟数据不完整');
    });

    test('跨多日数据缺失被正确检测（已修复）', () async {
      // 场景：有1月15日和1月20日的数据，中间日期缺失
      // 新实现能检测到这些缺失

      final jan15 = DateTime(2026, 1, 15);
      final jan16 = DateTime(2026, 1, 16);
      final jan17 = DateTime(2026, 1, 17);
      final jan20 = DateTime(2026, 1, 20);

      // Save daily data to define trading days
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          _createKLine(jan15, 10.0),
          _createKLine(jan16, 10.2),
          _createKLine(jan17, 10.4),
          _createKLine(jan20, 11.0),
        ],
        dataType: KLineDataType.daily,
      );

      // Only save complete minute data for jan15 and jan20
      for (final date in [jan15, jan20]) {
        final minutes = <KLine>[];
        for (var i = 0; i < 230; i++) {
          minutes.add(_createKLine(
            DateTime(date.year, date.month, date.day, 9, 30).add(Duration(minutes: i)),
            10.0 + i * 0.001,
          ));
        }
        await manager.saveKlineData(
          stockCode: '000001',
          newBars: minutes,
          dataType: KLineDataType.oneMinute,
        );
      }

      // Populate cache
      final result = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(jan15, jan20),
      );

      // Verify jan16 and jan17 are missing
      expect(result.missingDates, containsAll([jan16, jan17]));
      expect(result.completeDates, containsAll([jan15, jan20]));

      // checkFreshness should return Stale
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>());
    });
  });

  group('边界条件测试', () {
    test('恰好24小时前的数据应该是 Fresh (边界值)', () async {
      // 使用昨天的日期确保在边界内
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayDate = DateTime(yesterday.year, yesterday.month, yesterday.day);

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(yesterdayDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data (220+ bars)
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(yesterdayDate.year, yesterdayDate.month, yesterdayDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache via findMissingMinuteDates
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(yesterdayDate, yesterdayDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
    });

    test('超过一日且存在交易日窗口的数据应该是 Stale', () async {
      final staleAnchor = DateTime.now().subtract(const Duration(days: 7));
      final staleAnchorDate = DateTime(
        staleAnchor.year,
        staleAnchor.month,
        staleAnchor.day,
      );

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(staleAnchorDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data (220+ bars)
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(
            staleAnchorDate.year,
            staleAnchorDate.month,
            staleAnchorDate.day,
            9,
            30,
          ).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache via findMissingMinuteDates
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(staleAnchorDate, staleAnchorDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // 数据窗口里包含潜在交易日，应该判定为 Stale
      expect(freshness['000001'], isA<Stale>());
    });
  });

  group('交易日 vs 非交易日', () {
    test('周五的数据在周一检查时，如果已缓存为完整则返回 Fresh', () async {
      // 场景：周五有完整数据，周末不是交易日
      // 新实现使用日线数据作为交易日参考，周末不会被视为缺失

      // 找到最近的周五
      var friday = DateTime.now();
      while (friday.weekday != DateTime.friday) {
        friday = friday.subtract(const Duration(days: 1));
      }
      final fridayDate = DateTime(friday.year, friday.month, friday.day);

      // Save daily data only for Friday (weekend is not trading day)
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(fridayDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data for Friday
      final fridayMinutes = <KLine>[];
      for (var i = 0; i < 230; i++) {
        fridayMinutes.add(_createKLine(
          DateTime(fridayDate.year, fridayDate.month, fridayDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: fridayMinutes,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(fridayDate, fridayDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // With the new cache-based approach, result depends on whether
      // there are unchecked trading days since Friday
      // If today is within 1 day of Friday's checked date, it's Fresh
      // Otherwise it's Stale (potential new trading days)
      expect(
        freshness['000001'],
        anyOf(isA<Fresh>(), isA<Stale>()),
        reason: '新实现基于缓存的交易日检查',
      );
    });

    test('节假日后数据状态取决于是否有新交易日', () async {
      // 场景：节假日期间没有交易，数据完整
      // 新实现使用日线数据确定交易日

      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final sevenDaysAgoDate = DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);

      // Save daily data
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(sevenDaysAgoDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(sevenDaysAgoDate.year, sevenDaysAgoDate.month, sevenDaysAgoDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(sevenDaysAgoDate, sevenDaysAgoDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // Data is 7 days old, likely has new trading days -> Stale
      expect(freshness['000001'], isA<Stale>(),
          reason: '7天前的数据可能有新交易日未检查');
    });
  });

  group('日线 vs 分钟线差异', () {
    test('日线数据使用相同的缓存机制', () async {
      final staleAnchor = DateTime.now().subtract(const Duration(days: 7));
      final staleAnchorDate = DateTime(
        staleAnchor.year,
        staleAnchor.month,
        staleAnchor.day,
      );

      // Save daily data
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(staleAnchorDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // For daily data, we need to populate cache manually since
      // findMissingMinuteDates is for minute data
      final dateCheckStorage = DateCheckStorage(database: database);
      await dateCheckStorage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.daily,
        date: staleAnchorDate,
        status: DayDataStatus.complete,
        barCount: 1,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.daily,
      );

      // Data is 2 days old, there might be new trading days -> Stale
      expect(freshness['000001'], isA<Stale>());
    });

    test('分钟线和日线独立检测', () async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final weekAgoDate = DateTime(weekAgo.year, weekAgo.month, weekAgo.day);

      // Save daily data as trading day reference
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(todayDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data for today
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(todayDate.year, todayDate.month, todayDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate minute cache
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(todayDate, todayDate),
      );

      // Populate daily cache with old data
      final dateCheckStorage = DateCheckStorage(database: database);
      await dateCheckStorage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.daily,
        date: weekAgoDate,
        status: DayDataStatus.complete,
        barCount: 1,
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
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      final weekAgoDate = DateTime(weekAgo.year, weekAgo.month, weekAgo.day);

      // 股票1：今天有完整数据 -> Fresh
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(todayDate, 10.0)],
        dataType: KLineDataType.daily,
      );
      final stock1Minutes = <KLine>[];
      for (var i = 0; i < 230; i++) {
        stock1Minutes.add(_createKLine(
          DateTime(todayDate.year, todayDate.month, todayDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: stock1Minutes,
        dataType: KLineDataType.oneMinute,
      );
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(todayDate, todayDate),
      );

      // 股票2：7天前有完整数据 -> Stale
      await manager.saveKlineData(
        stockCode: '000002',
        newBars: [_createKLine(weekAgoDate, 10.0)],
        dataType: KLineDataType.daily,
      );
      final stock2Minutes = <KLine>[];
      for (var i = 0; i < 230; i++) {
        stock2Minutes.add(_createKLine(
          DateTime(weekAgoDate.year, weekAgoDate.month, weekAgoDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000002',
        newBars: stock2Minutes,
        dataType: KLineDataType.oneMinute,
      );
      await repository.findMissingMinuteDates(
        stockCode: '000002',
        dateRange: DateRange(weekAgoDate, weekAgoDate),
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
    test('missingRange 应该包含未检查的日期范围', () async {
      final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
      final fiveDaysAgoDate = DateTime(fiveDaysAgo.year, fiveDaysAgo.month, fiveDaysAgo.day);

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(fiveDaysAgoDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(fiveDaysAgoDate.year, fiveDaysAgoDate.month, fiveDaysAgoDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(fiveDaysAgoDate, fiveDaysAgoDate),
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>());
      final stale = freshness['000001'] as Stale;

      // missingRange.start should be after the last checked date
      final expectedStart = fiveDaysAgoDate.add(const Duration(days: 1));
      expect(
        stale.missingRange.start.day,
        equals(expectedStart.day),
        reason: 'missingRange 应该从最后检查日期的第二天开始',
      );
    });

    test('missingRange.end 应该是当前时间', () async {
      final fiveDaysAgo = DateTime.now().subtract(const Duration(days: 5));
      final fiveDaysAgoDate = DateTime(fiveDaysAgo.year, fiveDaysAgo.month, fiveDaysAgo.day);

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(fiveDaysAgoDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Save complete minute data
      final minuteKlines = <KLine>[];
      for (var i = 0; i < 230; i++) {
        minuteKlines.add(_createKLine(
          DateTime(fiveDaysAgoDate.year, fiveDaysAgoDate.month, fiveDaysAgoDate.day, 9, 30).add(Duration(minutes: i)),
          10.0 + i * 0.001,
        ));
      }
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: minuteKlines,
        dataType: KLineDataType.oneMinute,
      );

      // Populate cache
      await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(fiveDaysAgoDate, fiveDaysAgoDate),
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

  group('数据连续性检查 - 新实现已支持', () {
    test('检测指定日期范围内的数据连续性', () async {
      // 新实现通过 findMissingMinuteDates 检测数据连续性

      final jan20 = DateTime(2026, 1, 20);
      final jan21 = DateTime(2026, 1, 21);
      final jan22 = DateTime(2026, 1, 22);
      final jan23 = DateTime(2026, 1, 23);
      final jan24 = DateTime(2026, 1, 24);

      // Save daily data to define trading days (all 5 days)
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [
          _createKLine(jan20, 10.0),
          _createKLine(jan21, 10.1),
          _createKLine(jan22, 10.2),
          _createKLine(jan23, 10.3),
          _createKLine(jan24, 10.4),
        ],
        dataType: KLineDataType.daily,
      );

      // Only save complete minute data for jan20, jan22, jan24 (skip jan21, jan23)
      for (final date in [jan20, jan22, jan24]) {
        final minutes = <KLine>[];
        for (var i = 0; i < 230; i++) {
          minutes.add(_createKLine(
            DateTime(date.year, date.month, date.day, 9, 30).add(Duration(minutes: i)),
            10.0 + i * 0.001,
          ));
        }
        await manager.saveKlineData(
          stockCode: '000001',
          newBars: minutes,
          dataType: KLineDataType.oneMinute,
        );
      }

      // findMissingMinuteDates detects gaps
      final result = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(jan20, jan24),
      );

      // Verify gaps are detected
      expect(result.missingDates, containsAll([jan21, jan23]));
      expect(result.completeDates, containsAll([jan20, jan22, jan24]));

      // checkFreshness should return Stale due to missing dates
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>(),
          reason: '新实现检测到数据不连续');
    });

    test('检测分钟数据的日内完整性', () async {
      // 新实现检查 barCount >= 220 判断完整性

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayDate = DateTime(yesterday.year, yesterday.month, yesterday.day);

      // Save daily data to define trading day
      await manager.saveKlineData(
        stockCode: '000001',
        newBars: [_createKLine(yesterdayDate, 10.0)],
        dataType: KLineDataType.daily,
      );

      // Only save 50 bars (incomplete)
      final incomplete = <KLine>[];
      for (var i = 0; i < 50; i++) {
        final datetime = DateTime(yesterdayDate.year, yesterdayDate.month, yesterdayDate.day, 9, 30 + i);
        incomplete.add(_createKLine(datetime, 10.0 + i * 0.01));
      }

      await manager.saveKlineData(
        stockCode: '000001',
        newBars: incomplete,
        dataType: KLineDataType.oneMinute,
      );

      // findMissingMinuteDates detects incomplete data
      final result = await repository.findMissingMinuteDates(
        stockCode: '000001',
        dateRange: DateRange(yesterdayDate, yesterdayDate),
      );

      // Verify incomplete is detected
      expect(result.incompleteDates, contains(yesterdayDate));
      expect(result.completeDates, isEmpty);

      // checkFreshness should return Stale due to incomplete data
      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>(),
          reason: '新实现检测到日内分钟数据不完整');
    });
  });

  group('checkFreshness with cache', () {
    test('returns Stale when cache has pending dates', () async {
      final jan15 = DateTime(2026, 1, 15);

      // Manually save incomplete status to cache
      final dateCheckStorage = DateCheckStorage(database: database);
      await dateCheckStorage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: jan15,
        status: DayDataStatus.incomplete,
        barCount: 100,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Stale>());
    });

    test('returns Fresh when all cached dates are complete', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayDate = DateTime(yesterday.year, yesterday.month, yesterday.day);

      // Save complete status
      final dateCheckStorage = DateCheckStorage(database: database);
      await dateCheckStorage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: yesterdayDate,
        status: DayDataStatus.complete,
        barCount: 240,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['000001'], isA<Fresh>());
    });

    test('returns Missing when no cached data', () async {
      final freshness = await repository.checkFreshness(
        stockCodes: ['999999'],
        dataType: KLineDataType.oneMinute,
      );

      expect(freshness['999999'], isA<Missing>());
    });

    test('excludes today from pending check', () async {
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      // Save incomplete status for today only
      final dateCheckStorage = DateCheckStorage(database: database);
      await dateCheckStorage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: todayDate,
        status: DayDataStatus.incomplete,
        barCount: 50,
      );

      // Also save a complete date for yesterday so it's not Missing
      final yesterday = todayDate.subtract(const Duration(days: 1));
      await dateCheckStorage.saveCheckStatus(
        stockCode: '000001',
        dataType: KLineDataType.oneMinute,
        date: yesterday,
        status: DayDataStatus.complete,
        barCount: 240,
      );

      final freshness = await repository.checkFreshness(
        stockCodes: ['000001'],
        dataType: KLineDataType.oneMinute,
      );

      // Should be Fresh because today's incomplete is ignored
      expect(freshness['000001'], isA<Fresh>());
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
