#!/usr/bin/env python3
"""Ask before taking over the pointer, keyboard, compositor or the visible screen.

Deliberately narrow. Ordinary work must never prompt: file edits, builds, tests,
packages, sudo, systemd, mounts, boot config, firewalls, deletion, version control.
The user runs --dangerously-skip-permissions on purpose and only wants a prompt for
the one class of action that interrupts whoever is at the keyboard.

It inspects the *command being run*, never the text a command is handling, so a
message argument or a grep pattern containing one of these words stays silent.
"""
import json
import shlex
import sys

# argv[0] is enough: synthesising input is the whole point of these.
INPUT_SYNTH = {"ydotool", "ydotoold", "xdotool", "wtype", "dotool", "xte", "evemu-play"}

# hyprctl subcommands that move the cursor, windows, workspaces or the live config.
HYPR_TAKEOVER = {
    "dispatch", "keyword", "reload", "setcursor", "output", "switchxkblayout",
    "seterror", "setprop", "notify", "dismissnotify", "plugin",
}
# `hyprctl eval`/`repl` run Lua. Only flag it when the Lua actually drives things;
# using it as a calculator or to read state is not a takeover.
HYPR_LUA_DRIVE = ("hl.dsp", "hl.dispatch", "hl.keyword", "hl.reload")

# Other compositors / window managers, same idea.
WM_CTL = {"wmctrl", "i3-msg"}
WM_READONLY = {
    "get_tree", "get_workspaces", "get_outputs", "get_inputs", "get_marks",
    "get_config", "get_seats", "get_bar_config", "get_binding_modes", "get_version",
}

# dms verbs that put something on screen or repaint it. `plugins enable` stays free.
DMS_SURFACE_VERBS = {"open", "toggle", "show", "reveal", "close", "hide", "lock", "unlock"}
DMS_SURFACE_TARGETS = {"theme", "wallpaper", "night", "profile", "dark", "light"}

# Wrappers to look through to find the real command.
WRAPPERS = {"sudo", "doas", "env", "command", "nohup", "setsid", "stdbuf",
            "nice", "ionice", "time", "exec"}
# Shell keywords sit where a command name would, so step over them too.
KEYWORDS = {"do", "then", "else", "elif", "while", "until", "if", "for", "select",
            "function", "!", "coproc"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}


def segments(cmd):
    """Split on shell operators, honouring quotes, so each piece starts with a command."""
    out, buf, quote, i = [], "", None, 0
    while i < len(cmd):
        c = cmd[i]
        if quote:
            buf += c
            if c == quote:
                quote = None
            elif c == "\\" and i + 1 < len(cmd):
                i += 1
                buf += cmd[i]
        elif c in "\"'":
            quote = c
            buf += c
        elif c in ";\n&|":
            out.append(buf)
            buf = ""
            while i + 1 < len(cmd) and cmd[i + 1] in ";&|":
                i += 1
        elif c in "(){}":
            out.append(buf)
            buf = ""
        else:
            buf += c
        i += 1
    out.append(buf)
    return [s.strip() for s in out if s.strip()]


def tokens(seg):
    try:
        return shlex.split(seg)
    except ValueError:
        return seg.split()


def unwrap(argv):
    """Drop sudo/env/VAR=x prefixes to reach the actual command."""
    while argv:
        head = argv[0].rsplit("/", 1)[-1]
        if head in KEYWORDS:
            argv = argv[1:]
        elif "=" in head and not head.startswith("-"):
            argv = argv[1:]
        elif head in WRAPPERS:
            argv = argv[1:]
            while argv and argv[0].startswith("-"):
                argv = argv[1:]
        else:
            break
    return argv


def verdict(seg, depth=0):
    argv = unwrap(tokens(seg))
    if not argv:
        return None
    prog = argv[0].rsplit("/", 1)[-1]
    rest = argv[1:]

    if prog in INPUT_SYNTH:
        return "synthesises mouse or keyboard input"

    if prog == "hyprctl":
        words = [a for a in rest if not a.startswith("-")]
        sub = words[0] if words else ""
        if sub in ("eval", "repl"):
            lua = " ".join(rest)
            return "drives the compositor through Lua" if any(k in lua for k in HYPR_LUA_DRIVE) else None
        if sub in HYPR_TAKEOVER:
            return "drives the compositor (cursor, windows, workspaces, output or live config)"
        return None

    if prog == "swaymsg":
        words = [a for a in rest if not a.startswith("-")]
        return None if words and words[0] in WM_READONLY else "drives the window manager"

    if prog in WM_CTL:
        return "drives the window manager"

    if prog == "dms" and len(rest) >= 3 and rest[0] == "ipc" and rest[1] == "call":
        target = rest[2]
        verb = rest[3] if len(rest) > 3 else ""
        if target in DMS_SURFACE_TARGETS or verb in DMS_SURFACE_VERBS:
            return "changes what is on the bar or shell surface"
        return None

    if prog == "slurp":
        return "takes over the screen with a region selector"

    if prog in ("xdg-open", "gio", "gnome-open", "kde-open", "exo-open"):
        if prog == "gio" and not (rest and rest[0] == "open"):
            return None
        return "opens a window on the user's current screen"

    if prog == "xrandr" and any(a in ("--output", "--mode", "--off", "--rate", "--primary") for a in rest):
        return "reconfigures the display"

    # `bash -c "..."`: look inside. Never at `sh -n file`, which only syntax-checks.
    if prog in SHELLS and depth < 2:
        for i, a in enumerate(rest):
            if a == "-c" and i + 1 < len(rest):
                for s in segments(rest[i + 1]):
                    found = verdict(s, depth + 1)
                    if found:
                        return found
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    cmd = (payload.get("tool_input") or {}).get("command") or ""
    for seg in segments(cmd):
        reason = verdict(seg)
        if reason:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": (
                    "This command " + reason + ". The user is working in other workspaces and "
                    "has asked to be told, and to agree, immediately before anything takes over "
                    "the pointer, keyboard, workspaces or the visible screen. Approve only if "
                    "that was asked and agreed just now."),
            }}))
            sys.exit(0)
    sys.exit(0)


if __name__ == "__main__":
    main()
