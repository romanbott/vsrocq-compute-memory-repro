# Rocq / VsRocq: `Compute` memory & stack blow-ups

Two minimal, self-contained reproductions of Rocq `Compute` blowing up when the
result is a large **unary `nat`**, and of the VsRocq language server
(`vsrocqtop`) hosting that blow-up until the host runs out of memory.

The original trigger was an innocuous-looking line in a Software Foundations
exercise file:

```coq
Compute mult 200 200.                              (* line 134 *)
Compute eleva_cuadrado_y_multiplica_lista [1;20;300;4;5].   (* line 119 *)
```

* `Compute mult 200 200.`  → **`Error: Stack overflow.`**
* `Compute eleva_cuadrado_y_multiplica_lista [1;20;300;4;5].` → **out of memory**
  (the value is `14_400_000_000`, represented as a unary `nat`).

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
harness/run_capped.sh 2000 20 unary_nat_oom       rocq/unary_nat_oom.v
lsp/run_lsp_capped.sh 8000 10 rocq/unary_nat_oom.v oomgrow
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

`Compute` uses call-by-value, so reducing (and then printing the resulting
`S (S (...))` chain) recurses to a depth proportional to the *result*, roughly
`n*m`. `harness/sweep_nat.sh` finds the cliff:

| n | `Compute (mult n n)` | wall | peak RSS |
|---|---|---|---|
| 100 | `= 10000` | 285 ms | 236 MB |
| 150 | `= 22500` | 402 ms | 247 MB |
| 180 | `= 32400` | 558 ms | 329 MB |
| **200** | **`Error: Stack overflow.`** | 154 ms | — |
| 250 | `Error: Stack overflow.` | 160 ms | — |

## Failure mode B — large unary `nat` results exhaust memory

`rocq/unary_nat_oom.v`:

```coq
Definition ecml (l : list nat) : nat :=
  fold mult (map (fun x : nat => mult x x) l) 1.

Compute (ecml [1;2;3]).         (* = 36            *)
Compute (ecml [1;20;300;4;5]).  (* = 14400000000, out of memory *)
```

`ecml [1;20;300;4;5]` is `1²·20²·300²·4²·5² = 14_400_000_000`. Because `nat` is
unary, materialising that value builds ~14.4 billion `S` constructors, and the
reduction allocates far more than the final value itself.

`harness/sweep_ecml.sh` (using `ecml [1;N] = N²`), capped at 2 GB / 25 s:

| input | expected | result | wall | peak RSS |
|---|---|---|---|---|
| `[1;3]` | 9 | `= 9` | 214 ms | 8 MB |
| `[1;100]` | 10000 | `= 10000` | 400 ms | 167 MB |
| `[1;1000]` | 1 000 000 | `Error: Stack overflow.` | 502 ms | 248 MB |
| `[1;3000]` | 9 000 000 | `Error: Stack overflow.` | 2.8 s | 947 MB |
| `[1;10000]` | 100 000 000 | killed (SIGABRT, hit cap) | 13.7 s | 1.7 GB |
| `[1;100000]` | 10 000 000 000 | killed (SIGABRT, hit cap) | 13.7 s | 1.7 GB |

With the cap lifted, memory grows without bound. A fixed 6 s observation window
(`harness/run_capped.sh 8000 6 growth_oom rocq/unary_nat_oom.v`) gives a clean,
monotonic curve — ~2.7 GB and still climbing when the watchdog stops it:

```
0.64 s   300 MB
1.90 s   805 MB
3.16 s  1769 MB
4.42 s  1829 MB
5.68 s  2556 MB
```

A control in a binary representation (`rocq/binary_control.v`) is instant:

```coq
From Stdlib Require Import ZArith. Open Scope Z_scope.
Compute (1 * 1 * (20 * 20) * (300 * 300) * (4 * 4) * (5 * 5)).  (* = 14400000000 : Z *)
```

## Language-server reproduction (headless `vsrocqtop`)

`lsp/drive_vsrocq.py` speaks LSP over stdio, opens a file, sends
`prover/interpretToEnd`, and samples the **server's** RSS (including worker
processes). This shows the blow-up is hosted by the server, not caused by the
editor.

| file | server peak RSS (cap 8 GB) |
|---|---|
| `rocq/binary_control.v` | 0.27 GB |
| `rocq/mult_stack_overflow.v` | 0.32 GB (reports the error quickly) |
| `rocq/unary_nat_oom.v` | **3.55 GB at 10 s, still climbing** |

Growth curve for `unary_nat_oom.v` through the server:

```
7.4 s    945 MB
9.5 s   1862 MB
12.7 s  3103 MB
14.8 s  3631 MB
```

So a single `Compute` in a document makes `vsrocqtop` allocate until the machine
swaps/dies. In an editor this is what "the whole system hangs at tens of GB"
looks like.

## Root cause

* `nat` is unary, so any computation producing a large `nat` is
  `O(value)` in time **and** memory.
* `Compute` is `cbv`; its recursive reduction (and the pretty-printer for the
  resulting `S`-chain) also has `O(value)` call depth — hence the stack
  overflow at surprisingly small numbers (`mult 200 200`).
* `vsrocqtop` runs that computation in-process and provides no effective
  per-command memory ceiling or cancellation (the documented
  `vsrocq.memory.limit` only discards states of *closed* documents).

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
issues/   draft upstream reports
```

## Safety

Every harness run uses `ulimit -v` plus a watchdog `timeout`, and the RSS
sampler records a growth curve even when the process is killed. Nothing here
can exhaust the host.

## References

* Rocq `#5661` — "printing small expressions should not take massively more
  memory than computing them".
* VsRocq `#1142` — possible memory leak in `vsrocqtop`.
* VsRocq `#746` — long-running orphaned `vsrocqtop` processes.
* VsRocq `docs/protocol.md` — `prover/interpretToEnd`, `prover/updateProofView`.
