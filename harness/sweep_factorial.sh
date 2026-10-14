#!/usr/bin/env bash
# Sweep `Compute (factorial N)` to show unary-nat memory growth.
#
# usage: sweep_factorial.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR=${OUTDIR:-results}
mkdir -p "$OUTDIR/gen"

csv="$OUTDIR/sweep_factorial.csv"
echo "n,expected,result,wall_ms,peak_rss_kb,exit_code" > "$csv"

run_case() {
  local n=$1 expected=$2
  local f="$OUTDIR/gen/factorial_$n.v"
  {
    echo 'Fixpoint factorial (n : nat) : nat :='
    echo '  match n with 0 => 1 | S n => mult (S n) (factorial n) end.'
    printf 'Compute (factorial %s).\n' "$n"
  } > "$f"

  "$HERE/run_capped.sh" 2000 25 "factorial_$n" "$f" >/dev/null

  local meta="$OUTDIR/factorial_$n.meta"
  local wall peak rc result
  wall=$(awk -F= '$1=="wall_ms"{print $2}' "$meta")
  peak=$(awk -F= '$1=="peak_rss_kb"{print $2}' "$meta")
  rc=$(awk -F= '$1=="exit_code"{print $2}' "$meta")
  result=$(grep -oE '= [0-9]+|Error: Stack overflow|Error: Out of memory' "$OUTDIR/factorial_$n.log" | tail -1)
  [ -z "$result" ] && result="(killed)"

  echo "$n,$expected,$result,$wall,$peak,$rc" >> "$csv"
  printf 'factorial %-3s -> %-28s peak=%s KB wall=%s ms\n' "$n" "$result" "$peak" "$wall"
}

run_case 5  "120"
run_case 6  "720"
run_case 7  "5040"
run_case 8  "40320"
run_case 10 "3628800"
run_case 12 "479001600"
run_case 15 "1307674368000"
run_case 20 "2432902008176640000"

echo "wrote $csv"
