import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/database_schema.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage_v2.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/data/storage/market_database.dart';
import 'package:stock_rtwatcher/models/kline.dart';

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.basePath);

  final String basePath;

  @override
  Future<String?> getTemporaryPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;

  @override
  Future<String?> getLibraryPath() async => basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getApplicationCachePath() async => basePath;

  @override
  Future<String?> getExternalStoragePath() async => basePath;

  @override
  Future<List<String>?> getExternalCachePaths() async => <String>[basePath];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async => <String>[basePath];

  @override
  Future<String?> getDownloadsPath() async => basePath;
}

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;
  late MarketDatabase database;
  late KLineFileStorageV2 storage;
  late KLineMetadataManager manager;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestWidgetsFlutterBinding.ensureInitialized();
    originalPathProvider = PathProviderPlatform.instance;
  });

  Future<void> deleteTestDatabase() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = '$dbPath/${DatabaseSchema.databaseName}';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  setUp(() async {
    MarketDatabase.resetInstance();
    await deleteTestDatabase();

    tempDir = await Directory.systemTemp.createTemp(
      'monthly-daily-storage-readback-',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);

    storage = KLineFileStorageV2();
    await storage.initialize();

    database = MarketDatabase();
    await database.database;

    manager = KLineMetadataManager(
      database: database,
    );
  });

  tearDown(() async {
    try {
      await database.close();
    } catch (_) {}
    MarketDatabase.resetInstance();

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }

    PathProviderPlatform.instance = originalPathProvider;
    await deleteTestDatabase();
  });

  test('reads back daily bars from monthly storage on disk', () async {
    const stockCode = 'SH600000';

    final bars = [
      KLine(
        datetime: DateTime(2026, 1, 5, 10, 0),
        open: 10.0,
        close: 10.4,
        high: 10.6,
        low: 9.8,
        volume: 1200.0,
        amount: 12000.0,
      ),
      KLine(
        datetime: DateTime(2026, 1, 2, 10, 0),
        open: 10.1,
        close: 10.2,
        high: 10.5,
        low: 9.9,
        volume: 1100.0,
        amount: 11000.0,
      ),
      KLine(
        datetime: DateTime(2026, 1, 3, 10, 0),
        open: 10.2,
        close: 10.1,
        high: 10.4,
        low: 9.7,
        volume: 1150.0,
        amount: 11500.0,
      ),
    ];

    await manager.saveKlineData(
      stockCode: stockCode,
      newBars: bars,
      dataType: KLineDataType.daily,
    );

    try {
      await database.close();
    } catch (_) {}
    MarketDatabase.resetInstance();
    await deleteTestDatabase();

    storage = KLineFileStorageV2();
    await storage.initialize();
    database = MarketDatabase();
    await database.database;
    manager = KLineMetadataManager(
      database: database,
    );

    final sortedBars = [...bars]
      ..sort((a, b) => a.datetime.compareTo(b.datetime));
    final firstBar = sortedBars.first;
    final lastBar = sortedBars.last;
    final yearMonth =
        '${firstBar.datetime.year}${firstBar.datetime.month.toString().padLeft(2, '0')}';
    final filePath = await storage.getFilePathAsync(
      stockCode,
      KLineDataType.daily,
      firstBar.datetime.year,
      firstBar.datetime.month,
    );
    final fileSize = await File(filePath).length();
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await database.database;
    await db.insert('kline_files', {
      'stock_code': stockCode,
      'data_type': KLineDataType.daily.name,
      'year_month': yearMonth,
      'file_path': filePath,
      'start_date': firstBar.datetime.millisecondsSinceEpoch,
      'end_date': lastBar.datetime.millisecondsSinceEpoch,
      'record_count': sortedBars.length,
      'checksum': null,
      'created_at': now,
      'updated_at': now,
      'file_size': fileSize,
    });

    final loaded = await manager.loadKlineData(
      stockCode: stockCode,
      dataType: KLineDataType.daily,
      dateRange: DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31)),
    );

    expect(loaded, isNotEmpty);
    expect(loaded.length, bars.length);

    final savedByDate = {
      for (final bar in bars) bar.datetime: bar,
    };

    for (final bar in loaded) {
      final saved = savedByDate[bar.datetime];
      expect(saved, isNotNull, reason: 'Missing saved bar for ${bar.datetime}');
      expect(bar.close, saved!.close);
      expect(bar.volume, saved.volume);
    }

    final loadedDates = loaded.map((kline) => kline.datetime).toList();
    final sortedDates = [...loadedDates]
      ..sort((a, b) => a.compareTo(b));

    expect(loadedDates, orderedEquals(sortedDates));
  });

  test('daily metadata manager defaults to v2 file paths', () async {
    final manager = KLineMetadataManager(database: database);

    await manager.saveKlineData(
      stockCode: '000001',
      newBars: [
        KLine(
          datetime: DateTime(2026, 2, 18),
          open: 10,
          close: 11,
          high: 12,
          low: 9,
          volume: 100,
          amount: 200,
        ),
      ],
      dataType: KLineDataType.daily,
    );

    final meta = await manager.getMetadata(
      stockCode: '000001',
      dataType: KLineDataType.daily,
    );
    expect(meta.first.filePath.contains('klines_v2'), isTrue);
  });
}
