# 数据管理页真实网络 E2E 耗时与优化记录（2026-02-16）

## 目标
- 用真实网络 e2e 识别数据管理页耗时长的功能。
- 对长任务逐项优化，并用同一套 e2e 再验证。

## 采样环境
- 命令：
```bash
flutter test integration_test/features/data_management_real_network_test.dart \
  -d macos \
  --dart-define=RUN_DATA_MGMT_REAL_E2E=true \
  -r compact
```
- 说明：同一命令重复多次，取日志中的 `*_elapsed_ms` 对比。

## 基线耗时（优化前）
一次完整矩阵（ms）：

| 操作 | 耗时 |
|---|---:|
| historical_fetch_missing | 5884 |
| weekly_fetch_missing | 1395 |
| daily_force_refetch | 14518 |
| historical_recheck | 2277 |
| weekly_force_refetch | 3334 |
| weekly_macd_recompute | 3858 |

长任务（>5s）：
- `daily_force_refetch`（约 14.5s）
- `historical_fetch_missing`（约 5.8s）

## 优化项

### 1) 历史分钟K拉取：无新增时跳过行业重算
- 位置：`lib/screens/data_management_screen.dart`
- 优化点：
  - 原逻辑：`fetchMissingData` 完成后总是执行行业趋势 + 行业排名重算。
  - 新逻辑：仅在 `forceRefetch=true` 或 `fetchResult.totalRecords > 0` 时重算。
  - 无新增记录时直接跳过行业重算，缩短等待。
- 回归测试：
  - `历史分钟K拉取缺失无新增记录时应跳过行业重算`
  - `历史分钟K拉取缺失有新增记录时应触发行业重算`

### 2) 日K强制拉取：突破检测改为受控并发
- 位置：`lib/providers/market_data_provider.dart`
- 优化点：
  - 原逻辑：`_applyBreakoutDetection` 串行逐股 `await`。
  - 新逻辑：最多 6 并发 worker 处理，保持结果顺序写回。
- 性能回归测试（单测内压测）：
  - `forceRefetchDailyBars should avoid sequential breakout recompute latency`
  - 指标阶段从约 `1539ms` 降至约 `309ms`（同测试工况）。

## 优化后真实网络复测
最近一次完整矩阵（ms）：

| 操作 | 耗时 |
|---|---:|
| historical_fetch_missing | 5813 |
| weekly_fetch_missing | 1507 |
| daily_force_refetch | 14597 |
| historical_recheck | 2281 |
| weekly_force_refetch | 3285 |
| weekly_macd_recompute | 3950 |

## 结论
- `daily_force_refetch` 端到端耗时仍主要受网络拉取阶段影响，当前优化主要压缩了本地“指标计算”阶段（单测可验证显著下降）。
- `historical_fetch_missing` 在“无新增记录”场景已去除不必要的行业重算；当确有新增记录时仍会执行必要重算，端到端耗时受增量数据规模影响。
- 本轮已完成：
  - 长任务识别（真实网络 e2e）
  - 长任务对应优化（逻辑跳过 + 并发计算）
  - 回归验证（widget/unit/integration + real-network e2e）
