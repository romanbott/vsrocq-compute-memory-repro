(* Control: the same numeric value computed with a *binary* representation is
   instant, because `Z`/`positive` are binary rather than unary.

   This shows the blow-up in `unary_nat_oom.v` is about the representation of
   `nat`, not about the arithmetic itself.
*)

From Stdlib Require Import ZArith.
Open Scope Z_scope.

Compute (1 * 1 * (20 * 20) * (300 * 300) * (4 * 4) * (5 * 5)).
(* = 14400000000 : Z  -- immediate *)
