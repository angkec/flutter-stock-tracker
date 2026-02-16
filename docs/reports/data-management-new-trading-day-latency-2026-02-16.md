# 数据管理页：新交易日增量链路真网络观测（2026-02-16）

## 范围

- 用例：`integration_test/features/data_management_real_network_test.dart`
- 模式：真网络（`RUN_DATA_MGMT_REAL_E2E=true`）
- 关注点：
  - `daily_force_refetch` 的阶段可观测性
  - `daily_intraday_or_final_state` 的链路状态标记
  - `daily_incremental_recompute_elapsed_ms` 的基线记录

## 新增日志字段

- `[DataManagement Real E2E] daily_force_refetch_progress_hint=speed:<bool>,eta:<bool>,indicator_stage:<bool>`
- `[DataManagement Real E2E] daily_intraday_or_final_state=<intraday_partial|final_override|unknown>`
- `[DataManagement Real E2E] daily_incremental_recompute_elapsed_ms=<ms>`

## 运行命令

```bash
flutter test integration_test/features/data_management_real_network_test.dart \
  -d macos \
  --dart-define=RUN_DATA_MGMT_REAL_E2E=true
```

## 结果记录模板

- run_at:
- historical_fetch_missing_elapsed_ms:
- weekly_fetch_missing_elapsed_ms:
- daily_force_refetch_elapsed_ms:
- daily_force_refetch_progress_hint:
- daily_intraday_or_final_state:
- daily_incremental_recompute_elapsed_ms:
- historical_recheck_elapsed_ms:
- weekly_force_refetch_elapsed_ms:
- weekly_macd_recompute_elapsed_ms:

## 备注

- 当 `daily_force_refetch_elapsed_ms > 5000` 时，必须至少满足：
  - `speed:true` 或 `indicator_stage:true`
- `daily_intraday_or_final_state` 若长期为 `unknown`，说明真实链路尚未对“日内 partial / 终盘 final”输出明确阶段文案，需在 UI/状态汇聚层补充可观测标识。
