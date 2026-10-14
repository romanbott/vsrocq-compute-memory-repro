<!-- Title: Compute of a standard recursive function with a large unary nat result consumes unbounded memory -->

**Description of the problem**

A short, ordinary `Compute` allocates without bound because its result is a
large unary `nat`. Under a 2 GB cap it dies within seconds; uncapped it grows
into the tens of GB and can take the machine down (especially through an IDE's
language server). Small values are instant, so this is surprising.

Minimal reproduction repo (capped harness, measurements):
<REPO-URL>

**Small Rocq / Coq file to reproduce the bug**

```coq
(* rocq/factorial_oom.v *)
Fixpoint factorial (n : nat) : nat :=
  match n with 0 => 1 | S n' => mult (S n') (factorial n') end.

Compute (factorial 7).    (* = 5040 *)
Compute (factorial 20).   (* Error: Out of memory. *)
```

Same blow-up with a plain recursive exponential (`rocq/pow_oom.v`):

```coq
Fixpoint pow (b e : nat) : nat :=
  match e with 0 => 1 | S e' => mult b (pow b e') end.

Compute (pow 2 10).   (* = 1024 *)
Compute (pow 2 30).   (* Error: Out of memory. *)
```

Run (capped, safe): `harness/run_capped.sh 2000 20 factorial_oom rocq/factorial_oom.v`

**Version of Rocq / Coq where this bug occurs**

9.1.0 (OCaml 4.14.2, x86_64 Linux). Also observed via VsRocq 2.3.4.

**Interface of Rocq / Coq where this bug occurs**

`rocq repl` (`Compute`) and VsRocq (`vsrocqtop`, 2.3.4 and current `main`).

**Last version of Rocq / Coq where the bug did not occur**

Not a regression: `Compute` has always materialised unary `nat`s; the issue is
the lack of a diagnostic/bound. (Related closed reports: #10073, #17406.)

**Evidence**

`harness/sweep_factorial.sh` / `harness/sweep_pow.sh`, cap 2 GB / 25 s:

| `Compute` | result | wall | peak RSS |
|---|---|---|---|
| `factorial 7` | `= 5040` | 183 ms | 9 MB |
| `factorial 8` | `Error: Stack overflow.` | 148 ms | 8 MB |
| `factorial 10` | `Error: Stack overflow.` | 350 ms | 117 MB |
| `factorial 12` | `Error: Out of memory.` | 3.3 s | 1.2 GB |
| `factorial 20` | `Error: Out of memory.` | 3.3 s | 1.3 GB |
| `pow 2 10` | `= 1024` | 114 ms | 8 MB |
| `pow 2 20` | `Error: Stack overflow.` | 255 ms | 166 MB |
| `pow 2 25` | `Error: Out of memory.` | 2.8 s | 1.1 GB |
| `pow 2 30` | `Error: Out of memory.` | 2.8 s | 1.1 GB |

Fixed 6 s window, 8 GB ceiling (killed by time, still climbing):

```
factorial 20              pow 2 30
2.11 s   840 MB           2.11 s   891 MB
3.16 s  1420 MB           3.16 s  1278 MB
4.22 s  1894 MB           4.21 s  1721 MB
5.27 s  2287 MB           5.26 s  1873 MB
```

The same value in a binary type is instant (`rocq/binary_control.v`, `Z`):
`= 2432902008176640000 : Z`.

**Notes**

This may be partly "working as intended" (unary `nat` is inherently `O(value)`),
but the ratio of memory to result, the absence of any diagnostic, and the
combination with an IDE server make it worth a look. Related:
[#5661](https://github.com/rocq-prover/rocq/issues/5661).

---

*Prepared with AI assistance (root-cause analysis, tests, measurements). The
human author has reviewed and tested everything and takes responsibility for it.*
