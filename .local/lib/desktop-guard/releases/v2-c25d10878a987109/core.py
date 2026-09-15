#!/usr/bin/env python3
"""Provider-neutral, action-scoped desktop approval ledger.

Adapters pass their native hook envelope to :func:`handle`.  The optional
``policy`` module is deliberately imported only after an already-approved
action has been matched, so a broken classifier cannot strand safe work or an
existing exact retry.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import importlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from typing import Any, Iterator


REQUEST_TTL_SECONDS = 2 * 60 * 60
PERMIT_TTL_SECONDS = 5 * 60
CODE_RE = re.compile(r"\A\s*(YES|NO)\s+(DSK-[A-F0-9]{6})\s*\Z", re.IGNORECASE)
REQUEST_ID_RE = re.compile(r"\ADSK-[A-F0-9]{6}\Z")
# These are provider-native, non-executing inspection tools.  This deliberately
# small path lets ordinary reads continue even when the optional policy or its
# ledger is unavailable; every executable tool still reaches policy.
KNOWN_SAFE_READ_TOOLS = {"Read", "Glob", "Grep", "Search", "ListMcpResources", "ReadMcpResource"}


def default_root() -> Path:
    """Return the private, per-user runtime ledger location without creating it."""
    uid = os.getuid()
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        return Path(runtime) / "agent-desktop-guard-v2"
    candidate = Path(f"/run/user/{uid}")
    if candidate.is_dir():
        return candidate / "agent-desktop-guard-v2"
    return Path(f"/tmp/agent-desktop-guard-v2-{uid}")


def ensure_root(root: Path | None) -> Path:
    path = Path(root) if root is not None else default_root()
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError(f"unsafe desktop-guard state directory: {path}")
    os.chmod(path, 0o700)
    records = path / "records"
    records.mkdir(mode=0o700, exist_ok=True)
    os.chmod(records, 0o700)
    return path


def _canonical(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str)
    except (TypeError, ValueError) as exc:
        raise RuntimeError(f"cannot encode hook action: {exc}") from exc


def identity(payload: dict[str, Any], provider: str) -> dict[str, str]:
    session = str(payload.get("session_id") or "").strip()
    origin = next((str(payload.get(key) or "").strip() for key in (
        "agent_id", "agent_transcript_path", "transcript_path"
    ) if str(payload.get(key) or "").strip()), "")
    return {"provider": provider, "session": session, "origin": origin}


def automatic_permit_possible(actor: dict[str, str]) -> bool:
    """A shared provider session never identifies a child actor by itself."""
    return bool(actor["session"] and actor["origin"])


def base_fingerprint(payload: dict[str, Any], actor: dict[str, str]) -> str:
    # tool_input is the complete argument object supplied by the provider.
    material = {
        "provider": actor["provider"], "session": actor["session"], "origin": actor["origin"],
        "cwd": payload.get("cwd", ""), "tool_name": payload.get("tool_name", ""),
        "arguments": payload.get("tool_input"),
    }
    return hashlib.sha256(_canonical(material).encode("utf-8")).hexdigest()


def fingerprint(payload: dict[str, Any], actor: dict[str, str], bindings: dict[str, Any] | None = None) -> str:
    material = {"base": base_fingerprint(payload, actor), "bindings": bindings or {}}
    return hashlib.sha256(_canonical(material).encode("utf-8")).hexdigest()


def describe(payload: dict[str, Any]) -> str:
    """Preserve the entire action for review; deliberately do not truncate."""
    name = str(payload.get("tool_name") or "unknown tool")
    return f"{name}: {_canonical(payload.get('tool_input'))} (cwd={payload.get('cwd', '')})"


def _record_path(root: Path, request_id: str) -> Path:
    if not REQUEST_ID_RE.fullmatch(request_id):
        raise ValueError("invalid desktop approval code")
    return root / "records" / f"{request_id}.json"


@contextmanager
def _locked(path: Path) -> Iterator[None]:
    lock_path = path.with_suffix(".lock")
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        os.close(descriptor)


def _write_atomic(path: Path, value: dict[str, Any]) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=".desktop-guard-", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def _audit(root: Path, event: str, record: dict[str, Any] | None = None, note: str | None = None) -> None:
    """Best-effort diagnostics; never make the approval path depend on logging."""
    try:
        actor = record.get("actor", {}) if record else {}
        entry = {
            "time": time.time(), "event": event, "provider": actor.get("provider"),
            "session": actor.get("session"), "origin": actor.get("origin"),
            "request_id": record.get("request_id") if record else None,
            "fingerprint": record.get("fingerprint") if record else None,
            "reason": record.get("reason") if record else None, "note": note,
        }
        descriptor = os.open(root / "audit.jsonl", os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
        try:
            os.write(descriptor, (_canonical(entry) + "\n").encode("utf-8"))
        finally:
            os.close(descriptor)
    except OSError:
        pass


def _valid_record(data: Any) -> dict[str, Any]:
    required = ("request_id", "actor", "base_fingerprint", "fingerprint", "reason", "action", "status", "expires_at", "operator_only", "tool_name", "tool_input", "cwd")
    if not isinstance(data, dict) or any(key not in data for key in required):
        raise ValueError("record is missing required fields")
    if not isinstance(data["actor"], dict) or not all(isinstance(data["actor"].get(key), str) for key in ("provider", "session", "origin")):
        raise ValueError("record actor is invalid")
    if data["status"] not in {"pending", "approved"}:
        raise ValueError("record status is invalid")
    float(data["expires_at"])
    return data


def _quarantine(path: Path) -> str:
    target = path.with_name(f"{path.name}.corrupt-{int(time.time())}-{secrets.token_hex(2)}")
    try:
        os.replace(path, target)
        return f"quarantined malformed ledger record {path.name}"
    except OSError as exc:
        return f"could not quarantine malformed ledger record {path.name}: {exc}"


def _load_locked(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return _valid_record(data), None
    except FileNotFoundError:
        return None, None
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return None, f"{_quarantine(path)} ({type(exc).__name__})"


def _records(root: Path) -> list[Path]:
    try:
        return sorted((root / "records").glob("DSK-*.json"))
    except OSError as exc:
        raise RuntimeError(f"cannot inspect desktop-guard ledger: {exc}") from exc


def _expire(path: Path, record: dict[str, Any], now: float) -> bool:
    if float(record["expires_at"]) > now:
        return False
    path.unlink(missing_ok=True)
    _audit(path.parent.parent, "expire", record)
    return True


def _pretool_output(message: str) -> dict[str, Any]:
    return {
        "systemMessage": message,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": message,
        },
    }


def _prompt_output(message: str) -> dict[str, Any]:
    return {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": message}}


def _request_message(record: dict[str, Any], state: str = "PENDING", health: str | None = None) -> str:
    suffix = f"\nGuard health: {health}." if health else ""
    recovery = "Only this action waits; safe work may continue. This approval does not override other independent guards."
    if record.get("operator_only"):
        recovery = (
            "This request lacks a stable initiating actor and can never automatically permit a tool retry. "
            f"An operator may inspect or cancel it with `~/.local/bin/desktop-guard show|cancel {record['request_id']}`. "
            + (f"For this stored Bash action, explicit CLI approval and `~/.local/bin/desktop-guard run {record['request_id']}` can recover it. " if record.get("tool_name") == "Bash" else "This non-shell tool cannot be recovered through this hook channel; restore hook identity and retry. ")
            + "Other independent guards remain unaffected."
        )
    return (
        "DESKTOP CONTROL APPROVAL REQUIRED\n"
        f"State: {state}\nRisk: {record['reason']}\nAction: {record['action']}\n\n"
        f"Reply exactly: YES {record['request_id']}\nor: NO {record['request_id']}\n\n"
        f"{recovery}"
        f"{suffix}"
    )


def _policy_decision(payload: dict[str, Any]) -> tuple[str | None, dict[str, Any]]:
    # Do not move this import to module scope: permits must survive policy failures.
    policy = importlib.import_module("policy")
    reason = policy.classify(payload)
    if reason is not None and not isinstance(reason, str):
        raise RuntimeError("policy.classify returned a non-string decision")
    bindings_fn = getattr(policy, "bindings", None)
    bindings = bindings_fn(payload) if callable(bindings_fn) else {}
    if not isinstance(bindings, dict):
        raise RuntimeError("policy.bindings returned a non-object")
    return reason, bindings


def _bound_action_is_current(record: dict[str, Any]) -> bool:
    """Verify optional bindings without importing policy during a permit retry."""
    bindings = record.get("bindings", {})
    if not isinstance(bindings, dict):
        return False
    scripts = bindings.get("scripts", {})
    if not isinstance(scripts, dict):
        return False
    for name, expected in scripts.items():
        if not isinstance(name, str) or not isinstance(expected, str):
            return False
        try:
            digest = hashlib.sha256(Path(name).read_bytes()).hexdigest()
        except OSError:
            return False
        if not secrets.compare_digest(digest, expected):
            return False
    processes = bindings.get("processes", [])
    if not isinstance(processes, list):
        return False
    if bindings.get("process_identity") is not None:
        processes = processes + [bindings["process_identity"]]
    return all(_process_is_current(process) for process in processes)


def _process_is_current(process: Any) -> bool:
    if not isinstance(process, dict):
        return False
    pid = process.get("pid")
    expected_start = process.get("start_time", process.get("starttime"))
    if not isinstance(pid, int) or expected_start is None:
        return False
    try:
        # /proc/<pid>/stat field 22 is starttime; UID is intentionally not evidence.
        tail = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8").rsplit(")", 1)[1].split()
        return secrets.compare_digest(str(tail[19]), str(expected_start))
    except (OSError, IndexError):
        return False


def _consume_permit(root: Path, payload: dict[str, Any], actor: dict[str, str], now: float) -> tuple[bool, str | None]:
    current = base_fingerprint(payload, actor)
    health: str | None = None
    for path in _records(root):
        with _locked(path):
            record, issue = _load_locked(path)
            health = health or issue
            if not record:
                continue
            if _expire(path, record, now):
                continue
            if record["actor"] != actor or record["base_fingerprint"] != current:
                continue
            if record["status"] == "approved" and not record.get("operator_only"):
                if not _bound_action_is_current(record):
                    path.unlink(missing_ok=True)
                    health = health or "revoked an approved request because its bound script or process changed"
                    _audit(root, "error", record, "bound action changed before consumption")
                    continue
                path.unlink(missing_ok=True)  # lock makes the permit one-use.
                _audit(root, "consume", record)
                return True, health
    return False, health


def _find_matching_request(root: Path, actor: dict[str, str], base: str, now: float) -> tuple[dict[str, Any] | None, str | None]:
    health: str | None = None
    for path in _records(root):
        with _locked(path):
            record, issue = _load_locked(path)
            health = health or issue
            if not record:
                continue
            if _expire(path, record, now):
                continue
            if record["actor"] == actor and record["base_fingerprint"] == base:
                return record, health
    return None, health


def _new_record(root: Path, payload: dict[str, Any], actor: dict[str, str], reason: str, bindings: dict[str, Any], now: float) -> dict[str, Any]:
    for _ in range(16):
        code = "DSK-" + secrets.token_hex(3).upper()
        path = _record_path(root, code)
        with _locked(path):
            if path.exists():
                continue
            base = base_fingerprint(payload, actor)
            record = {
                "request_id": code, "actor": actor, "base_fingerprint": base,
                "fingerprint": fingerprint(payload, actor, bindings), "bindings": bindings,
                "reason": reason, "action": describe(payload), "status": "pending",
                "operator_only": not automatic_permit_possible(actor),
                "tool_name": str(payload.get("tool_name") or ""),
                "tool_input": payload.get("tool_input"), "cwd": str(payload.get("cwd") or ""),
                "created_at": now, "expires_at": now + REQUEST_TTL_SECONDS,
            }
            _write_atomic(path, record)
            _audit(root, "request", record)
            return record
    raise RuntimeError("could not allocate a unique desktop approval code")


def _handle_pretool(payload: dict[str, Any], provider: str, root: Path) -> dict[str, Any] | None:
    actor = identity(payload, provider)
    now = time.time()
    current = base_fingerprint(payload, actor)
    # This lock covers only the same exact actor/action, avoiding duplicate
    # pending requests while leaving unrelated safe work and actions concurrent.
    with _locked(root / f".claim-{current}"):
        consumed, health = _consume_permit(root, payload, actor, now)
        if consumed:
            return None
        existing, existing_health = _find_matching_request(root, actor, current, now)
        health = health or existing_health
        if existing:
            state = "APPROVED—USE OPERATOR RECOVERY" if existing.get("operator_only") and existing["status"] == "approved" else ("APPROVED—RETRY THE EXACT ACTION" if existing["status"] == "approved" else "PENDING")
            return _pretool_output(_request_message(existing, state=state, health=health))

        try:
            reason, bindings = _policy_decision(payload)
        except Exception as exc:
            reason, bindings = f"the desktop guard could not classify this action ({type(exc).__name__}: {exc})", {}
            _audit(root, "error", note=f"policy classification failed: {type(exc).__name__}: {exc}")
        if not reason:
            return None
        record = _new_record(root, payload, actor, reason, bindings, now)
        return _pretool_output(_request_message(record, health=health))


def _known_safe_read(payload: dict[str, Any]) -> bool:
    return str(payload.get("tool_name") or "") in KNOWN_SAFE_READ_TOOLS


def _ledger_unavailable_pretool(payload: dict[str, Any], error: Exception) -> dict[str, Any] | None:
    """A broken ledger must not turn policy-verified safe work into a prompt."""
    try:
        reason, _ = _policy_decision(payload)
    except Exception as policy_error:
        return _pretool_output(
            f"DESKTOP GUARD ERROR: ledger unavailable ({type(error).__name__}: {error}) and this action "
            f"could not be independently classified ({type(policy_error).__name__}: {policy_error}). "
            "No desktop action was approved; restore the runtime ledger or use `~/.local/bin/desktop-guard status`."
        )
    if reason is None:
        return None
    return _pretool_output(
        f"DESKTOP CONTROL BLOCKED: {reason}. The approval ledger is unavailable ({type(error).__name__}: {error}), "
        "so no recoverable permit was created. Restore the runtime ledger, then retry this exact action."
    )


def _handle_prompt(payload: dict[str, Any], provider: str, root: Path) -> dict[str, Any] | None:
    session = str(payload.get("session_id") or "").strip()
    match = CODE_RE.fullmatch(str(payload.get("prompt") or ""))
    if not match:
        return _prompt_output("Desktop approvals are action-scoped: only the matching YES/NO code affects its request. Safe work may continue while a request is pending.")
    code = match.group(2).upper()
    path = _record_path(root, code)
    with _locked(path):
        record, issue = _load_locked(path)
        if not record:
            detail = f" Guard health: {issue}." if issue else ""
            return _prompt_output(f"Desktop approval {code} is unavailable, expired, or belongs to another session. No action was approved.{detail}")
        if not session:
            return _prompt_output(f"Desktop approval {code} was not processed: this confirmation has no session identity. No action was approved.")
        if record["actor"]["provider"] != provider or record["actor"]["session"] != session:
            return _prompt_output(f"Desktop approval {code} belongs to a different session. No action was approved.")
        if _expire(path, record, time.time()):
            return _prompt_output(f"Desktop approval {code} expired. Retry the exact action to create a new request.")
        if match.group(1).upper() == "NO":
            path.unlink(missing_ok=True)
            _audit(root, "cancel", record)
            return _prompt_output(f"Desktop action {code} was cancelled. Do not retry it or an equivalent route without a new request.")
        record["status"] = "approved"
        record["approved_at"] = time.time()
        record["expires_at"] = record["approved_at"] + PERMIT_TTL_SECONDS
        _write_atomic(path, record)
        _audit(root, "approve", record)
        if record.get("operator_only"):
            return _prompt_output(f"Desktop action {code} is approved only for explicit operator recovery. It cannot automatically permit a tool retry because stable actor identity is absent.")
        return _prompt_output(f"Desktop action {code} is approved for one exact retry within five minutes. Only the initiating actor can consume it; safe work may continue.")


def handle(payload: dict[str, Any], provider: str, root: Path | None = None) -> dict[str, Any] | None:
    """Handle one native hook payload, returning only provider-supported output."""
    try:
        event = payload.get("hook_event_name")
        if event == "PreToolUse":
            if _known_safe_read(payload):
                return None
            try:
                state_root = ensure_root(root)
            except Exception as error:
                return _ledger_unavailable_pretool(payload, error)
            return _handle_pretool(payload, provider, state_root)
        if event == "UserPromptSubmit":
            state_root = ensure_root(root)
            return _handle_prompt(payload, provider, state_root)
        return None
    except Exception as exc:
        message = f"DESKTOP GUARD ERROR: {type(exc).__name__}: {exc}. No desktop action was approved. Use `~/.local/bin/desktop-guard status` for recovery."
        return _prompt_output(message) if payload.get("hook_event_name") == "UserPromptSubmit" else _pretool_output(message)


def main(provider: str) -> None:
    """Hook stdio adapter.  The caller supplies its provider label."""
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            raise ValueError("hook payload is not an object")
        result = handle(payload, provider)
    except Exception as exc:
        message = f"DESKTOP GUARD ERROR: {type(exc).__name__}: {exc}. No desktop action was approved."
        result = _pretool_output(message)
    if result is not None:
        print(json.dumps(result, ensure_ascii=False))


def _lookup(root: Path, code: str) -> tuple[Path, dict[str, Any] | None, str | None]:
    path = _record_path(root, code.upper())
    with _locked(path):
        record, issue = _load_locked(path)
        return path, record, issue


def cli() -> None:
    """Local operator recovery helper; ``run`` executes one explicitly approved Bash record."""
    parser = argparse.ArgumentParser(description="Desktop guard approval ledger helper")
    parser.add_argument("--root", type=Path, help="override ledger root (for recovery/testing)")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    show = commands.add_parser("show"); show.add_argument("code")
    for name in ("approve", "cancel"):
        item = commands.add_parser(name); item.add_argument("code")
    run = commands.add_parser("run"); run.add_argument("code")
    args = parser.parse_args()
    try:
        root = ensure_root(args.root)
        if args.command == "status":
            items: list[dict[str, Any]] = []
            health: list[str] = []
            now = time.time()
            for path in _records(root):
                with _locked(path):
                    record, issue = _load_locked(path)
                    if issue: health.append(issue)
                    if record and not _expire(path, record, now): items.append(record)
            print(json.dumps({"root": str(root), "available": True, "records": items, "health": health}, ensure_ascii=False, indent=2))
            return
        path, record, issue = _lookup(root, args.code)
        if not record or _expire(path, record, time.time()):
            raise RuntimeError(issue or f"request {args.code.upper()} is unavailable or expired")
        if args.command == "show":
            print(json.dumps(record, ensure_ascii=False, indent=2)); return
        with _locked(path):
            record, issue = _load_locked(path)
            if not record or _expire(path, record, time.time()):
                raise RuntimeError(issue or f"request {args.code.upper()} is unavailable or expired")
            if args.command == "cancel":
                path.unlink(missing_ok=True)
                _audit(root, "cancel", record, "operator helper")
                print(f"Cancelled {record['request_id']}; no action was executed.")
                return
            if args.command == "approve":
                record["status"] = "approved"; record["approved_at"] = time.time(); record["expires_at"] = record["approved_at"] + PERMIT_TTL_SECONDS
                _write_atomic(path, record)
                _audit(root, "approve", record, "operator helper")
                print(f"Approved {record['request_id']} for one exact retry; no action was executed.")
                return
            if not record.get("operator_only"):
                raise RuntimeError("CLI run is reserved for an operator-only recovery request")
            if record.get("status") != "approved":
                raise RuntimeError("request must be explicitly approved before CLI run")
            command = record.get("tool_input", {}).get("command") if isinstance(record.get("tool_input"), dict) else None
            if record.get("tool_name") != "Bash" or not isinstance(command, str) or not command:
                raise RuntimeError("CLI run supports only a stored Bash command")
            if not _bound_action_is_current(record):
                path.unlink(missing_ok=True)
                _audit(root, "error", record, "bound action changed before operator run")
                raise RuntimeError("request was revoked because its bound script or process changed")
            cwd = record.get("cwd") or None
            path.unlink(missing_ok=True)  # Consume before executing; state is not execution proof.
            _audit(root, "consume", record, "operator helper run")
        print(f"Running exactly approved stored command for {record['request_id']}:\n{command}")
        result = subprocess.run(command, shell=True, executable="/bin/bash", cwd=cwd, check=False)
        print(f"Operator command exited with status {result.returncode}; ledger consumption is not proof that it succeeded.")
    except Exception as exc:
        print(f"Desktop guard ledger unavailable: {type(exc).__name__}: {exc}. No risky action was allowed.", file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    cli()
