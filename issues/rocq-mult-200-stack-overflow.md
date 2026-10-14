<!-- Title: Compute (mult 200 200) overflows the stack while mult 180 180 succeeds -->

**Description of the problem**

`Compute` on a modest unary-`nat` multiplication raises
`Error: Stack overflow.` The cliff is between `180` and `200`, i.e. for a result
of only `~4·10^4`. This is the VM read-back overflowing the OCaml system stack
on OCaml 4.

Minimal reproduction repo: <REPO-URL>

**Small Rocq / Coq file to reproduce the bug**

```coq
(* rocq/mult_stack_overflow.v *)
Compute (mult 150 150).   (* = 22500 *)
Compute (mult 200 200).   (* Error: Stack overflow. *)
```

Run: `rocq repl -q < rocq/mult_stack_overflow.v`

**Version of Rocq / Coq where this bug occurs**

9.1.0 (OCaml 4.14.2, x86_64 Linux).

**Interface of Rocq / Coq where this bug occurs**

`rocq repl` / `rocq compile` (`Compute`).

**Last version of Rocq / Coq where the bug did not occur**

Not a regression as far as I know. Related: #17473 (open), #10073 and #17406
(closed); #10073 notes the issue becomes moot on OCaml 5.

**Evidence**

`harness/sweep_nat.sh`:

| n | result | wall | peak RSS |
|---|---|---|---|
| 180 | `= 32400` | 558 ms | 329 MB |
| 200 | `Error: Stack overflow.` | 154 ms | — |
| 250 | `Error: Stack overflow.` | 160 ms | — |

**Notes / hypothesis**

`Compute` is `Eval vm_compute` (see #17406), so the reduction goes through the VM
and then reads the result back into a kernel term. `Nat.mul` is structural on a
unary `nat`:

```coq
fix mul (n m : nat) {struct n} : nat :=
  match n with 0 => 0 | S p => m + mul p m end
```

`Eval cbv`, `Eval compute` and `Eval simpl` all print `= 40000` for the same
term; only `vm_compute` (and `native_compute`) overflow, which points at the VM
read-back rather than the printer. `200*200 = 40000` is already enough to exhaust
the OCaml stack.

The actionable short-term fix is probably the message/warning wording tracked in
#17473 (the "abstract-large-number" warning only concerns parsing).

---

*Prepared with AI assistance (root-cause analysis, tests, measurements). The
human author has reviewed and tested everything and takes responsibility for it.*
