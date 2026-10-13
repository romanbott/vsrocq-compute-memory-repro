(* Minimal reproducer: computing a modest unary-nat multiplication overflows
   the OCaml stack in Rocq's reduction/printing machinery.

   `mult` is `Nat.mul`, which is defined by structural recursion on a unary
   `nat`:

       fix mul (n m : nat) {struct n} : nat :=
         match n with
         | 0 => 0
         | S p => m + mul p m
         end

   `Compute` uses call-by-value (`cbv`), so the reduction (and the printing of
   the resulting `S (S (...))` chain) recurses to a depth proportional to the
   *result*, i.e. roughly n*m for `mult n m`.

   Observed with Rocq 9.1.0:
       mult 150 150  ->  22500            (ok)
       mult 200 200  ->  Error: Stack overflow.
*)

Compute (mult 150 150).
Compute (mult 200 200).
