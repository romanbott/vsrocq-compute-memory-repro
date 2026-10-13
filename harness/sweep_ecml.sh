#!/usr/bin/env bash
# Sweep `Compute (ecml [1;N])` (= N*N) to show unary-nat memory growth.
#
# `ecml [1;N]` folds to `mult 1 (mult (N*N) 1) = N*N`, so the expected result
# is a clean, monotonically increasing number.
#
# usage: sweep_ecml.sh
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR=${OUTDIR:-results}
mkdir -p "$OUTDIR/gen"

csv="$OUTDIR/sweep_ecml.csv"
echo "input,expected,result,wall_ms,peak_rss_kb,exit_code" > "$csv"

run_case() {
  local label=$1 expected=$2 list=$3
  local f="$OUTDIR/gen/ecml_$label.v"
  {
    echo 'From Stdlib Require Import List.'
    echo 'Import ListNotations.'
    echo 'Fixpoint fold {X Y : Type} (f : X -> Y -> Y) (l : list X) (b : Y) : Y :='
    echo '  match l with nil => b | h :: t => f h (fold f t b) end.'
    echo 'Definition ecml (l : list nat) : nat := fold mult (map (fun x : nat => mult x x) l) 1.'
    printf 'Compute (ecml %s).\n' "$list"
  } > "$f"

  "$HERE/run_capped.sh" 2000 25 "ecml_$label" "$f" >/dev/null

  local meta="$OUTDIR/ecml_$label.meta"
  local wall peak rc result
  wall=$(awk -F= '$1=="wall_ms"{print $2}' "$meta")
  peak=$(awk -F= '$1=="peak_rss_kb"{print $2}' "$meta")
  rc=$(awk -F= '$1=="exit_code"{print $2}' "$meta")
  result=$(grep -oE '= [0-9]+|Error: Stack overflow|Error: Out of memory' "$OUTDIR/ecml_$label.log" | tail -1)
  [ -z "$result" ] && result="(killed)"

  echo "$list,$expected,$result,$wall,$peak,$rc" >> "$csv"
  printf 'ecml %-16s -> %-26s peak=%s KB wall=%s ms\n' "$list" "$result" "$peak" "$wall"
}

run_case "1_3"        "9"          "[1;3]"
run_case "1_20"       "400"        "[1;20]"
run_case "1_100"      "10000"      "[1;100]"
run_case "1_1000"     "1000000"    "[1;1000]"
run_case "1_3000"     "9000000"    "[1;3000]"
run_case "1_10000"    "100000000"  "[1;10000]"
run_case "1_100000"   "10000000000" "[1;100000]"

echo "wrote $csv"
