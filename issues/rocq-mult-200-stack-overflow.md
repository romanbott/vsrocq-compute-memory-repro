# Rocq: `Compute (mult 200 200)` overflows the stack while `mult 180 180` succeeds

**Component:** Rocq kernel / reduction / printing (`Compute` = `cbv`)
**Version:** Rocq 9.1.0, OCaml 4.14.2, x86_64 Linux

## Summary

`Compute` on a modest unary-`nat` multiplication raises `Error: Stack overflow.`
The cliff is between `180` and `200`, i.e. for a result of only `~4·10^4`.

## Reproducer

`rocq/mult_stack_overflow.v`:

```coq
Compute (mult 150 150).   (* = 22500 *)
Compute (mult 200 200).   (* Error: Stack overflow. *)
```

Run:

```bash
rocq repl -q < rocq/mult_stack_overflow.v
```

## Expected

`Compute (mult 200 200).` prints `= 40000 : nat` (as `mult 180 180` prints
`= 32400`).

## Actual

```
Error: Stack overflow.
```

## Evidence

`harness/sweep_nat.sh`:

| n | result | wall | peak RSS |
|---|---|---|---|
| 180 | `= 32400` | 558 ms | 329 MB |
| 200 | `Error: Stack overflow.` | 154 ms | — |
| 250 | `Error: Stack overflow.` | 160 ms | — |

## Notes / hypothesis

`Nat.mul` is structural on unary `nat`:

```coq
fix mul (n m : nat) {struct n} : nat :=
  match n with 0 => 0 | S p => m + mul p m end
```

With `cbv`, both the reduction and the printing of the resulting
`S (S (...))` chain recurse to a depth proportional to the result (`n*m`), so
`200*200 = 40000` is already enough to exhaust the OCaml stack. It is unclear
whether the overflow is in reduction or in pretty-printing; a smaller repro or a
clearer error would help. Possibly related to
[#5661](https://github.com/rocq-prover/rocq/issues/5661) (printing cost).

Attached repo reproduces this with `harness/run_capped.sh`.
