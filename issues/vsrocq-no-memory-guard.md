# VsRocq: `vsrocqtop` grows without bound on a single `Compute` and takes the host down

**Component:** `vsrocq-language-server` / `vsrocqtop`
**Version:** 2.3.4 (Rocq 9.1.0, OCaml 4.14.2, x86_64 Linux)

## Summary

A single `Compute` in a document makes `vsrocqtop` allocate until the machine
swaps and hangs. There appears to be no effective per-command memory ceiling or
cancellation while a command is running.

## Context

While stepping through a Software Foundations exercise file, a line

```coq
Compute eleva_cuadrado_y_multiplica_lista [1;20;300;4;5].
```

(the result is `14400000000`, a unary `nat`) caused the editor session to
consume tens of GB of RAM and freeze the whole system. The underlying Rocq
behaviour is reported separately (large unary `nat`); the point of this report is
that the **language server hosts the blow-up unboundedly**.

## Reproducer

The Rocq-level reproducer is `rocq/unary_nat_oom.v` (see the Rocq report).
Driven headlessly against the server:

```bash
lsp/run_lsp_capped.sh 8000 10 rocq/unary_nat_oom.v oomgrow
```

`lsp/drive_vsrocq.py` opens the file, sends `prover/interpretToEnd`, and samples
the server's RSS (including worker processes).

## Actual

Server peak RSS (8 GB address-space cap, 10 s window):

| file | peak RSS |
|---|---|
| `rocq/binary_control.v` (control) | 0.27 GB |
| `rocq/mult_stack_overflow.v` | 0.32 GB (reports the error quickly) |
| `rocq/unary_nat_oom.v` | **3.55 GB, still climbing** |

Growth curve for `unary_nat_oom.v` through the server:

```
7.4 s    945 MB
9.5 s   1862 MB
12.7 s  3103 MB
14.8 s  3631 MB
```

Uncapped this continues into the tens of GB. The client (an editor) sees no
error while this happens; the process simply grows until the OS kills it or the
host swaps.

## Expected

A single command should not be able to exhaust host memory. Options:

* enforce a real per-process memory limit and surface a diagnostic;
* cancel/abort a command that exceeds a budget;
* at minimum, document that `vsrocq.memory.limit` does **not** bound an
  in-flight command (it only discards states of closed documents).

## Notes

Related open issues:
* [#1142](https://github.com/rocq-prover/vsrocq/issues/1142) — possible memory
  leak in `vscoqtop`.
* [#746](https://github.com/rocq-prover/vsrocq/issues/746) — long-running
  orphaned `vscoqtop` processes.

A `prover/interrupt` verb exists (per `docs/protocol.md`); it may be relevant if
the command can be cancelled from the client while it is running.

Attached repo reproduces this with `lsp/`.
