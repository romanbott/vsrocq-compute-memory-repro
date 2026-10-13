#!/usr/bin/env bash
# Regenerate all measurements in ./results.
#
# Every run is hard-capped in address space (ulimit -v) and wall time, so this
# script cannot take down the host. Adjust the caps to taste.
set -eu
cd "$(dirname "$0")"
export OUTDIR=results
mkdir -p "$OUTDIR"

echo "== minimal repros =="
harness/run_capped.sh 2000 20 mult_stack_overflow rocq/mult_stack_overflow.v
harness/run_capped.sh 2000 20 unary_nat_oom       rocq/unary_nat_oom.v
harness/run_capped.sh 2000 20 binary_control      rocq/binary_control.v

echo "== sweeps =="
harness/sweep_nat.sh
harness/sweep_ecml.sh

echo "== fixed-window growth (killed by time, not OOM) =="
harness/run_capped.sh 8000 6 growth_oom rocq/unary_nat_oom.v

echo "== language server (headless vsrocqtop) =="
lsp/run_lsp_capped.sh 8000 10 rocq/unary_nat_oom.v    oomgrow
lsp/run_lsp_capped.sh 8000  8 rocq/binary_control.v   control
lsp/run_lsp_capped.sh 8000  8 rocq/mult_stack_overflow.v stackoverflow

echo "done; see $OUTDIR/"
