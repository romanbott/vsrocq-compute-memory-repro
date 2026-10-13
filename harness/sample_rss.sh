#!/usr/bin/env bash
# Sample the resident set size (VmRSS) of a process until it exits.
#
# usage: sample_rss.sh <pid> <interval_seconds> <out_csv>
#
# Writes: t_ms,rss_kb   (t_ms is milliseconds since the sampler started)
set -u

pid=${1:?usage: sample_rss.sh <pid> <interval_seconds> <out_csv>}
interval=${2:-0.2}
out=${3:?missing output csv}

echo "t_ms,rss_kb" > "$out"

start=$(date +%s%3N)
while kill -0 "$pid" 2>/dev/null; do
  rss=$(awk '/^VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null)
  if [ -z "${rss:-}" ]; then
    break
  fi
  now=$(date +%s%3N)
  echo "$((now - start)),$rss" >> "$out"
  sleep "$interval"
done
