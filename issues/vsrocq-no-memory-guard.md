<!-- Title: [BUG] vsrocq.memory.limit does not bound an in-flight computation; vsrocqtop grows without bound and takes the host down -->

**IMPORTANT: Before You Submit This Issue**

- [x] I have searched the [existing VsRocq issues](https://github.com/rocq-prover/vsrocq/issues)
- [x] I have reviewed the [VsRocq FAQ.md](https://github.com/rocq-prover/vsrocq/blob/main/docs/FAQ.md) and my issue is not addressed there.

**Describe the Bug**

A single `Compute` in a document makes `vsrocqtop` allocate until the machine
swaps and hangs. The setting named `vsrocq.memory.limit` does not prevent this:
it is used only to trigger a `Gc.compact`/purge of *closed* documents, and the
`memprof-limits` machinery the server already links is wired for **cancellation
only**, never for a memory bound.

Minimal reproduction repo (capped harness, measurements, patch):
<REPO-URL>

**To Reproduce**

1. Open `rocq/factorial_oom.v` — a standard `factorial` whose `factorial 20`
   result is a huge unary `nat`:

   ```coq
   Fixpoint factorial (n : nat) : nat :=
     match n with 0 => 1 | S n' => mult (S n') (factorial n') end.
   Compute (factorial 20).   (* result: 2432902008176640000, unary *)
   ```

2. Ask the server to interpret the document (`prover/interpretToEnd`, or
   "Rocq: Interpret to End").
3. Watch `vsrocqtop`'s RSS grow without bound.

Headless driver used here (opens the file, sends `prover/interpretToEnd`, samples
the server's RSS):

```bash
lsp/run_lsp_capped.sh 8000 10 rocq/factorial_oom.v oomgrow
```

**Expected vs. Actual Behavior**

Expected: `vsrocq.memory.limit` (or some mechanism) should bound a running
computation and surface an error, so that a single command cannot exhaust host
memory.

Actual: the server grows without bound. Peak RSS with an 8 GB address-space
ceiling over a ~13 s window (unpatched 2.3.4):

| file | peak RSS |
|---|---|
| `rocq/binary_control.v` (control) | 0.28 GB |
| `rocq/mult_stack_overflow.v` | 0.31 GB (errors quickly) |
| `rocq/factorial_oom.v` | **3.65 GB, still climbing** |

With a longer window it keeps going. Setting `memory.limit` to 2 GB does not
change the curve. Uncapped it reaches the tens of GB and freezes the host.

**Environment (paste the result of `Rocq: Troubleshooting: Show Setup`)**

| Debug Information        | Value |
| ------------------------ | ----- |
| Rocq Installation        | 9.1.0 (opam) |
| Rocq Path                | `rocq` from the opam switch |
| VsRocq Extension Version | n/a — reproduced with a headless LSP client and vsrocq.nvim |
| VsRocqTop Version        | 2.3.4, and current `main` |
| VsRocqTop Path           | opam `vsrocqtop` (2.3.4); `_build/default/vsrocqtop/vsrocqtop.exe` (main) |
| OS                       | Linux 7.2.9 x86_64, 22 cores, 30 GiB RAM |
| VSCode Version           | n/a |

**Rocq Log Output (if applicable)**

With `vsrocq.args = ["-bt", "-vsrocq-d", "all"]`, the unbounded job is a
`promise_execution` in `proverThread`; before the fix nothing interrupts it.
Full logs and RSS curves are in the reproduction repo (`results/`).

**Root cause (current `main`)**

* `language-server/vsrocqtop/lspManager.ml`
  * `:42` `let max_memory_usage = ref 4000000000`
  * `:133` `max_memory_usage := settings.memory.limit * 1000000000`
  * `:332-342` `consider_purge_invisible_tabs`: when `Gc.stat().heap_words *
    word_size > max_memory_usage`, it purges *invisible* tabs and calls
    `Gc.compact ()`. This cannot reclaim the live in-flight term.
* `language-server/dm/proverThread.ml:113-115`
  `limit f token = ... Memprof_limits.limit_with_token ~token f`.
  Per the memprof-limits API, `limit_with_token` is a **cancellation** limit only
  (`token:Token.t -> (unit -> 'a) -> 'a result`). The memory limit is a separate
  API:
  * `Memprof_limits.set_global_memory_limit : int -> unit` (default **-1 =
    disabled**), and
  * `Memprof_limits.limit_global_memory : (unit -> 'a) -> 'a result`.
* A scan of `language-server/**/*.ml` shows `set_global_memory_limit` and
  `limit_global_memory` are **never called**.

So the setting's name is misleading and no memory bound exists for a running job.

**Suggested fix**

`proverThread.ml` already funnels every job through `limit`, and memprof-limits
is already a dependency. The fix is to (a) feed `settings.memory.limit` into
`Memprof_limits.set_global_memory_limit` and (b) run each job under
`Memprof_limits.limit_global_memory`, nested with the existing cancellation
token. The two are distinguishable: a memory abort is `Error` from the outer
`limit_global_memory`, while a cancellation is `Ok (Error _)` from the inner
`limit_with_token`. After a memory abort the heap must be compacted, otherwise
every subsequent job is interrupted immediately.

A patch is included in the reproduction repo (`patches/vsrocq-memory-limit.patch`,
against `main`). It touches `proverThread.ml`, `checkingManager.ml/.mli` and
`lspManager.ml`, and also fixes a related crash: `executionManager.ml` used to do
`Aborted e -> CErrors.user_err e`, which raises inside the event loop and kills
the server whenever a job is aborted (out-of-memory, timeout, internal error).

Validated with `vsrocq.memory.limit = 1` GB: the server now aborts at the limit
(peak RSS 3.2 GB, settling to 2.2 GB) and reports
`Rocq exceeded the configured memory limit ...`. Caveat: the limit is on the
OCaml major heap, so RSS can exceed it by a factor (the `vm_compute` read-back
also uses a large non-heap stack).

**Notes**

Related open issues:
* [#1142](https://github.com/rocq-prover/vsrocq/issues/1142) — possible memory
  leak in `vscoqtop`.
* [#746](https://github.com/rocq-prover/vsrocq/issues/746) — long-running
  orphaned `vscoqtop` processes.

`prover/interrupt` exists (per `docs/protocol.md`) but only helps once the client
decides to cancel; it does not bound memory.

---

*Prepared with AI assistance (root-cause analysis, patch, tests, measurements).
The human author has reviewed and tested the changes and takes responsibility for
them.*
