(* Control: the same value computed with a *binary* representation is instant,
   because `Z`/`positive` are binary rather than unary.

   This shows the blow-up in factorial_oom.v / pow_oom.v is about the
   representation of `nat`, not about the arithmetic itself.
*)

From Stdlib Require Import ZArith.
Open Scope Z_scope.

Compute (1 * 2 * 3 * 4 * 5 * 6 * 7 * 8 * 9 * 10
         * 11 * 12 * 13 * 14 * 15 * 16 * 17 * 18 * 19 * 20).
(* = 2432902008176640000 : Z  -- immediate *)
