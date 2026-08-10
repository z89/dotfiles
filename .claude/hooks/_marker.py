"""Session markers for the commit gate.

`require-commit-skill` needs to know whether the `/commit` skill has been loaded
in the session that is asking to run a git command, and `mark-commit-skill` sets
that flag. Both need to agree on where the flag lives, so the path is defined
once, here.

Markers live under XDG_RUNTIME_DIR (a per-user tmpfs, mode 0700, wiped on
logout) rather than in /tmp. /tmp is world-writable: any process on the machine
could have forged a marker there and unlocked the gate for a session it had
nothing to do with. This is a workflow gate rather than a security boundary, but
a gate that anything can open is not worth having.

Markers expire. The gate exists so the model has the commit rules in context;
a session that loaded them two days ago has almost certainly had that context
compacted away since, and re-arming costs one `/commit`.
"""
import os
import time

TTL_SECONDS = 8 * 60 * 60
SWEEP_AFTER_SECONDS = 24 * 60 * 60


def _directory():
    root = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    path = os.path.join(root, "claude-guards")
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def path_for(session_id):
    safe = "".join(c if (c.isalnum() or c in "-_") else "_" for c in session_id)
    return os.path.join(_directory(), "commit-skill." + safe)


def arm(session_id):
    marker = path_for(session_id)
    with open(marker, "w") as handle:
        handle.write(str(int(time.time())))
    os.chmod(marker, 0o600)


def state(session_id):
    """Return ('armed', age) | ('expired', age) | ('absent', None)."""
    marker = path_for(session_id)
    try:
        age = time.time() - os.stat(marker).st_mtime
    except OSError:
        return "absent", None
    if age > TTL_SECONDS:
        return "expired", age
    return "armed", age


def sweep():
    """Delete markers old enough that no live session could still want them."""
    try:
        directory = _directory()
        cutoff = time.time() - SWEEP_AFTER_SECONDS
        for name in os.listdir(directory):
            if not name.startswith("commit-skill."):
                continue
            full = os.path.join(directory, name)
            try:
                if os.stat(full).st_mtime < cutoff:
                    os.unlink(full)
            except OSError:
                pass
    except OSError:
        pass
