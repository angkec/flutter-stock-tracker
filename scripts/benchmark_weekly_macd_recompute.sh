#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DEVICE="${BENCH_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(flutter devices | rg 'simulator' | head -n1 | sed -E 's/^[[:space:]]*([^•]+).*/\1/' | xargs || true)"
fi
if [[ -z "$DEVICE" ]]; then
  DEVICE="macos"
fi

STOCK_LIMIT="${WEEKLY_MACD_BENCH_STOCK_LIMIT:-200}"
POOL_SIZE="${WEEKLY_MACD_BENCH_POOL_SIZE:-12}"
RANGE_DAYS="${WEEKLY_MACD_BENCH_RANGE_DAYS:-760}"
SWEEP="${WEEKLY_MACD_BENCH_SWEEP:-40x6,80x8,120x8}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/weekly_macd_recompute_bench_${TIMESTAMP}.log"
SUMMARY_FILE="/tmp/weekly_macd_recompute_bench_${TIMESTAMP}.tsv"

echo "[INFO] Running weekly MACD recompute sweep on device: ${DEVICE}"
echo "[INFO] stockLimit=${STOCK_LIMIT}, poolSize=${POOL_SIZE}, rangeDays=${RANGE_DAYS}, sweep=${SWEEP}"

RUN_REAL_WEEKLY_MACD_BENCH=1 \
WEEKLY_MACD_BENCH_STOCK_LIMIT="${STOCK_LIMIT}" \
WEEKLY_MACD_BENCH_POOL_SIZE="${POOL_SIZE}" \
WEEKLY_MACD_BENCH_RANGE_DAYS="${RANGE_DAYS}" \
WEEKLY_MACD_BENCH_SWEEP="${SWEEP}" \
flutter test test/integration/weekly_macd_recompute_benchmark_test.dart \
  -d "${DEVICE}" \
  -r compact | tee "${LOG_FILE}"

echo -e "fetchBatch\tpersistConcurrency\tfirstProgressMs\tfetchMs\tcomputeMs\tpersistMs\ttotalMs\tstocks\tstocksPerSec\tklineCalls\tpersistCalls\tsavedSeries\tcomputeCalls\tprogress\tlogPath" > "${SUMMARY_FILE}"

rg '\[WEEKLY_MACD_BENCH\]\[run\]' "${LOG_FILE}" | while read -r line; do
  fetch_batch="$(echo "$line" | sed -E 's/.*fetchBatch=([0-9]+).*/\1/')"
  persist_concurrency="$(echo "$line" | sed -E 's/.*persistConcurrency=([0-9]+).*/\1/')"
  first_progress_ms="$(echo "$line" | sed -E 's/.*firstProgressMs=([0-9]+).*/\1/')"
  fetch_ms="$(echo "$line" | sed -E 's/.*fetchMs=([0-9]+).*/\1/')"
  compute_ms="$(echo "$line" | sed -E 's/.*computeMs=([0-9]+).*/\1/')"
  persist_ms="$(echo "$line" | sed -E 's/.*persistMs=([0-9]+).*/\1/')"
  total_ms="$(echo "$line" | sed -E 's/.*totalMs=([0-9]+).*/\1/')"
  stocks="$(echo "$line" | sed -E 's/.*stocks=([0-9]+).*/\1/')"
  stocks_per_sec="$(echo "$line" | sed -E 's/.*stocksPerSec=([0-9]+\.[0-9]).*/\1/')"
  kline_calls="$(echo "$line" | sed -E 's/.*klineCalls=([0-9]+).*/\1/')"
  persist_calls="$(echo "$line" | sed -E 's/.*persistCalls=([0-9]+).*/\1/')"
  saved_series="$(echo "$line" | sed -E 's/.*savedSeries=([0-9]+).*/\1/')"
  compute_calls="$(echo "$line" | sed -E 's/.*computeCalls=([0-9]+).*/\1/')"
  progress="$(echo "$line" | sed -E 's/.*progress=([0-9]+\/[0-9]+).*/\1/')"

  echo -e "${fetch_batch}\t${persist_concurrency}\t${first_progress_ms}\t${fetch_ms}\t${compute_ms}\t${persist_ms}\t${total_ms}\t${stocks}\t${stocks_per_sec}\t${kline_calls}\t${persist_calls}\t${saved_series}\t${compute_calls}\t${progress}\t${LOG_FILE}" >> "${SUMMARY_FILE}"
done

python3 - "${SUMMARY_FILE}" <<'PY'
import csv
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
rows = []
with summary_path.open() as file:
    reader = csv.DictReader(file, delimiter='\t')
    for row in reader:
        rows.append(row)

if not rows:
    print('[ERROR] No benchmark rows captured from log')
    raise SystemExit(1)

STALL_THRESHOLD_MS = 5000
acceptable = [row for row in rows if int(row['firstProgressMs']) <= STALL_THRESHOLD_MS]
ranking_base = acceptable if acceptable else rows
ranking_base.sort(key=lambda item: (int(item['totalMs']), int(item['firstProgressMs'])))
best = ranking_base[0]

print('\n=== Weekly MACD Recompute Sweep Summary ===')
print('fetchBatch | persistConc | firstMs | totalMs | fetchMs | computeMs | persistMs | stocks/s')
for row in rows:
    print(
        f"{row['fetchBatch']:>10} | {row['persistConcurrency']:>11} | "
        f"{row['firstProgressMs']:>7} | {row['totalMs']:>7} | "
        f"{row['fetchMs']:>7} | {row['computeMs']:>9} | {row['persistMs']:>9} | "
        f"{row['stocksPerSec']:>8}"
    )

print('\n=== Recommendation ===')
print(
    f"Prefer fetchBatch={best['fetchBatch']} + persistConcurrency={best['persistConcurrency']} "
    f"(firstProgress={best['firstProgressMs']} ms, total={best['totalMs']} ms)."
)
print(f"Summary TSV: {summary_path}")
print(f"Log file: {best['logPath']}")
PY

echo "[INFO] Sweep complete"
