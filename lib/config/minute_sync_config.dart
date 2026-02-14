class MinuteSyncConfig {
  final bool enablePoolMinutePipeline;
  final int poolBatchCount;
  final int poolMaxBatches;
  final int minuteWriteConcurrency;
  final bool enableMinutePipelineLogs;
  final bool minutePipelineFallbackToLegacyOnError;

  const MinuteSyncConfig({
    this.enablePoolMinutePipeline = false,
    this.poolBatchCount = 800,
    this.poolMaxBatches = 10,
    this.minuteWriteConcurrency = 6,
    this.enableMinutePipelineLogs = false,
    this.minutePipelineFallbackToLegacyOnError = true,
  });
}
