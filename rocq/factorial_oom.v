(* Minimal reproducer: `Compute` on a standard recursive function whose result
   is a large *unary* `nat`.  Memory grows without bound until the process is
   killed.

   `nat` is unary (`S (S (S ...))`), so materialising `factorial 20`
   (= 2_432_902_008_176_640_000) builds ~2.4 quintillion constructors.

   Observed with Rocq 9.1.0 (RSS capped at 2 GB):
       factorial 7   ->  5040
       factorial 20  ->  Error: Out of memory.   (still climbing)

   Intermediate sizes (`factorial 8` .. `factorial 10`) overflow the VM's
   read-back stack first; see harness/sweep_factorial.sh.
*)

Fixpoint factorial (n : nat) : nat :=
  match n with
  | 0 => 1
  | S n' => mult (S n') (factorial n')
  end.

Compute (factorial 7).    (* = 5040 *)
Compute (factorial 20).   (* Error: Out of memory. *)
