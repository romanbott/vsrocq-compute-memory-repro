#!/usr/bin/env bash
# Sweep `Compute (mult N N)` to locate the stack-overflow threshold.
#
# usage: sweep_nat.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR=${OUTDIR:-results}
mkdir -p "$OUTDIR/gen"

csv="$OUTDIR/sweep_nat.csv"
echo "n,result,wall_ms,peak_rss_kb,exit_code" > "$csv"

for n in 20 40 60 80 100 120 140 150 160 180 200 250; do
  f="$OUTDIR/gen/mult_$n.v"
  printf 'Compute (mult %s %s).\n' "$n" "$n" > "$f"

  "$HERE/run_capped.sh" 2000 20 "nat_$n" "$f" >/dev/null

  meta="$OUTDIR/nat_$n.meta"
  wall=$(awk -F= '$1=="wall_ms"{print $2}' "$meta")
  peak=$(awk -F= '$1=="peak_rss_kb"{print $2}' "$meta")
  rc=$(awk -F= '$1=="exit_code"{print $2}' "$meta")
  result=$(grep -oE '= [0-9]+|Error: Stack overflow|Error: [A-Za-z ]+' "$OUTDIR/nat_$n.log" | tail -1)
  [ -z "$result" ] && result="(no result)"

  echo "$n,$result,$wall,$peak,$rc" >> "$csv"
  printf 'mult %s %s -> %s\n' "$n" "$n" "$result"
done

echo "wrote $csv"
