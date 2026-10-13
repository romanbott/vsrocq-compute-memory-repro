#!/usr/bin/env bash
# Run the headless VsRocq driver under a hard memory cap + timeout.
#
# usage: run_lsp_capped.sh <mem_mb> <timeout_s> <file.v> [label]
set -u

mem_mb=${1:?usage: run_lsp_capped.sh <mem_mb> <timeout_s> <file.v> [label]}
timeout_s=${2:?usage: run_lsp_capped.sh <mem_mb> <timeout_s> <file.v> [label]}
file=${3:?usage: run_lsp_capped.sh <mem_mb> <timeout_s> <file.v> [label]}
label=${4:-$(basename "$file" .v)}

HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR=${OUTDIR:-results}
mkdir -p "$OUTDIR"

# The cap is inherited by vsrocqtop and any worker processes it spawns.
( ulimit -v $((mem_mb * 1024)); exec python3 "$HERE/drive_vsrocq.py" \
    --file "$file" --timeout "$timeout_s" --out "$OUTDIR" --label "$label" )
rc=$?
echo "[lsp:$label] driver exit=$rc"
exit $rc
