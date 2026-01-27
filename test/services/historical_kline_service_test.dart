import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/data_freshness.dart';
import 'package:stock_rtwatcher/data/models/data_status.dart';
import 'package:stock_rtwatcher/data/models/data_updated_event.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/fetch_result.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/data_repository.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/quote.dart';
import 'package:stock_rtwatcher/services/historical_kline_service.dart';

/// Mock DataRepository for testing HistoricalKlineService
class MockDataRepository implements DataRepository {
  final Map<String, List<KLine>> _klineData = {};
  final Map<String, DataFreshness> _freshnessResults = {};
  int _version = 0;

  final _statusController = StreamController<DataStatus>.broadcast();
  final _dataUpdatedController = StreamController<DataUpdatedEvent>.broadcast();

  @override
  Stream<DataStatus> get statusStream => _statusController.stream;

  @override
  Stream<DataUpdatedEvent> get dataUpdatedStream => _dataUpdatedController.stream;

  /// Set kline data for testing
  void setKlineData(String stockCode, List<KLine> klines) {
    _klineData[stockCode] = klines;
  }

  /// Set freshness result for testing
  void setFreshnessResult(String stockCode, DataFreshness freshness) {
    _freshnessResults[stockCode] = freshness;
  }

  @override
  Future<Map<String, List<KLine>>> getKlines({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
  }) async {
    final result = <String, List<KLine>>{};
    for (final code in stockCodes) {
      if (_klineData.containsKey(code)) {
        result[code] = _klineData[code]!;
      }
    }
    return result;
  }

  @override
  Future<Map<String, DataFreshness>> checkFreshness({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    final result = <String, DataFreshness>{};
    for (final code in stockCodes) {
      result[code] = _freshnessResults[code] ?? const Missing();
    }
    return result;
  }

  @override
  Future<Map<String, Quote>> getQuotes({required List<String> stockCodes}) async {
    return {};
  }

  @override
  Future<int> getCurrentVersion() async => _version;

  @override
  Future<FetchResult> fetchMissingData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: {},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<FetchResult> refetchData({
    required List<String> stockCodes,
    required DateRange dateRange,
    required KLineDataType dataType,
    ProgressCallback? onProgress,
  }) async {
    return FetchResult(
      totalStocks: 0,
      successCount: 0,
      failureCount: 0,
      errors: {},
      totalRecords: 0,
      duration: Duration.zero,
    );
  }

  @override
  Future<void> cleanupOldData({required DateTime beforeDate}) async {}

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _dataUpdatedController.close();
  }
}

// Helper function to generate test KLine bars
List<KLine> _generateBars(DateTime date, int upCount, int downCount, {double upVol = 100, double downVol = 100}) {
  final bars = <KLine>[];
  for (var i = 0; i < upCount; i++) {
    bars.add(KLine(
      datetime: date.add(Duration(minutes: i)),
      open: 10, close: 11, high: 11, low: 10,
      volume: upVol, amount: 0,
    ));
  }
  for (var i = 0; i < downCount; i++) {
    bars.add(KLine(
      datetime: date.add(Duration(minutes: upCount + i)),
      open: 11, close: 10, high: 11, low: 10,
      volume: downVol, amount: 0,
    ));
  }
  return bars;
}

