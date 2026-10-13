# Rocq: `Compute` of a modest recursive expression with a large unary `nat` result consumes unbounded memory

**Component:** Rocq kernel / reduction (`Compute` = `cbv`)
**Version:** Rocq 9.1.0, OCaml 4.14.2, x86_64 Linux

## Summary

A short, ordinary-looking `Compute` allocates without bound because its result
is a large unary `nat`. Under a 2 GB cap it dies within seconds; uncapped it
grows into the tens of GB and can take the machine down (especially through an
IDE's language server).

## Reproducer

`rocq/unary_nat_oom.v`:

```coq
From Stdlib Require Import List.
Import ListNotations.

Fixpoint fold {X Y : Type} (f : X -> Y -> Y) (l : list X) (b : Y) : Y :=
  match l with nil => b | h :: t => f h (fold f t b) end.

Definition ecml (l : list nat) : nat :=
  fold mult (map (fun x : nat => mult x x) l) 1.

Compute (ecml [1;2;3]).         (* = 36 *)
Compute (ecml [1;20;300;4;5]).  (* = 14400000000, out of memory *)
```

Run (capped, safe):

```bash
harness/run_capped.sh 2000 20 unary_nat_oom rocq/unary_nat_oom.v
```

## Expected

The computation either completes or fails quickly with a diagnostic. `36` is
computed instantly, so `14_400_000_000` should be feasible in principle.

## Actual

* `ecml [1;2;3]` → `= 36` (8 MB).
* `ecml [1;20;30]` (= 360000) → `Error: Stack overflow.`
* `ecml [1;20;300;4;5]` (= 14400000000) → `Error: Out of memory.`

## Evidence

`harness/sweep_ecml.sh` (using `ecml [1;N] = N²`), cap 2 GB / 25 s:

| input | expected | result | wall | peak RSS |
|---|---|---|---|---|
| `[1;3]` | 9 | `= 9` | 214 ms | 8 MB |
| `[1;100]` | 10000 | `= 10000` | 400 ms | 167 MB |
| `[1;1000]` | 1 000 000 | `Error: Stack overflow.` | 502 ms | 248 MB |
| `[1;3000]` | 9 000 000 | `Error: Stack overflow.` | 2.8 s | 947 MB |
| `[1;10000]` | 100 000 000 | killed (SIGABRT, hit cap) | 13.7 s | 1.7 GB |
| `[1;100000]` | 10 000 000 000 | killed (SIGABRT, hit cap) | 13.7 s | 1.7 GB |

Fixed 6 s window, 8 GB ceiling (killed by time, still climbing):

```
0.64 s   300 MB
1.90 s   805 MB
3.16 s  1769 MB
4.42 s  1829 MB
5.68 s  2556 MB
```

The same value in a binary type is instant
(`rocq/binary_control.v`, `Z`): `= 14400000000 : Z`.

## Notes

This may be partly "working as intended" (unary `nat` is inherently `O(value)`),
but the ratio of memory to result, the absence of any diagnostic, and the
combination with an IDE server (see the VsRocq report) make it worth a look.
Related: [#5661](https://github.com/rocq-prover/rocq/issues/5661).

Attached repo reproduces this with `harness/`.
