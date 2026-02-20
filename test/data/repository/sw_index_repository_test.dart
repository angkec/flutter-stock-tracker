import 'package:flutter_test/flutter_test.dart';
import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/repository/sw_index_repository.dart';
import 'package:stock_rtwatcher/data/storage/kline_metadata_manager.dart';
import 'package:stock_rtwatcher/models/kline.dart';
import 'package:stock_rtwatcher/models/sw_daily_bar.dart';
import 'package:stock_rtwatcher/services/tushare_client.dart';

void main() {
  group('SwIndexRepository', () {
    test('syncMissingDaily fetches and persists missing bars', () async {
      final metadata = _FakeMetadataManager();
      final client = _FakeTushareClient(
        barsByCode: {
          '801010.SI': [
            SwDailyBar(
              tsCode: '801010.SI',
              tradeDate: DateTime(2025, 1, 2),
              open: 100,
              high: 101,
              low: 99,
              close: 100.5,
              volume: 1000,
              amount: 10000,
            ),
          ],
        },
      );

      final repository = SwIndexRepository(
        metadataManager: metadata,
        client: client,
      );

      final result = await repository.syncMissingDaily(
        tsCodes: const ['801010.SI'],
        dateRange: DateRange(DateTime(2025, 1, 1), DateTime(2025, 1, 31)),
      );

      expect(result.fetchedCodes, const ['801010.SI']);
      expect(metadata.savedRecordsByCode['sw_801010_si'], hasLength(1));
      expect(metadata.savedTypeByCode['sw_801010_si'], KLineDataType.daily);
    });

    test('getDailyKlines returns bars using normalized local code', () async {
      final metadata = _FakeMetadataManager();
      metadata.loadDataByCode['sw_801010_si'] = [
        KLine(
          datetime: DateTime(2025, 1, 2),
          open: 100,
          close: 101,
          high: 102,
          low: 99,
          volume: 1000,
          amount: 10000,
        ),
      ];

      final repository = SwIndexRepository(
        metadataManager: metadata,
        client: _FakeTushareClient(barsByCode: const {}),
      );

      final result = await repository.getDailyKlines(
        tsCodes: const ['801010.SI'],
        dateRange: DateRange(DateTime(2025, 1, 1), DateTime(2025, 1, 31)),
      );

      expect(result['801010.SI'], hasLength(1));
    });
  });
}

class _FakeTushareClient extends TushareClient {
  final Map<String, List<SwDailyBar>> barsByCode;

  _FakeTushareClient({required this.barsByCode}) : super(token: 'fake-token');

  @override
  Future<List<SwDailyBar>> fetchSwDaily({
    required String tsCode,
    required String startDate,
    required String endDate,
    String fields = 'ts_code,trade_date,open,high,low,close,vol,amount',
  }) async {
    return barsByCode[tsCode] ?? const <SwDailyBar>[];
  }
}

class _FakeMetadataManager extends KLineMetadataManager {
  final Map<String, List<KLine>> savedRecordsByCode = {};
  final Map<String, KLineDataType> savedTypeByCode = {};
  final Map<String, List<KLine>> loadDataByCode = {};

  @override
  Future<void> saveKlineData({
    required String stockCode,
    required List<KLine> newBars,
    required KLineDataType dataType,
    bool bumpVersion = true,
  }) async {
    savedRecordsByCode[stockCode] = List<KLine>.from(newBars);
    savedTypeByCode[stockCode] = dataType;
  }

  @override
  Future<List<KLine>> loadKlineData({
    required String stockCode,
    required KLineDataType dataType,
    required DateRange dateRange,
  }) async {
    return loadDataByCode[stockCode] ?? const <KLine>[];
  }

  @override
  Future<Map<String, ({DateTime? startDate, DateTime? endDate})>>
  getCoverageRanges({
    required List<String> stockCodes,
    required KLineDataType dataType,
  }) async {
    return {
      for (final code in stockCodes) code: (startDate: null, endDate: null),
    };
  }

  @override
  Future<int> getCurrentVersion() async => 1;
}
