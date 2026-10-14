(* Same blow-up as factorial_oom.v, with a plain recursive exponential instead
   of a factorial.

   `pow 2 30` = 1_073_741_824; as a unary `nat` that is ~1 billion `S`
   constructors.

   Observed with Rocq 9.1.0 (RSS capped at 2 GB):
       pow 2 10  ->  1024
       pow 2 30  ->  Error: Out of memory.   (still climbing)

   Intermediate sizes (`pow 2 15` .. `pow 2 22`) overflow the VM's read-back
   stack first; see harness/sweep_pow.sh.
*)

Fixpoint pow (b e : nat) : nat :=
  match e with
  | 0 => 1
  | S e' => mult b (pow b e')
  end.

Compute (pow 2 10).   (* = 1024 *)
Compute (pow 2 30).   (* Error: Out of memory. *)
