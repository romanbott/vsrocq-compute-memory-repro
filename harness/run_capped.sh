#!/usr/bin/env bash
# Run a Rocq script under a hard memory cap + timeout, sampling its RSS.
#
# usage: run_capped.sh <mem_mb> <timeout_s> <label> <file.v>
#
# Environment:
#   ROCQ_CMD   command used to run the file (default: "rocq repl -q")
#   OUTDIR     output directory (default: results)
#
# Outputs:
#   $OUTDIR/<label>.log       combined stdout/stderr
#   $OUTDIR/<label>.rss.csv   RSS samples (t_ms,rss_kb)
#   $OUTDIR/<label>.meta      wall time, exit code, peak RSS
#
# The memory cap uses `ulimit -v` (address space). This is deliberately blunt:
# it guarantees the experiment cannot take down the host, at the cost of some
# over-counting versus a cgroup RSS limit.
set -u

mem_mb=${1:?usage: run_capped.sh <mem_mb> <timeout_s> <label> <file.v>}
timeout_s=${2:?usage: run_capped.sh <mem_mb> <timeout_s> <label> <file.v>}
label=${3:?usage: run_capped.sh <mem_mb> <timeout_s> <label> <file.v>}
file=${4:?usage: run_capped.sh <mem_mb> <timeout_s> <label> <file.v>}

ROCQ_CMD=${ROCQ_CMD:-rocq repl -q}
OUTDIR=${OUTDIR:-results}
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$OUTDIR"
log="$OUTDIR/$label.log"
csv="$OUTDIR/$label.rss.csv"
meta="$OUTDIR/$label.meta"

start=$(date +%s%3N)

# Start the Rocq process in its own subshell with the address-space limit,
# then exec so that $! is the actual Rocq process we sample.
( ulimit -v $((mem_mb * 1024)); exec $ROCQ_CMD ) < "$file" > "$log" 2>&1 &
pid=$!

# Watchdog: kill the process if it outlives the timeout.
( sleep "$timeout_s"; kill -TERM "$pid" 2>/dev/null ) &
watchdog=$!

# RSS sampler.
"$HERE/sample_rss.sh" "$pid" 0.2 "$csv" &
sampler=$!

wait "$pid"
rc=$?
kill "$watchdog" "$sampler" 2>/dev/null
wait "$watchdog" "$sampler" 2>/dev/null

end=$(date +%s%3N)
peak=$(awk -F, 'NR>1 && $2>m {m=$2} END {print m+0}' "$csv")

{
  echo "label=$label"
  echo "file=$file"
  echo "mem_cap_mb=$mem_mb"
  echo "timeout_s=$timeout_s"
  echo "wall_ms=$((end - start))"
  echo "exit_code=$rc"
  echo "peak_rss_kb=$peak"
  echo "verdict=$(grep -oE 'Error: [A-Za-z ]+|Stack overflow|Out of memory' "$log" | tail -1)"
} > "$meta"

echo "[$label] exit=$rc wall_ms=$((end - start)) peak_rss_kb=$peak"
