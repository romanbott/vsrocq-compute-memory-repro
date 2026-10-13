(* Minimal reproducer: a small-looking recursive computation whose result is a
   large *unary* `nat`. Memory grows without bound until the process is killed.

   `ecml [1;20;300;4;5]` computes
       (1*1) * (20*20) * (300*300) * (4*4) * (5*5)
     = 1 * 400 * 90000 * 16 * 25
     = 14_400_000_000

   Because `nat` is unary (`S (S (S ...))`), materialising that value builds
   ~14.4 billion constructors. Under a 2 GB cap this process dies in a few
   seconds after climbing past ~1.8 GB; uncapped it grows into the tens of GB
   and can take the whole machine down (especially when driven by an IDE).

   Observed with Rocq 9.1.0 (RSS capped at 2 GB):
       ecml [1;2;3]        ->  36            (ok, ~70 MB)
       ecml [1;20;30]      ->  Error: Stack overflow.
       ecml [1;20;300;4;5] ->  Error: Out of memory.   (still climbing)
*)

From Stdlib Require Import List.
Import ListNotations.

Fixpoint fold {X Y : Type} (f : X -> Y -> Y) (l : list X) (b : Y) : Y :=
  match l with
  | nil => b
  | h :: t => f h (fold f t b)
  end.

Definition ecml (l : list nat) : nat :=
  fold mult (map (fun x : nat => mult x x) l) 1.

Compute (ecml [1;2;3]).         (* = 36 *)
Compute (ecml [1;20;300;4;5]).  (* = 14400000000, OOM *)
