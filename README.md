# Rocq / VsRocq: `Compute` memory & stack blow-ups

Two minimal, self-contained reproductions of Rocq `Compute` blowing up when the
result is a large **unary `nat`**, and of the VsRocq language server
(`vsrocqtop`) hosting that blow-up until the host runs out of memory.

The trigger is always the same: `Compute` (= `Eval vm_compute`) of an ordinary
recursive function whose result is a large `nat`. The two standard examples used
here are `factorial 20` and `pow 2 30`.

Everything below is reduced to minimal, name-free reproducers.

## Environment

```
Rocq Prover 9.1.0 (OCaml 4.14.2)
rocq-runtime / rocq-core / rocq-stdlib 9.1.0
vsrocq-language-server 2.3.4
Linux 7.2.9 x86_64, 22 cores, 30 GiB RAM (+8 GiB zram swap)
```

## Reproduce

All scripts hard-cap memory (address space) and wall time, so they are safe to
run on a normal machine. From the repository root:

```bash
./run_all.sh            # everything, capped
# or individually:
harness/run_capped.sh 2000 20 mult_stack_overflow rocq/mult_stack_overflow.v
harness/run_capped.sh 2000 20 factorial_oom       rocq/factorial_oom.v
lsp/run_lsp_capped.sh 8000 10 rocq/factorial_oom.v oomgrow
```

## Failure mode A — `Compute (mult 200 200)` overflows the stack

`rocq/mult_stack_overflow.v`:

```coq
Compute (mult 150 150).   (* = 22500 *)
Compute (mult 200 200).   (* Error: Stack overflow. *)
```

`mult` is `Nat.mul`, structural on a unary `nat`:

```coq
fix mul (n m : nat) {struct n} : nat :=
  match n with 0 => 0 | S p => m + mul p m end
```

`Compute` is in fact `Eval vm_compute` (see Rocq #17406), so the reduction goes
through the VM and then **reads the result back** into a kernel term; that
read-back recurses on the OCaml system stack, to a depth proportional to the
*result* (roughly `n*m`). Note that `Eval cbv`, `Eval compute` and `Eval simpl`
all print `= 40000` for the same term — only `vm_compute` (and
`native_compute`) overflow. `harness/sweep_nat.sh` finds the cliff:

| n | `Compute (mult n n)` | wall | peak RSS |
|---|---|---|---|
| 100 | `= 10000` | 285 ms | 236 MB |
| 150 | `= 22500` | 402 ms | 247 MB |
| 180 | `= 32400` | 558 ms | 329 MB |
| **200** | **`Error: Stack overflow.`** | 154 ms | — |
| 250 | `Error: Stack overflow.` | 160 ms | — |

## Failure mode B — large unary `nat` results exhaust memory

`rocq/factorial_oom.v`:

```coq
Fixpoint factorial (n : nat) : nat :=
  match n with 0 => 1 | S n' => mult (S n') (factorial n') end.

Compute (factorial 7).    (* = 5040 *)
Compute (factorial 20).   (* Error: Out of memory. *)
```

`factorial 20` = 2_432_902_008_176_640_000. Because `nat` is unary, materialising
that value builds ~2.4 quintillion `S` constructors, and the reduction allocates
far more than the final value itself.

`rocq/pow_oom.v` is the same story with a plain recursive exponential
(`pow 2 30` = 1_073_741_824):

```coq
Fixpoint pow (b e : nat) : nat :=
  match e with 0 => 1 | S e' => mult b (pow b e') end.

Compute (pow 2 10).   (* = 1024 *)
Compute (pow 2 30).   (* Error: Out of memory. *)
```

`harness/sweep_factorial.sh`, capped at 2 GB / 25 s:

| `Compute (factorial n)` | result | wall | peak RSS |
|---|---|---|---|
| `factorial 5` | `= 120` | 105 ms | 8 MB |
| `factorial 7` | `= 5040` | 183 ms | 9 MB |
| `factorial 8` | `Error: Stack overflow.` | 148 ms | 8 MB |
| `factorial 10` | `Error: Stack overflow.` | 350 ms | 117 MB |
| `factorial 12` | `Error: Out of memory.` | 3.3 s | 1.2 GB |
| `factorial 20` | `Error: Out of memory.` | 3.3 s | 1.3 GB |

`harness/sweep_pow.sh`, same caps:

| `Compute (pow 2 k)` | result | wall | peak RSS |
|---|---|---|---|
| `pow 2 10` | `= 1024` | 114 ms | 8 MB |
| `pow 2 15` | `Error: Stack overflow.` | 151 ms | 8 MB |
| `pow 2 20` | `Error: Stack overflow.` | 255 ms | 166 MB |
| `pow 2 22` | `Error: Stack overflow.` | 629 ms | 215 MB |
| `pow 2 25` | `Error: Out of memory.` | 2.8 s | 1.1 GB |
| `pow 2 30` | `Error: Out of memory.` | 2.8 s | 1.1 GB |

With the cap lifted, memory grows without bound. Fixed 6 s observation windows
(`harness/run_capped.sh 8000 6 growth_factorial rocq/factorial_oom.v`, and
likewise `growth_pow`) give clean, monotonic curves — ~2.9 GB and ~1.9 GB, still
climbing when the watchdog stops them:

```
growth_factorial         growth_pow
2.11 s   840 MB          2.11 s   891 MB
3.16 s  1420 MB          3.16 s  1278 MB
4.22 s  1894 MB          4.21 s  1721 MB
5.27 s  2287 MB          5.26 s  1873 MB
```

A control in a binary representation (`rocq/binary_control.v`) is instant:

```coq
From Stdlib Require Import ZArith. Open Scope Z_scope.
Compute (1 * 2 * 3 * ... * 20).  (* = 2432902008176640000 : Z *)
```

## Language-server reproduction (headless `vsrocqtop`)

`lsp/drive_vsrocq.py` speaks LSP over stdio, opens a file, sends
`prover/interpretToEnd`, and samples the **server's** RSS (including worker
processes). This shows the blow-up is hosted by the server, not caused by the
editor.