void main() {
  group('HistoricalKlineService', () {
    group('date utilities', () {
      test('formatDate returns YYYY-MM-DD format', () {
        final date = DateTime(2025, 1, 25);
        expect(HistoricalKlineService.formatDate(date), '2025-01-25');
      });

      test('formatDate pads single digit month and day', () {
        final date = DateTime(2025, 3, 5);
        expect(HistoricalKlineService.formatDate(date), '2025-03-05');
      });

      test('parseDate parses YYYY-MM-DD format', () {
        final date = HistoricalKlineService.parseDate('2025-01-25');
        expect(date.year, 2025);
        expect(date.month, 1);
        expect(date.day, 25);
      });
    });

    group('getDailyVolumes', () {
      late HistoricalKlineService service;
      late MockDataRepository mockRepo;

      setUp(() {
        mockRepo = MockDataRepository();
        service = HistoricalKlineService(repository: mockRepo);
      });

      test('returns empty map for unknown stock', () async {
        final volumes = await service.getDailyVolumes('999999');
        expect(volumes, isEmpty);
      });

      test('calculates daily up/down volumes correctly', () async {
        final date1 = DateTime(2025, 1, 24, 9, 30);
        final date2 = DateTime(2025, 1, 25, 9, 30);

        final bars = [
          ..._generateBars(date1, 5, 3, upVol: 100, downVol: 50),
          ..._generateBars(date2, 4, 6, upVol: 200, downVol: 100),
        ];

        mockRepo.setKlineData('000001', bars);

        final volumes = await service.getDailyVolumes('000001');

        expect(volumes.length, 2);
        expect(volumes['2025-01-24']?.up, 500); // 5 * 100
        expect(volumes['2025-01-24']?.down, 150); // 3 * 50
        expect(volumes['2025-01-25']?.up, 800); // 4 * 200
        expect(volumes['2025-01-25']?.down, 600); // 6 * 100
      });
    });

    group('getMissingDays (deprecated)', () {
      late HistoricalKlineService service;
      late MockDataRepository mockRepo;

      setUp(() {
        mockRepo = MockDataRepository();
        service = HistoricalKlineService(repository: mockRepo);
      });

      test('returns expected trading days when no data', () {
        // With no complete dates, all estimated trading days are missing
        // ignore: deprecated_member_use_from_same_package
        final missing = service.getMissingDays();
        expect(missing, greaterThan(0));
      });

      test('returns 0 when all recent dates are complete', () {
        // Simulate having all recent trading days
        // Need to go back ~45 calendar days to cover 30 trading days (weekends excluded)
        final today = DateTime.now();
        for (var i = 1; i <= 45; i++) {
          final date = today.subtract(Duration(days: i));
          if (date.weekday != DateTime.saturday && date.weekday != DateTime.sunday) {
            service.addCompleteDate(HistoricalKlineService.formatDate(date));
          }
        }
        // ignore: deprecated_member_use_from_same_package
        final missing = service.getMissingDays();
        expect(missing, 0);
      });
    });

    group('getMissingDaysForStocks', () {
      late HistoricalKlineService service;
      late MockDataRepository mockRepo;

      setUp(() {
        mockRepo = MockDataRepository();
        service = HistoricalKlineService(repository: mockRepo);
      });

      test('returns 0 for empty stock list', () async {
        final missing = await service.getMissingDaysForStocks([]);
        expect(missing, 0);
      });

      test('returns 30 for completely missing stock', () async {
        mockRepo.setFreshnessResult('000001', const Missing());

        final missing = await service.getMissingDaysForStocks(['000001']);
        expect(missing, 30);
      });

      test('returns 0 for fresh stock', () async {
        mockRepo.setFreshnessResult('000001', const Fresh());

        final missing = await service.getMissingDaysForStocks(['000001']);
        expect(missing, 0);
      });

      test('returns days based on stale range', () async {
        final now = DateTime.now();
        final staleRange = DateRange(
          now.subtract(const Duration(days: 5)),
          now,
        );
        mockRepo.setFreshnessResult('000001', Stale(missingRange: staleRange));

        final missing = await service.getMissingDaysForStocks(['000001']);
        expect(missing, 5);
      });

      test('clamps stale range to 30 days max', () async {
        final now = DateTime.now();
        final staleRange = DateRange(
          now.subtract(const Duration(days: 60)),
          now,
        );
        mockRepo.setFreshnessResult('000001', Stale(missingRange: staleRange));

        final missing = await service.getMissingDaysForStocks(['000001']);
        expect(missing, 30);
      });

      test('sums missing days across multiple stocks', () async {
        final now = DateTime.now();
        mockRepo.setFreshnessResult('000001', const Missing()); // 30 days
        mockRepo.setFreshnessResult('000002', const Fresh()); // 0 days
        mockRepo.setFreshnessResult('000003', Stale(
          missingRange: DateRange(now.subtract(const Duration(days: 10)), now),
        )); // 10 days

        final missing = await service.getMissingDaysForStocks(['000001', '000002', '000003']);
        expect(missing, 40); // 30 + 0 + 10
      });
    });

    group('persistence', () {
      late MockDataRepository mockRepo;

      setUp(() {
        mockRepo = MockDataRepository();
      });

      test('serializes and deserializes correctly', () {
        final service = HistoricalKlineService(repository: mockRepo);
        // Use a recent date to avoid cleanup removing it
        final now = DateTime.now();
        final recentDate = DateTime(now.year, now.month, now.day, 9, 30).subtract(const Duration(days: 1));
        final dateKey = HistoricalKlineService.formatDate(recentDate);
        final bars = _generateBars(recentDate, 5, 3);

        service.setStockBars('000001', bars);
        service.addCompleteDate(dateKey);

        final json = service.serializeCache();

        expect(json['version'], 1);
        expect(json['completeDates'], contains(dateKey));
        expect(json['stocks']['000001'], isNotEmpty);

        // Create new service and deserialize
        final service2 = HistoricalKlineService(repository: mockRepo);
        service2.deserializeCache(json);

        expect(service2.completeDates, contains(dateKey));
      });
    });
  });
}
