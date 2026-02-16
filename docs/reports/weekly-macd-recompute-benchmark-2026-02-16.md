# 周线 MACD 重算模拟器压测（2026-02-16）

## 目的

- 用模拟器可复现的统计结果压缩“周线 MACD 重算”体感时延。
- 同时满足两条约束：
  - 首次业务进度反馈不要出现长时间无预期等待。
  - 总耗时不能明显回退。

## 环境

- 日期：2026-02-16
- 设备：iPhone SE (3rd generation) 模拟器
- 数据范围：最近 760 天周K
- 命令：

```bash
BENCH_DEVICE='iPhone SE (3rd generation)' \
WEEKLY_MACD_BENCH_STOCK_LIMIT=500 \
WEEKLY_MACD_BENCH_SWEEP='40x6,80x8,120x8' \
scripts/benchmark_weekly_macd_recompute.sh
```

本轮优化内容：
- `MarketDataRepository.getKlines` 增加并发读取（默认 6 worker）
- `prewarmFromRepository` 改为 fetch/compute 流水线
- 同版本 + 同配置 + 同股票范围时，跳过重复重算

原始日志（优化后）：
- `/tmp/weekly_macd_recompute_bench_20260216_092827.log`
- `/tmp/weekly_macd_recompute_bench_20260216_092827.tsv`

## 结果

| fetchBatch | persistConcurrency | firstProgressMs | totalMs | stocks/s |
|---|---:|---:|---:|---:|
| 40 | 6   | 517 | 3058 | 163.5 |
| 80 | 8   | 419 | 2909 | 171.9 |
| 120 | 8  | 453 | 2903 | 172.2 |

优化前后对比（同设备、同 500 只股票）：

| 组合 | firstProgressMs | totalMs |
|---|---:|---:|
| 优化前 `40x6` | 447 | 5159 |
| 优化后 `120x8` | 453 | 2903 |
| 优化前 `80x8` | 805 | 5188 |
| 优化后 `80x8` | 419 | 2909 |

## 结论

- 本轮核心收益来自“并发读取 + 流水线”，而不是单纯调参数。
- 在新实现下，`80x8` / `120x8` 都明显优于 `40x6`。
- 以 `120x8` 作为默认时：
  - 总耗时相对优化前约下降 **43.7%**（5159ms -> 2903ms）
  - 首进度仍保持在 **0.5s** 以内，满足“不可无预期等待 >5s”。

推荐默认参数：
- `fetchBatchSize = 120`
- `maxConcurrentPersistWrites = 8`

## 落地范围

- 周线 MACD 设置页“重算”路径。
- 数据管理页周K同步后的周线 MACD 预热路径。

## 回归验证

```bash
flutter test test/screens/data_management_screen_test.dart -r compact
flutter test integration_test/features/data_management_offline_test.dart -d macos -r compact
flutter test test/integration/weekly_macd_recompute_benchmark_test.dart -d macos -r compact
```
