# VsRocq: `vsrocq.memory.limit` does not bound an in-flight computation; `vsrocqtop` grows without bound and takes the host down

**Component:** `vsrocq-language-server` / `vsrocqtop`
**Version:** 2.3.4 (installed) and current `main` (both affected)
**Rocq:** 9.1.0, OCaml 4.14.2, x86_64 Linux

## Summary

A single `Compute` in a document makes `vsrocqtop` allocate until the machine
swaps and hangs. The setting named `vsrocq.memory.limit` does not prevent this:
it is used only to trigger a `Gc.compact`/purge of *closed* documents, and the
`memprof-limits` machinery the server already links is wired for **cancellation
only**, never for a memory bound.

## Reproducer

A short recursive computation whose result is a large unary `nat` (see the Rocq
report). `rocq/unary_nat_oom.v`:

```coq
Compute (ecml [1;20;300;4;5]).  (* result is 14400000000, unary *)
```

Driven headlessly against the server (opens the file, sends
`prover/interpretToEnd`, samples the server's RSS):

```bash
lsp/run_lsp_capped.sh 8000 10 rocq/unary_nat_oom.v oomgrow
```

## Actual

Server peak RSS (8 GB address-space ceiling, 10 s window):

| file | peak RSS |
|---|---|
| `rocq/binary_control.v` (control) | 0.27 GB |
| `rocq/mult_stack_overflow.v` | 0.32 GB (errors quickly) |
| `rocq/unary_nat_oom.v` | **3.55 GB, still climbing** |

With a longer window it passes 6 GB and keeps going; setting
`memory.limit` to 2 GB does not change the curve. Uncapped it reaches the tens
of GB.

## Root cause (current `main`)

* `language-server/vsrocqtop/lspManager.ml`
  * `:42` `let max_memory_usage = ref 4000000000`
  * `:133` `max_memory_usage := settings.memory.limit * 1000000000`
  * `:332-342` `consider_purge_invisible_tabs`: when `Gc.stat().heap_words *
    word_size > max_memory_usage`, it purges *invisible* tabs and calls
    `Gc.compact ()`. This cannot reclaim the live in-flight term.
* `language-server/dm/proverThread.ml:113-115`
  `limit f token = ... Memprof_limits.limit_with_token ~token f`.
  Per the memprof-limits API, `limit_with_token` is a **cancellation** limit
  only (`token:Token.t -> (unit -> 'a) -> 'a result`). The memory limit is a
  separate API:
  * `Memprof_limits.set_global_memory_limit : int -> unit` (default **-1 =
    disabled**), and
  * `Memprof_limits.limit_global_memory : (unit -> 'a) -> 'a result`.
* A full scan of `language-server/**/*.ml` shows `set_global_memory_limit` and
  `limit_global_memory` are **never called**.

So the setting's name is misleading and no memory bound exists for a running
job.

## Expected

A single command should not be able to exhaust host memory. Options:

* enforce a real per-process memory limit and surface a diagnostic;
* cancel/abort a command that exceeds a budget;
* at minimum, document that `vsrocq.memory.limit` does not bound an in-flight
  command (it only discards states of closed documents).

## Suggested fix

`proverThread.ml` already funnels every job through `limit`, and memprof-limits
is already a dependency. The fix is to (a) feed `settings.memory.limit` into
`Memprof_limits.set_global_memory_limit` and (b) run each job under
`Memprof_limits.limit_global_memory`, nested with the existing cancellation
token. The two are distinguishable: a memory abort is `Error` from the outer
`limit_global_memory`, while a cancellation is `Ok (Error _)` from the inner
`limit_with_token`. After a memory abort the heap must be compacted, otherwise
every subsequent job is interrupted immediately.

A patch implementing this is included in this repository
(`patches/vsrocq-memory-limit.patch`, against `main`). It touches
`proverThread.ml`, `checkingManager.ml/.mli` and `lspManager.ml`, and also
fixes a related crash: `executionManager.ml` used to do
`Aborted e -> CErrors.user_err e`, which raises inside the event loop and kills
the server when any job is aborted (out-of-memory, timeout, internal error).

Validated with `vsrocq.memory.limit = 1` GB: the server now aborts at the limit
(peak RSS 3.2 GB, settling to 2.2 GB) and reports
`Rocq exceeded the configured memory limit ...`, instead of growing without
bound. Caveat: the limit is on the OCaml major heap, so RSS can exceed it by a
factor (the `vm_compute` read-back also uses a large non-heap stack).

## Notes

Related open issues:
* [#1142](https://github.com/rocq-prover/vsrocq/issues/1142) — possible memory
  leak in `vscoqtop`.
* [#746](https://github.com/rocq-prover/vsrocq/issues/746) — long-running
  orphaned `vscoqtop` processes.

`prover/interrupt` exists (per `docs/protocol.md`) but only helps once the
client decides to cancel; it does not bound memory.

Attached repo reproduces this with `lsp/`.
