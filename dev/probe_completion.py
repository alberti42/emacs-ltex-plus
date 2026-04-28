#!/usr/bin/env python3
"""Probe textDocument/completion against a running ltex-ls-plus.

Spawns ltex-ls-plus over stdio, performs the LSP handshake with
completionEnabled=true, opens a synthetic markdown document, and sends
a textDocument/completion at the end of the document.

Usage:
    dev/probe_completion.py "Some text wonder"
    dev/probe_completion.py --server /path/to/ltex-ls-plus --language en-US "wonder"
    dev/probe_completion.py --raw "wonder"   # dump full JSON response
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from typing import Any


def _frame(payload: dict) -> bytes:
    body = json.dumps(payload).encode("utf-8")
    return f"Content-Length: {len(body)}\r\n\r\n".encode("ascii") + body


def _read_message(stream) -> dict:
    headers = {}
    while True:
        line = stream.readline()
        if not line:
            raise EOFError("server closed stdout")
        line = line.decode("ascii", errors="replace").rstrip("\r\n")
        if not line:
            break
        key, _, value = line.partition(":")
        headers[key.strip().lower()] = value.strip()
    length = int(headers["content-length"])
    body = stream.read(length)
    return json.loads(body)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("text", help="document text; completion fires at its end")
    parser.add_argument("--server", default=shutil.which("ltex-ls-plus") or "ltex-ls-plus")
    parser.add_argument("--language", default="en-US")
    parser.add_argument("--raw", action="store_true", help="print full JSON response")
    parser.add_argument("--limit", type=int, default=20, help="labels to print in summary mode")
    parser.add_argument("--trace", action="store_true", help="log all JSON-RPC traffic to stderr")
    args = parser.parse_args()

    def trace(direction: str, payload: dict) -> None:
        if args.trace:
            sys.stderr.write(f"--- {direction} ---\n{json.dumps(payload, indent=2)}\n")

    proc = subprocess.Popen(
        [args.server],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=sys.stderr if args.trace else subprocess.DEVNULL,
    )

    next_id = iter(range(1, 10_000))

    settings_holder: dict = {}

    def respond(rid: int, result: Any) -> None:
        payload = {"jsonrpc": "2.0", "id": rid, "result": result}
        trace("CLIENT->SERVER (response)", payload)
        proc.stdin.write(_frame(payload))
        proc.stdin.flush()

    def handle_server_request(msg: dict) -> None:
        method = msg.get("method")
        rid = msg.get("id")
        if method == "workspace/configuration":
            # Server asks for one entry per `items[]`; return matching settings
            # by walking the dotted section name through settings_holder.
            items = msg.get("params", {}).get("items", []) or []
            out = []
            for item in items:
                section = item.get("section", "")
                node: Any = settings_holder
                for part in section.split("."):
                    if isinstance(node, dict) and part in node:
                        node = node[part]
                    else:
                        node = None
                        break
                out.append(node)
            respond(rid, out)
        elif method == "client/registerCapability":
            respond(rid, None)
        elif method == "workspace/workspaceFolders":
            respond(rid, [])
        elif rid is not None:
            # Unknown server-to-client request: respond with null to unblock.
            respond(rid, None)

    saw_diagnostics = {"flag": False}

    def pump_until(predicate) -> dict:
        while True:
            msg = _read_message(proc.stdout)
            trace("SERVER->CLIENT", msg)
            if "method" in msg and msg.get("id") is not None:
                handle_server_request(msg)
            elif "method" in msg:
                if msg["method"] == "textDocument/publishDiagnostics":
                    saw_diagnostics["flag"] = True
            if predicate(msg):
                return msg

    def request(method: str, params: dict) -> dict:
        rid = next(next_id)
        payload = {"jsonrpc": "2.0", "id": rid, "method": method, "params": params}
        trace("CLIENT->SERVER (request)", payload)
        proc.stdin.write(_frame(payload))
        proc.stdin.flush()
        return pump_until(lambda m: m.get("id") == rid)

    def notify(method: str, params: dict) -> None:
        payload = {"jsonrpc": "2.0", "method": method, "params": params}
        trace("CLIENT->SERVER (notify)", payload)
        proc.stdin.write(_frame(payload))
        proc.stdin.flush()

    request(
        "initialize",
        {
            "processId": None,
            "rootUri": None,
            "capabilities": {
                "textDocument": {
                    "completion": {
                        "completionItem": {"snippetSupport": False}
                    }
                }
            },
            "initializationOptions": {
                # Some clients accept settings here; ltex-ls-plus also reads
                # workspace/configuration. We pass the flag both ways.
                "completionEnabled": True,
            },
        },
    )
    notify("initialized", {})

    settings_holder["ltex"] = {
        "enabled": ["markdown", "latex", "tex", "html", "org"],
        "language": args.language,
        "completionEnabled": True,
    }
    notify("workspace/didChangeConfiguration", {"settings": settings_holder})

    uri = "file:///tmp/probe.md"
    notify(
        "textDocument/didOpen",
        {
            "textDocument": {
                "uri": uri,
                "languageId": "markdown",
                "version": 1,
                "text": args.text,
            }
        },
    )

    # Wait for the server to publish diagnostics (= done parsing/spell-checking).
    pump_until(lambda _m: saw_diagnostics["flag"])

    lines = args.text.split("\n")
    line = len(lines) - 1
    character = len(lines[-1])

    response = request(
        "textDocument/completion",
        {
            "textDocument": {"uri": uri},
            "position": {"line": line, "character": character},
            "context": {"triggerKind": 1},
        },
    )

    notify("exit", {})
    proc.wait(timeout=5)

    result: Any = response.get("result")
    if result is None:
        print(json.dumps(response, indent=2))
        return 1

    if args.raw:
        print(json.dumps(result, indent=2))
        return 0

    items = result["items"] if isinstance(result, dict) else result
    print(f"items: {len(items)}")
    for item in items[: args.limit]:
        label = item.get("label")
        kind = item.get("kind")
        filt = item.get("filterText")
        ins = item.get("insertText")
        edit = item.get("textEdit")
        extras = []
        if kind is not None:
            extras.append(f"kind={kind}")
        if filt is not None and filt != label:
            extras.append(f"filterText={filt!r}")
        if ins is not None and ins != label:
            extras.append(f"insertText={ins!r}")
        if edit is not None:
            extras.append("textEdit=set")
        suffix = f"  [{', '.join(extras)}]" if extras else ""
        print(f"  {label!r}{suffix}")
    if len(items) > args.limit:
        print(f"  ... ({len(items) - args.limit} more)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
