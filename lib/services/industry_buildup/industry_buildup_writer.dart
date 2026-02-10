import 'package:stock_rtwatcher/data/storage/industry_buildup_storage.dart';
import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/services/industry_buildup/industry_buildup_pipeline_models.dart';

abstract class IndustryBuildUpWriter {
  Future<IndustryBuildUpWriteResult> write({
    required IndustryBuildUpStorage storage,
    required List<IndustryBuildupDailyRecord> records,
  });
}

class DefaultIndustryBuildUpWriter implements IndustryBuildUpWriter {
  @override
  Future<IndustryBuildUpWriteResult> write({
    required IndustryBuildUpStorage storage,
    required List<IndustryBuildupDailyRecord> records,
  }) async {
    await storage.upsertDailyResults(records);
    return IndustryBuildUpWriteResult(writtenCount: records.length);
  }
}
