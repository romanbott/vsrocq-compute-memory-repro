#!/usr/bin/env bash
# Sweep `Compute (pow 2 K)` to show unary-nat memory growth.
#
# usage: sweep_pow.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR=${OUTDIR:-results}
mkdir -p "$OUTDIR/gen"

csv="$OUTDIR/sweep_pow.csv"
echo "k,expected,result,wall_ms,peak_rss_kb,exit_code" > "$csv"

run_case() {
  local k=$1 expected=$2
  local f="$OUTDIR/gen/pow_2_$k.v"
  {
    echo 'Fixpoint pow (b e : nat) : nat :='
    echo '  match e with 0 => 1 | S e => mult b (pow b e) end.'
    printf 'Compute (pow 2 %s).\n' "$k"
  } > "$f"

  "$HERE/run_capped.sh" 2000 25 "pow_2_$k" "$f" >/dev/null

  local meta="$OUTDIR/pow_2_$k.meta"
  local wall peak rc result
  wall=$(awk -F= '$1=="wall_ms"{print $2}' "$meta")
  peak=$(awk -F= '$1=="peak_rss_kb"{print $2}' "$meta")
  rc=$(awk -F= '$1=="exit_code"{print $2}' "$meta")
  result=$(grep -oE '= [0-9]+|Error: Stack overflow|Error: Out of memory' "$OUTDIR/pow_2_$k.log" | tail -1)
  [ -z "$result" ] && result="(killed)"

  echo "$k,$expected,$result,$wall,$peak,$rc" >> "$csv"
  printf 'pow 2 %-3s -> %-28s peak=%s KB wall=%s ms\n' "$k" "$result" "$peak" "$wall"
}

run_case 10 "1024"
run_case 15 "32768"
run_case 18 "262144"
run_case 20 "1048576"
run_case 22 "4194304"
run_case 25 "33554432"
run_case 30 "1073741824"

echo "wrote $csv"
