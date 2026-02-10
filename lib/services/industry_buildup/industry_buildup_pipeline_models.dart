import 'package:stock_rtwatcher/data/models/date_range.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';

int industryBuildUpDateKey(DateTime date) =>
    DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;

DateTime industryBuildUpDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

class IndustryBuildUpStockDayFeature {
  final double xHat;
  final double vSum;
  final double aSum;
  final double maxShare;
  final int minuteCount;
  final bool passed;

  const IndustryBuildUpStockDayFeature({
    required this.xHat,
    required this.vSum,
    required this.aSum,
    required this.maxShare,
    required this.minuteCount,
    required this.passed,
  });
}

class IndustryBuildUpIndustryDayIntermediate {
  final DateTime date;
  final double xI;
  final double xM;
  final double xRel;
  final double breadth;
  final int passedCount;
  final int memberCount;
  final double hhi;

  const IndustryBuildUpIndustryDayIntermediate({
    required this.date,
    required this.xI,
    required this.xM,
    required this.xRel,
    required this.breadth,
    required this.passedCount,
    required this.memberCount,
    required this.hhi,
  });
}

class IndustryBuildUpLoadResult {
  final Map<String, List<String>> industryStocks;
  final List<String> stockCodes;
  final List<DateTime> sortedTradingDates;
  final DateTime latestTradingDate;
  final int latestTradingDateKey;
  final DateRange dateRange;
  final Map<String, Map<int, IndustryBuildUpStockDayFeature>> stockFeatures;

  const IndustryBuildUpLoadResult({
    required this.industryStocks,
    required this.stockCodes,
    required this.sortedTradingDates,
    required this.latestTradingDate,
    required this.latestTradingDateKey,
    required this.dateRange,
    required this.stockFeatures,
  });
}

class IndustryBuildUpLoadOutcome {
  final IndustryBuildUpLoadResult? result;
  final String? errorMessage;

  const IndustryBuildUpLoadOutcome._({this.result, this.errorMessage});

  factory IndustryBuildUpLoadOutcome.success(IndustryBuildUpLoadResult result) {
    return IndustryBuildUpLoadOutcome._(result: result);
  }

  factory IndustryBuildUpLoadOutcome.failure(String message) {
    return IndustryBuildUpLoadOutcome._(errorMessage: message);
  }

  bool get isSuccess => result != null;
}

class IndustryBuildUpComputeResult {
  final List<IndustryBuildupDailyRecord> finalRecords;
  final bool hasLatestTradingDayResult;

  const IndustryBuildUpComputeResult({
    required this.finalRecords,
    required this.hasLatestTradingDayResult,
  });
}

class IndustryBuildUpWriteResult {
  final int writtenCount;

  const IndustryBuildUpWriteResult({required this.writtenCount});
}