| file | server peak RSS (cap 8 GB) |
|---|---|
| `rocq/binary_control.v` | 0.28 GB |
| `rocq/mult_stack_overflow.v` | 0.31 GB (reports the error quickly) |
| `rocq/factorial_oom.v` | **3.65 GB at ~13 s, still climbing** |

Growth curve for `factorial_oom.v` through the server (unpatched 2.3.4):

```
6.8 s   2.77 GB
8.5 s   2.96 GB
10.2 s  3.22 GB
11.9 s  3.40 GB
13.6 s  3.52 GB
```

So a single `Compute` in a document makes `vsrocqtop` allocate until the machine
swaps/dies. In an editor this is what "the whole system hangs at tens of GB"
looks like.

## Status

* VsRocq issue: <ISSUE-URL>.
* Fix proposed upstream: <PR-URL> — it feeds `vsrocq.memory.limit` into
  `Memprof_limits.set_global_memory_limit` and runs every job under
  `Memprof_limits.limit_global_memory`, nested with the existing cancellation
  token, surfacing a memory abort as a sentence error. It also fixes a related
  crash: `executionManager.ml` used to do `Aborted e -> CErrors.user_err e`,
  which raised inside the event loop and killed the server.

With `vsrocq.memory.limit = 1` GB the patched server aborts at the limit (peak
RSS 3.2 GB, settling to 2.2 GB) instead of growing without bound. **Caveat:** the
limit is on the OCaml **major heap** (what memprof-limits measures);
`Compute`/`vm_compute` also allocates outside it (the VM read-back uses a large
non-heap stack), so RSS can exceed the limit by a factor (~2.6x for this repro).

## Root cause

* `nat` is unary, so any computation producing a large `nat` is
  `O(value)` in time **and** memory.
* `Compute` = `Eval vm_compute`; the VM's recursive **read-back** of the result
  has `O(value)` call depth on OCaml 4 — hence the stack overflow at
  surprisingly small numbers (`mult 200 200`). This is known upstream (#17473,
  #10073) and becomes moot on OCaml 5.
* `vsrocqtop` runs that computation in-process and provides no effective
  per-command memory ceiling: `vsrocq.memory.limit` only compacts the heap and
  discards states of *closed* documents, while the `memprof-limits` dependency
  is wired for cancellation only (`proverThread.ml`), never for a memory bound.

## Workarounds

* Don't `Compute` large unary `nat`s. Use a binary type (`Z`, `N`, `positive`)
  for big arithmetic.
* Keep `Compute` arguments small; prefer `vm_compute` for *speed* (it does not
  help the unary size).
* In VsRocq: set a low `vsrocq.memory.limit`, prefer manual proof mode over
  continuous, and keep a way to kill stray `vsrocqtop` processes.
* Wrap interactive Rocq in a cgroup / `ulimit` so a runaway `Compute` cannot
  take the host down.

## Repository layout

```
rocq/     minimal .v reproducers (no personal data)
harness/  memory-capped runner, RSS sampler, sweeps
lsp/      headless vsrocqtop driver
results/  captured measurements (CSV/logs)
```

## Safety

Every harness run uses `ulimit -v` plus a watchdog `timeout`, and the RSS
sampler records a growth curve even when the process is killed. Nothing here
can exhaust the host.

## References

* Rocq `#17473` — "Misleading stack overflow messages from Compute for largish
  numbers" (open).
* Rocq `#10073` — "wish: an option for normalizing very large terms without
  causing a stack overflow" (closed; moot on OCaml 5).
* Rocq `#17406` — "Explain stack overflow for nat, number examples" (closed);
  notes that `Compute` is `Eval vm_compute`.
* Rocq `#5661` — "printing small expressions should not take massively more
  memory than computing them".
* VsRocq `#1142` — possible memory leak in `vsrocqtop`.
* VsRocq `#746` — long-running orphaned `vsrocqtop` processes.
* VsRocq `docs/protocol.md` — `prover/interpretToEnd`, `prover/updateProofView`.
