# 数据管理页：新交易日增量链路真网络观测（2026-02-16）

## 范围

- 用例：`integration_test/features/data_management_real_network_test.dart`
- 模式：真网络（`RUN_DATA_MGMT_REAL_E2E=true`）
- 关注点：
  - `daily_force_refetch` 的阶段可观测性
  - `daily_intraday_or_final_state` 的链路状态标记
  - `daily_incremental_recompute_elapsed_ms` 的基线记录

## 新增日志字段

- `[DataManagement Real E2E] daily_force_refetch_progress_hint=speed:<bool>,eta:<bool>,indicator_stage:<bool>,visible_hint:<bool>`
- `[DataManagement Real E2E] daily_intraday_or_final_state=<intraday_partial|final_override|unknown>`
- `[DataManagement Real E2E] daily_incremental_recompute_elapsed_ms=<ms>`

## 运行命令

```bash
flutter test integration_test/features/data_management_real_network_test.dart \
  -d macos \
  --dart-define=RUN_DATA_MGMT_REAL_E2E=true
```

## 实测结果（2026-02-16）

- run_at: `2026-02-16 15:18:07 CST`
- command: `flutter test integration_test/features/data_management_real_network_test.dart -d macos --dart-define=RUN_DATA_MGMT_REAL_E2E=true -r compact`
- suite_result: `PASS`
- historical_fetch_missing_elapsed_ms: `5897`
- weekly_fetch_missing_elapsed_ms: `1494`
- daily_force_refetch_elapsed_ms: `16305`
- daily_force_refetch_progress_hint: `speed:false,eta:false,indicator_stage:false,visible_hint:false`
- daily_intraday_or_final_state: `unknown`
- daily_incremental_recompute_elapsed_ms: `16305`
- historical_recheck_elapsed_ms: `1791`
- weekly_force_refetch_elapsed_ms: `3296`
- weekly_force_refetch_progress_hint: `speed:false,eta:false`
- weekly_macd_recompute_elapsed_ms: `3907`
- weekly_macd_recompute_progress_hint: `dialog:false,speed:false,eta:false`

## 结论

- 本次真网络全量链路执行成功，但 `daily_force_refetch` 耗时仍在 `16s+`，是当前最重任务。
- `daily_intraday_or_final_state=unknown`，说明真实链路尚未稳定暴露“日内 partial / 终盘 final”可观测标识。
- `daily_force_refetch_progress_hint` 的可视提示字段均为 `false`，意味着当前 UI 文案检索不到显式速率/ETA/增量阶段提示；虽然 watchdog 未判定卡住，但用户侧预期仍然不足。

## 备注

- 当 `daily_force_refetch_elapsed_ms > 5000` 时，必须至少满足：
  - `speed:true` 或 `indicator_stage:true`
- `daily_intraday_or_final_state` 若长期为 `unknown`，说明真实链路尚未对“日内 partial / 终盘 final”输出明确阶段文案，需在 UI/状态汇聚层补充可观测标识。
