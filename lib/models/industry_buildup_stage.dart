import 'package:stock_rtwatcher/models/industry_buildup.dart';
import 'package:stock_rtwatcher/models/industry_buildup_tag_config.dart';

enum IndustryBuildupStage {
  emotion,
  allocation,
  early,
  noise,
  neutral,
  observing,
}

extension IndustryBuildupStageLabel on IndustryBuildupStage {
  String get label {
    switch (this) {
      case IndustryBuildupStage.emotion:
        return '情绪驱动';
      case IndustryBuildupStage.allocation:
        return '行业配置期';
      case IndustryBuildupStage.early:
        return '早期建仓';
      case IndustryBuildupStage.noise:
        return '噪音信号';
      case IndustryBuildupStage.neutral:
        return '无异常';
      case IndustryBuildupStage.observing:
        return '观察中';
    }
  }
}

IndustryBuildupStage resolveIndustryBuildupStage(
  IndustryBuildupDailyRecord record,
  IndustryBuildupTagConfig config,
) {
  final z = record.zRel;
  final breadth = record.breadth;
  final q = record.q;

  if (z > config.emotionMinZ && breadth > config.emotionMinBreadth) {
    return IndustryBuildupStage.emotion;
  }
  if (z > config.allocationMinZ &&
      breadth >= config.allocationMinBreadth &&
      breadth <= config.allocationMaxBreadth &&
      q > config.allocationMinQ) {
    return IndustryBuildupStage.allocation;
  }
  if (z >= config.earlyMinZ &&
      z <= config.earlyMaxZ &&
      breadth >= config.earlyMinBreadth &&
      breadth <= config.earlyMaxBreadth &&
      q > config.earlyMinQ) {
    return IndustryBuildupStage.early;
  }
  if (z >= config.noiseMinZ &&
      breadth < config.noiseMaxBreadth &&
      q < config.noiseMaxQ) {
    return IndustryBuildupStage.noise;
  }
  if (z >= config.neutralMinZ && z <= config.neutralMaxZ) {
    return IndustryBuildupStage.neutral;
  }
  return IndustryBuildupStage.observing;
}
