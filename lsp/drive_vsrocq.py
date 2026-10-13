#!/usr/bin/env python3
"""Headless driver for the VsRocq language server (vsrocqtop).

It speaks LSP over stdio, opens a Rocq file, asks the server to interpret it
end-to-end (`prover/interpretToEnd`), and samples the server's memory
(including any worker processes) while it runs.

This isolates the *server's* memory behaviour from the editor, so we can tell
whether a runaway `Compute` is merely hosted by the server or amplified by it.

usage:
    drive_vsrocq.py --file rocq/unary_nat_oom.v --timeout 60 --out results

environment:
    VSROCQTOP   server binary (default: vsrocqtop)
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

# Must match Protocol.Settings.t in the server. All required fields present so
# the server actually parses (and applies) the configuration.
SETTINGS = {
    "proof": {
        "delegation": "None",
        "workers": None,
        "mode": 0,  # 0 = Manual
        "block": True,
        "pointInterpretationMode": 0,
    },
    "goals": {"messages": {"full": True}},
    "completion": {"enable": False, "algorithm": 0, "unificationLimit": 100},
    "diagnostics": {"enable": True, "full": True},
    "memory": {"limit": 4},  # gigabytes
    "interrupt": {"preempt": False},
}


def log(*a):
    print(*a, file=sys.stderr, flush=True)


class RssSampler(threading.Thread):
    """Samples VmRSS of a pid and all of its descendants."""

    def __init__(self, pid: int, out_csv: Path, interval: float = 0.2):
        super().__init__(daemon=True)
        self.pid = pid
        self.out_csv = out_csv
        self.interval = interval
        self.stop = threading.Event()
        self.peak_kb = 0

    @staticmethod
    def _ppid_map() -> dict[int, list[int]]:
        children: dict[int, list[int]] = {}
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            try:
                with open(f"/proc/{entry}/stat", "rb") as fh:
                    fields = fh.read().split()
                ppid = int(fields[3])
            except (OSError, IndexError, ValueError):
                continue
            children.setdefault(ppid, []).append(int(entry))
        return children

    def _tree_rss(self) -> dict:
        children = self._ppid_map()
        rss: dict[int, int] = {}
        stack = [self.pid]
        seen = set()
        while stack:
            pid = stack.pop()
            if pid in seen:
                continue
            seen.add(pid)
            try:
                with open(f"/proc/{pid}/status") as fh:
                    for line in fh:
                        if line.startswith("VmRSS:"):
                            rss[pid] = int(line.split()[1])
                            break
            except OSError:
                pass
            stack.extend(children.get(pid, []))
        return rss

    def run(self):
        start = time.monotonic()
        with open(self.out_csv, "w") as out:
            out.write("t_ms,rss_kb,nprocs,max_proc_kb\n")
            while not self.stop.is_set():
                try:
                    os.kill(self.pid, 0)
                except OSError:
                    break
                tree = self._tree_rss()
                total = sum(tree.values())
                nprocs = len(tree)
                max_proc = max(tree.values()) if tree else 0
                self.peak_kb = max(self.peak_kb, total)
                out.write(f"{int((time.monotonic() - start) * 1000)},{total},{nprocs},{max_proc}\n")
                out.flush()
                self.stop.wait(self.interval)


class LspClient:
    def __init__(self, proc: subprocess.Popen, on_message):
        self.proc = proc
        self.on_message = on_message
        self._buf = b""
        self._lock = threading.Lock()

    def send(self, msg: dict):
        body = json.dumps(msg).encode()
        with self._lock:
            self.proc.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode())
            self.proc.stdin.write(body)
            self.proc.stdin.flush()

    def request(self, msg_id, method, params):
        self.send({"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params})

    def notify(self, method, params):
        self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def reader(self):
        stdout = self.proc.stdout
        while True:
            chunk = stdout.read(1)
            if not chunk:
                break
            self._buf += chunk
            while b"\r\n\r\n" in self._buf:
                header, self._buf = self._buf.split(b"\r\n\r\n", 1)
                length = 0
                for line in header.split(b"\r\n"):
                    if line.lower().startswith(b"content-length:"):
                        length = int(line.split(b":", 1)[1].strip())
                while len(self._buf) < length:
                    more = stdout.read(length - len(self._buf))
                    if not more:
                        return
                    self._buf += more
                body, self._buf = self._buf[:length], self._buf[length:]
                try:
                    self.on_message(json.loads(body))
                except Exception as exc:  # noqa: BLE001
                    log(f"[driver] bad message: {exc}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--timeout", type=float, default=60.0)
    ap.add_argument("--out", default="results")
    ap.add_argument("--server", default=os.environ.get("VSROCQTOP", "vsrocqtop"))
    ap.add_argument("--debug", action="store_true", help="pass -vsrocq-d all -bt")
    ap.add_argument("--label", default=None)
    ap.add_argument(
        "--memory-limit",
        type=int,
        default=None,
        help="value (in GB) for the server's vsrocq.memory.limit setting",
    )
    args = ap.parse_args()

    if args.memory_limit is not None:
        SETTINGS["memory"]["limit"] = args.memory_limit

    src = Path(args.file).resolve()
    text = src.read_text()
    uri = src.as_uri()
    label = args.label or src.stem

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    rss_csv = outdir / f"lsp_{label}.rss.csv"
    server_log = outdir / f"lsp_{label}.server.log"

    cmd = [args.server]
    if args.debug:
        cmd += ["-bt", "-vsrocq-d", "all"]
    cmd += ["-Q", str(src.parent), "Repro"]

    log(f"[driver] server: {' '.join(cmd)}")
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=open(server_log, "wb"),
    )

    init_done = threading.Event()

    def on_message(msg: dict):
        method = msg.get("method")
        if method is not None:
            if "id" in msg:  # server -> client request
                if method == "workspace/configuration":
                    client.send({"jsonrpc": "2.0", "id": msg["id"], "result": [SETTINGS]})
                else:
                    client.send({"jsonrpc": "2.0", "id": msg["id"], "result": None})
            else:  # notification
                if method in ("window/logMessage", "window/showMessage"):
                    log(f"[server:{method}] {msg.get('params')}")
                elif "proofView" in method or "updateProofView" in method:
                    pv = msg.get("params", {})
                    msgs = pv.get("messages") or []
                    if msgs:
                        log(f"[server:{method}] {len(msgs)} message(s), last={msgs[-1][0]}")
        elif "id" in msg:  # response to one of our requests
            log(f"[server] response id={msg.get('id')}")
            if msg.get("id") == 1:
                init_done.set()

    client = LspClient(proc, on_message)
    threading.Thread(target=client.reader, daemon=True).start()
    sampler = RssSampler(proc.pid, rss_csv)
    sampler.start()

    client.request(
        1,
        "initialize",
        {
            "processId": os.getpid(),
            "rootUri": src.parent.as_uri(),
            "capabilities": {},
            "initializationOptions": SETTINGS,
        },
    )
    init_done.wait(5)
    client.notify("initialized", {})
    client.notify("workspace/didChangeConfiguration", {"settings": SETTINGS})
    client.notify(
        "textDocument/didOpen",
        {
            "textDocument": {
                "uri": uri,
                "languageId": "rocq",
                "version": 1,
                "text": text,
            }
        },
    )
    # Parsing is triggered by didOpen and can restart, cancelling an
    # interpretToEnd sent too early.  Let it settle, then ask once (re-sending
    # would re-run the whole document).
    time.sleep(2.0)
    client.notify(
        "prover/interpretToEnd",
        {"textDocument": {"uri": uri, "version": 1}},
    )

    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            log(f"[driver] server exited with code {proc.returncode}")
            break
        time.sleep(0.5)
    else:
        log(f"[driver] timeout after {args.timeout}s; terminating server")
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()

    sampler.stop.set()
    sampler.join(2)

    meta = outdir / f"lsp_{label}.meta"
    meta.write_text(
        "\n".join(
            [
                f"file={src}",
                f"server={' '.join(cmd)}",
                f"timeout_s={args.timeout}",
                f"server_exit={proc.returncode}",
                f"peak_rss_kb={sampler.peak_kb}",
                f"rss_csv={rss_csv}",
                f"server_log={server_log}",
                "",
            ]
        )
    )
    log(f"[driver] peak RSS (server + workers) = {sampler.peak_kb} KB")
    log(f"[driver] wrote {meta}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
