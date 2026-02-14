#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

POOL_SIZE="${BENCH_POOL_SIZE:-12}"
BATCH_COUNT="${BENCH_BATCH_COUNT:-800}"
MAX_BATCHES="${BENCH_MAX_BATCHES:-10}"
BENCH_DAYS="${BENCH_DAYS:-20}"
STOCK_LIMIT="${BENCH_STOCK_LIMIT:-0}"
CONCURRENCY_SET="${BENCH_WRITE_CONCURRENCY_SET:-4,6,8}"

IFS=',' read -r -a CONCURRENCIES <<< "$CONCURRENCY_SET"
if [[ ${#CONCURRENCIES[@]} -eq 0 ]]; then
  echo "[ERROR] BENCH_WRITE_CONCURRENCY_SET is empty"
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SUMMARY_FILE="/tmp/minute_write_concurrency_sweep_${TIMESTAMP}.tsv"

echo -e "writeConcurrency\tfirstMs\tsecondMs\tfetchMs\twriteMs\twritePersistMs\ttotalMs\tlogPath" > "$SUMMARY_FILE"

echo "[INFO] Sweep start: pool=${POOL_SIZE}, batch=${BATCH_COUNT}, maxBatches=${MAX_BATCHES}, days=${BENCH_DAYS}, stockLimit=${STOCK_LIMIT}, concurrencySet=${CONCURRENCY_SET}"

for concurrency in "${CONCURRENCIES[@]}"; do
  concurrency="${concurrency// /}"
  if [[ -z "$concurrency" ]]; then
    continue
  fi

  log_file="/tmp/minute_pipeline_bench_pool${POOL_SIZE}_wc${concurrency}_${TIMESTAMP}.log"

  echo "[INFO] Running benchmark for writeConcurrency=${concurrency}"
  RUN_REAL_TDX_BENCH=1 \
  BENCH_POOL_SIZE="$POOL_SIZE" \
  BENCH_BATCH_COUNT="$BATCH_COUNT" \
  BENCH_MAX_BATCHES="$MAX_BATCHES" \
  BENCH_DAYS="$BENCH_DAYS" \
  BENCH_STOCK_LIMIT="$STOCK_LIMIT" \
  BENCH_WRITE_CONCURRENCY="$concurrency" \
  flutter test test/integration/minute_pipeline_benchmark_test.dart -r compact | tee "$log_file"

  first_ms="$(rg '\[BENCH\]\[first\] durationMs=' "$log_file" | tail -n1 | sed -E 's/.*durationMs=([0-9]+).*/\1/')"
  second_ms="$(rg '\[BENCH\]\[second\] durationMs=' "$log_file" | tail -n1 | sed -E 's/.*durationMs=([0-9]+).*/\1/')"

  timing_line="$(rg '\[MinutePipeline\]\[timing\]' "$log_file" | head -n1)"
  fetch_ms="$(echo "$timing_line" | sed -E 's/.*fetchMs=([0-9]+).*/\1/')"
  write_ms="$(echo "$timing_line" | sed -E 's/.*writeMs=([0-9]+).*/\1/')"
  write_persist_ms="$(echo "$timing_line" | sed -E 's/.*writePersistMs=([0-9]+).*/\1/')"
  total_ms="$(echo "$timing_line" | sed -E 's/.*totalMs=([0-9]+).*/\1/')"

  echo -e "${concurrency}\t${first_ms}\t${second_ms}\t${fetch_ms}\t${write_ms}\t${write_persist_ms}\t${total_ms}\t${log_file}" >> "$SUMMARY_FILE"
done

python3 - "$SUMMARY_FILE" <<'PY'
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
    print('[ERROR] No benchmark rows captured')
    raise SystemExit(1)

rows.sort(key=lambda item: int(item['firstMs']))
best = rows[0]

print('\n=== Minute Write Concurrency Sweep Summary ===')
print('concurrency | firstMs | secondMs | fetchMs | writeMs | writePersistMs | totalMs')
for row in rows:
    print(
        f"{row['writeConcurrency']:>11} | {row['firstMs']:>7} | {row['secondMs']:>8} | "
        f"{row['fetchMs']:>7} | {row['writeMs']:>7} | {row['writePersistMs']:>14} | {row['totalMs']:>7}"
    )

first_ms = int(best['firstMs'])
minutes = first_ms / 60000
print('\n=== Recommendation ===')
print(
    f"Best writeConcurrency={best['writeConcurrency']} with first full fetch "
    f"{first_ms} ms ({minutes:.2f} min)."
)
print(f"Log file: {best['logPath']}")
print(f"Summary TSV: {summary_path}")
PY

echo "[INFO] Sweep complete"
