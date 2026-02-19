import 'package:stock_rtwatcher/data/models/kline_data_type.dart';
import 'package:stock_rtwatcher/data/storage/kline_file_storage.dart' show KLineAppendResult;
import 'package:stock_rtwatcher/models/kline.dart';

abstract class KLineMonthlyStorage {
  Future<void> initialize();
  void setBaseDirPathForTesting(String path);
  Future<String> getBaseDirectoryPath();
  Future<String> getFilePathAsync(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  );
  Future<List<KLine>> loadMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  );
  Future<void> saveMonthlyKlineFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> klines,
  );
  Future<KLineAppendResult?> appendKlineData(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
    List<KLine> newKlines,
  );
  Future<void> deleteMonthlyFile(
    String stockCode,
    KLineDataType dataType,
    int year,
    int month,
  );
}
