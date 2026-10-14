# language-server: enforce `vsrocq.memory.limit` on running computations

Fixes #<ISSUE-NUMBER> (link the VsRocq issue once filed).

## Motivation

`vsrocq.memory.limit` only triggered a `Gc.compact`/purge of *closed* documents;
it never bounded an in-flight computation, and the `memprof-limits` dependency
was wired for cancellation only. A single `Compute` producing a large unary
`nat` (e.g. `factorial 20`) could therefore grow `vsrocqtop` without bound until
the host ran out of memory. Reproduction, measurements and a capped harness:
<REPO-URL>.

## What changed

- `dm/proverThread.ml`
  - `set_options ~memory_limit` now calls
    `Memprof_limits.set_global_memory_limit`.
  - `limit` runs every job under `Memprof_limits.limit_global_memory`, nested
    with the existing cancellation token. A memory abort surfaces as `Error`
    from the outer wrapper; a cancellation as `Ok (Error _)` from the inner one.
  - On a memory abort, `Gc.compact ()` is called so the heap shrinks below the
    limit (otherwise every subsequent job would be interrupted immediately).
- `dm/checkingManager.ml/.mli` and `vsrocqtop/lspManager.ml`: plumb
  `vsrocq.memory.limit` (GB -> kiB) through to `proverThread`.
- `dm/executionManager.ml`: `Aborted e` is now reported as a sentence error
  instead of `CErrors.user_err e`, which raised inside the event loop and killed
  the server whenever a job was aborted (out-of-memory, timeout, internal error).
  The old code even carried a `(* bug in vsrocq *)` comment.
- `tests/proverThread_tests.ml`: regression test (a job allocating past the
  limit is aborted).
- `client/package.json`, `docs/FAQ.md`: corrected the description of
  `vsrocq.memory.limit`.

## Testing

With `vsrocq.memory.limit = 1` GB and `rocq/factorial_oom.v`:

| | unpatched (2.3.4) | patched |
|---|---|---|
| behaviour | grows without bound | aborts at the limit |
| peak RSS | 3.65 GB at 13 s, still climbing | 3.23 GB peak, settles to 2.18 GB |
| server | OOMs the host / is killed | survives and reports an error |
| diagnostic | — | `Rocq exceeded the configured memory limit ...` |

Local checks:
- Rocq **9.3.0** (OCaml 4.14.2): `make fatalwarnings` and `make test` are fully
  green (27/27, including the new test).
- Rocq **9.1.0**: `make fatalwarnings` green; `make test` is 26/27 — the only
  failure is the pre-existing `parse.feedback_attached_before_execution`, because
  9.1.0 emits `notation-bound-to-variable` instead of the expected
  `level-0-notation-not-closed` (that warning exists in 9.2/9.3/dev, which is
  what CI runs `make test` against).
- `client && npm run package` green.

## Caveat

The limit is on the OCaml **major heap** (what memprof-limits measures).
`Compute`/`vm_compute` also allocates outside it (the VM read-back uses a large
non-heap stack), so RSS can exceed the limit by a factor (~2.6x for the repro).
The bound is therefore approximate; users can lower the limit.

## Checklist

- [x] Added / updated tests (`tests/proverThread_tests.ml`).
- [x] Updated documentation (`docs/FAQ.md`, `client/package.json` description).
- [x] Documented the changed user-facing behaviour.

---

*Prepared with AI assistance (root-cause analysis, patch, tests, measurements).
The human author has reviewed and tested the changes and takes responsibility for
them.*
