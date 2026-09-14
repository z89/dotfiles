"""Shared desktop-takeover rules for the Claude Code and Codex gates.

Both agents run on this machine, both can reach the desktop the user is working
in, and both have a gate that denies desktop control until the user approves it
by code. Two copies of these rules would drift, and the half that drifted would
be the half that let something through. So the rules live here, once, and each
gate imports them and supplies only its own plumbing: state directory, locking,
hook output shape, event names.

What belongs here: what counts as desktop control, the request-code format, the
YES/NO grammar, the banner, and the fingerprint that pins an approval to one
exact call. What does not: anything agent-specific.

This module decides policy but performs nothing. It never runs a command, never
touches the desktop, and reads only `.desktop` files to learn which programs
open windows.
"""
import hashlib
import json
import os
import re
import secrets
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _cmdparse import invocations  # noqa: E402

RULES_VERSION = "2026-09-12"

CODE_RE = re.compile(r"DSK-[0-9A-F]{6}", re.IGNORECASE)
# `YES DSK-1A2B3C`, `y dsk-1a2b3c`, `DSK-1A2B3C approve`, with trailing words
# allowed. Requiring an exact whole-message match is how Codex's first version
# turned "yes DSK-4F21 go ahead" into another 10 minutes of blocked session.
ANSWER_RE = re.compile(
    r"^\s*(?:(?P<yes1>yes|y|approve|approved|ok|allow)|(?P<no1>no|n|deny|denied|cancel|stop))\b[\s:,-]*"
    r"(?P<code1>DSK-[0-9A-F]{6})|^\s*(?P<code2>DSK-[0-9A-F]{6})\b[\s:,-]*"
    r"(?:(?P<yes2>yes|y|approve|approved|ok|allow)|(?P<no2>no|n|deny|denied|cancel|stop))\b",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# What counts as taking over the desktop
# ---------------------------------------------------------------------------

INPUT_SYNTH = {
    "ydotool", "ydotoold", "xdotool", "wtype", "dotool", "xte", "evemu-play",
    "wlrctl", "cua-driver", "xnee", "cnee",
}
CAPTURE = {
    "grim", "grimblast", "hyprshot", "slurp", "satty", "wf-recorder",
    "wl-screenrec", "scrot", "maim", "import", "spectacle", "flameshot",
    "gnome-screenshot", "xwd", "wayfreeze", "screenshot", "obs", "obs-cmd",
    "wl-mirror",
}
LOCKERS = {
    "hyprlock", "swaylock", "swaylock-effects", "gtklock", "i3lock",
    "i3lock-color", "waylock", "physlock", "vlock", "xsecurelock",
    "xscreensaver-command",
}
SCREEN_STATE = {
    "hypridle", "swayidle", "hyprsunset", "hyprsunset-auto", "wlsunset",
    "gammastep", "redshift", "xset", "xsetroot",
}
APPEARANCE = {
    "swww", "swaybg", "hyprpaper", "wpaperd", "matugen", "wal", "wallust",
    "theme-apply", "theme-switch", "os3-theme", "font-switch", "palette-gen",
    "hyprpanel", "hyprpanel-launch", "hyprpanel-app", "ags", "eww", "waybar",
    "gjs", "dms-shell-patch", "dms-run-patched", "dms-shim", "workspace-switch",
    "app-relaunch", "focus-or-launch", "browser-open", "keybind-cheatsheet",
    "airpods-mic",
}
SHELL_UIS = {"dms", "qs", "quickshell"}
DMS_READ_VERBS = {
    "get", "list", "status", "info", "dump", "read", "show-config", "help",
}
WM_CONTROL = {"wmctrl", "riverctl", "i3-msg", "xprop"}
COMPOSITORS = {"Hyprland", "hyprland", "sway", "niri", "river", "weston"}
HYPR_MUTATING = {
    "dispatch", "keyword", "reload", "setcursor", "output", "switchxkblayout",
    "seterror", "setprop", "notify", "dismissnotify", "plugin", "kill",
    "setfloating", "movecursor",
}
HYPR_LUA_DRIVE = re.compile(
    r"\b(?:hl\.(?:dsp|dispatch|keyword|reload|notify|timer)|"
    r"(?:move|resize|focus|warp|setPosition|setSize|pin|swap|close|kill|"
    r"toggleFloating|setFullscreen)\s*[\(:])"
)
SWAY_READ = {
    "get_tree", "get_workspaces", "get_outputs", "get_inputs", "get_marks",
    "get_config", "get_seats", "get_bar_config", "get_binding_modes",
    "get_version",
}
DISPLAY = {"xrandr", "wlr-randr", "kanshi", "wdisplays", "ddcutil",
           "brightnessctl", "light", "chvt", "openvt", "deallocvt"}
XRANDR_WRITE = {
    "--output", "--mode", "--off", "--rate", "--primary", "--rotate",
    "--reflect", "--brightness", "--gamma", "--auto", "--dpi", "--fb",
    "--newmode", "--addmode", "--rmmode", "--delmode", "--setmonitor",
    "--delmonitor", "--scale", "--panning", "--pos", "--left-of",
    "--right-of", "--above", "--below", "--same-as", "-s",
}
PROCESS_KILL = {"kill", "pkill", "killall", "xkill", "skill"}
OPENERS = {
    # `open` is deliberately absent: it is a macOS command, it does not exist on
    # this machine, and as an ordinary English word it is the single likeliest
    # token to be mistaken for a command by any parser.
    "xdg-open", "gio", "gtk-launch", "dex", "kioclient", "kioclient5",
    "mimeopen", "exo-open", "gnome-open", "kde-open", "kde-open5",
}
NOTIFY = {"notify-send", "dunstify", "makoctl", "swaync-client", "swaync",
          "dunstctl"}
CLIPBOARD = {"wl-copy", "xclip", "xsel", "cliphist", "copyq", "clipman",
             "wl-clip-persist"}
AUDIO = {"pactl", "wpctl", "amixer", "pamixer", "playerctl", "mpc", "pw-cli",
         "pw-metadata", "pacmd"}
INPUT_CONFIG = {"setxkbmap", "xmodmap", "xkbcomp", "xinput", "xhost"}
PREFS = {"gsettings", "dconf", "kwriteconfig", "kwriteconfig5",
         "kwriteconfig6", "xfconf-query", "xdg-settings", "xdg-mime"}
DBUS = {"dbus-send", "gdbus", "qdbus", "qdbus6", "busctl", "dbus-monitor"}
POWER = {"shutdown", "reboot", "poweroff", "halt", "suspend", "hibernate",
         "systemd-sleep", "zzz", "ZZZ"}
DESKTOP_UNIT_WORDS = (
    "ags", "dms", "display-manager", "dunst", "eww", "gdm", "graphical",
    "greetd", "hypr", "kitty", "mako", "pipewire", "plasma", "portal",
    "quickshell", "sddm", "seatd", "sway", "swaync", "waybar", "wireplumber",
    "wayland", "window-manager", "xdg-desktop-portal", "xwayland",
)
SYSTEMCTL_SESSION = {"halt", "hibernate", "hybrid-sleep", "isolate", "kexec",
                     "poweroff", "reboot", "rescue", "suspend",
                     "suspend-then-hibernate", "emergency", "exit"}
SYSTEMCTL_UNIT_ACTIONS = {"start", "stop", "restart", "reload", "kill",
                          "try-restart", "reload-or-restart", "isolate"}
LOGINCTL_WRITE = {
    "activate", "kill-session", "kill-user", "lock-session", "lock-sessions",
    "terminate-session", "terminate-user", "unlock-session", "unlock-sessions",
    "suspend", "hibernate", "poweroff", "reboot", "halt",
}
QUERY_ONLY = {"--help", "-h", "--version", "-V", "help", "version",
              "--usage", "-?"}

# Names unambiguous enough to look for inside inline interpreter code.
# Deliberately excludes ordinary words like `kill` and `open`.
BLOB_NAMES = (
    "ydotool", "xdotool", "wtype", "dotool", "hyprctl", "swaymsg", "wmctrl",
    "quickshell", "pkill", "killall", "xkill", "xdg-open", "gtk-launch",
    "notify-send", "grim", "grimblast", "hyprshot", "slurp", "swww", "swaybg",
    "hyprpaper", "hyprlock", "swaylock", "loginctl", "wl-copy", "gsettings",
    "dconf", "playerctl", "brightnessctl", "pactl", "wpctl", "chvt", "xrandr",
    "wlr-randr", "matugen", "theme-apply", "workspace-switch", "cua-driver",
    "hyprpanel", "systemctl",
)
BLOB_RE = re.compile(r"(?<![\w-])(" + "|".join(BLOB_NAMES) + r")(?![\w-])")

# A desktop command name inside inline code (`python3 -c …`, a heredoc body)
# only matters if the code also shows intent to run something. Without this, a
# script that *writes about* a command - documentation, a test table, a regex -
# reads as one that runs it, which is how this gate first blocked its own README.
EXEC_INTENT_RE = re.compile(
    r"(subprocess|os\.system|os\.popen|os\.exec|os\.spawn|Popen|check_call|"
    r"check_output|getoutput|getstatusoutput|pty\.spawn|shell\s*=\s*True|"
    r"child_process|execSync|execFile|spawnSync|\bsystem\s*\(|\bexec\s*\(|"
    r"\bpopen\s*\(|\bqx\b|`)", re.I)

GUI_SCAN_ROOTS = (
    "/usr/share/applications",
    "/usr/local/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
)
GUI_NEVER = {
    "ash", "awk", "bash", "busybox", "cargo", "cat", "code", "dash", "docker",
    "env", "flatpak", "git", "go", "gpg", "grep", "java", "kubectl", "less",
    "make", "man", "node", "npm", "perl", "php", "pnpm", "python", "python2",
    "python3", "python3.11", "ruby", "sed", "sh", "snap", "ssh", "sudo",
    "systemd-run", "tmux", "wine", "xargs", "yarn", "zsh",
}

# Tools that exist only to drive a desktop: any use is a takeover.
DESKTOP_TOOL_RE = re.compile(
    r"(cua|computer[-_]?use|computer[-_]?control|desktop[-_]?control|"
    r"screen[-_]?control|remote[-_]?desktop|xdotool|hyprland|wayland|vnc)", re.I)
# Tools that drive a browser. Reading a page is ordinary work; raising a window,
# clicking and typing in one is not. Codex ships such a plugin, so the name
# matters here even though Claude Code currently has no equivalent.
BROWSER_TOOL_RE = re.compile(
    r"(browser|playwright|puppeteer|chrome|chromium|selenium|webdriver)", re.I)
DESKTOP_ACTION_RE = re.compile(
    r"(createBrowserTab|\.click\s*\(|\.setValue\s*\(|\.pressKey\s*\(|"
    r"\.typeText\s*\(|\.scroll\s*\(|\.selectText\s*\(|\.bringToFront\s*\(|"
    r"\.activate\s*\(|\.close\s*\(|\.goto\s*\(|\.navigate\s*\(|\.upload\s*\(|"
    r"\.moveMouse\s*\(|\.drag\s*\(|\.screenshot\s*\(|"
    r"performSecondaryAction|bring_to_front|type_text|press_key|move_mouse)", re.I)


def positionals(args, value_flags=()):
    """Non-flag arguments, skipping the values of flags that take one."""
    out, skip = [], False
    for token in args:
        if skip:
            skip = False
            continue
        if token in value_flags:
            skip = True
            continue
        if token.startswith("-"):
            continue
        out.append(token)
    return out


def gui_commands(cache_dir):
    """Basenames of installed graphical applications, cached by directory mtime.

    Only entries that open their own window count: `Terminal=true` desktop
    files (nvim, htop, ranger) are console programs and are left alone. The
    cache matters - without it this walks several hundred files on every single
    tool call, in front of every command the agent runs.
    """
    stamp = []
    for directory in GUI_SCAN_ROOTS:
        try:
            stamp.append(int(os.stat(directory).st_mtime))
        except OSError:
            stamp.append(0)
    key = ",".join(str(value) for value in stamp)
    cache = os.path.join(cache_dir, "gui-commands.json") if cache_dir else None
    if cache:
        try:
            with open(cache) as handle:
                data = json.load(handle)
            if data.get("key") == key and data.get("rules") == RULES_VERSION:
                return set(data.get("commands") or ())
        except Exception:
            pass

    commands = set()
    for directory in GUI_SCAN_ROOTS:
        try:
            names = os.listdir(directory)
        except OSError:
            continue
        for name in names:
            if not name.endswith(".desktop"):
                continue
            try:
                with open(os.path.join(directory, name), errors="replace") as handle:
                    text = handle.read()
            except OSError:
                continue
            if re.search(r"^Terminal\s*=\s*true", text, re.I | re.M):
                continue
            match = re.search(r"^Exec\s*=\s*(.+)$", text, re.M)
            if not match:
                continue
            found, _, _ = invocations(match.group(1))
            if found:
                commands.add(found[0][0])
    commands -= GUI_NEVER
    if cache:
        try:
            temporary = cache + ".tmp"
            with open(temporary, "w") as handle:
                json.dump({"key": key, "rules": RULES_VERSION,
                           "commands": sorted(commands)}, handle)
            os.replace(temporary, cache)
        except Exception:
            pass
    return commands


def judge(binary, args, cache_dir):
    """Reason this invocation reaches the user's desktop, or None."""
    if set(args) & QUERY_ONLY:
        return None
    words = positionals(args)

    if binary in INPUT_SYNTH:
        return "synthesises keyboard, pointer or window input"

    if binary == "hyprctl":
        flagless = positionals(args, value_flags={"-i", "--instance", "-r"})
        batch = None
        for index, token in enumerate(args):
            if token in ("--batch", "-b") and index + 1 < len(args):
                batch = args[index + 1]
        if batch is not None:
            for piece in batch.split(";"):
                first = piece.strip().split(" ")[0].lstrip("/")
                if first in HYPR_MUTATING:
                    return "drives Hyprland (batched window, workspace, output or config change)"
            return None
        sub = flagless[0] if flagless else ""
        if sub in ("eval", "repl"):
            return ("drives Hyprland through its Lua interface"
                    if HYPR_LUA_DRIVE.search(" ".join(args)) else None)
        if sub in HYPR_MUTATING:
            return "drives Hyprland (windows, workspaces, outputs, cursor or live config)"
        return None

    if binary == "hyprpm":
        return None if (words and words[0] == "list") else "loads, reloads or disables Hyprland plugins"

    if binary == "swaymsg":
        return None if (words and words[0] in SWAY_READ) else "drives the window manager"

    if binary == "xprop":
        return "changes a window property" if "-set" in args else None

    if binary in WM_CONTROL:
        return "drives the window manager"

    if binary in COMPOSITORS:
        return "starts a compositor session"

    if binary in SHELL_UIS:
        if binary == "dms":
            if words[:2] == ["ipc", "call"]:
                target = words[2].lower() if len(words) > 2 else ""
                verb = words[3].lower() if len(words) > 3 else ""
                if verb in DMS_READ_VERBS or target in DMS_READ_VERBS:
                    return None
                return "changes a visible desktop-shell surface (DMS ipc call)"
            if words and words[0] == "ipc":
                return None
            return "starts, stops or reloads the desktop shell"
        return "starts, stops or reloads the desktop shell"

    if binary in LOCKERS:
        return "locks or blanks the screen the user is working on"

    if binary in SCREEN_STATE:
        if binary == "xset" and not args:
            return None
        return "changes idle, blanking or screen-colour behaviour"

    if binary in CAPTURE:
        return "captures, records or freezes the visible screen"

    if binary in APPEARANCE:
        return "repaints the live desktop (wallpaper, colours, fonts, bar or shell)"

    if binary in DISPLAY:
        if binary == "xrandr":
            return ("reconfigures the display"
                    if any(token in XRANDR_WRITE for token in args) else None)
        if binary == "wlr-randr":
            return None if not args or "--json" in args else "reconfigures the display"
        if binary == "ddcutil":
            return ("changes monitor settings"
                    if words and words[0] in ("setvcp", "setvcpvalue") else None)
        if binary == "brightnessctl":
            return ("changes screen brightness"
                    if not words or words[0] in ("s", "set") else None)
        if binary == "light":
            return ("changes screen brightness"
                    if any(token.startswith(("-S", "-A", "-U")) for token in args) else None)
        return "switches the active virtual terminal"

    if binary in PROCESS_KILL:
        if binary == "pkill" and "-0" in args:
            return None
        if binary in ("kill", "skill"):
            if "-0" in args or "-l" in args:
                return None
            # A kill aimed at literal pids is almost always an agent ending a
            # daemon it started itself. A kill aimed at a *name* - pkill,
            # killall, or `kill $(pgrep firefox)` - is the one that closes the
            # user's windows, so anything non-numeric still stops the session.
            targets = [token for token in args if not token.startswith("-")]
            if targets and all(token.isdigit() for token in targets):
                return None
        return "kills or signals a running process, which may be the user's application"

    if binary in OPENERS:
        if binary == "gio" and not (words and words[0] == "open"):
            return None
        if binary in ("kioclient", "kioclient5") and not (words and words[0].startswith("exec")):
            return None
        return "opens a window on the user's screen"

    if binary in ("flatpak", "snap") and words and words[0] == "run":
        return "launches a graphical application"

    if binary == "uwsm" and words and words[0] in ("app", "start", "stop", "finalize"):
        return "launches or ends something in the graphical session"

    if binary in NOTIFY:
        if binary in ("makoctl", "dunstctl") and words and words[0] in ("list", "count", "history"):
            return None
        return "puts a notification on the user's screen"

    if binary in CLIPBOARD:
        if binary == "xclip" and not any(token.startswith("-i") for token in args):
            return None
        if binary == "xsel" and not any(
                token in ("-i", "--input", "-a", "--append", "-c", "--clear") for token in args):
            return None
        if binary == "cliphist" and not (
                words and words[0] in ("store", "wipe", "delete", "delete-query")):
            return None
        return "overwrites or clears the clipboard the user is using"

    if binary in AUDIO:
        if binary in ("pactl", "wpctl", "pacmd") and words and words[0].startswith("set"):
            return "changes audio devices, volume or mute state"
        if binary == "amixer" and words and words[0] in ("set", "sset"):
            return "changes audio volume or mute state"
        if binary == "pamixer" and any(
                token.startswith(("--set", "--allow", "-i", "-d", "-m", "-u", "-t")) for token in args):
            return "changes audio volume or mute state"
        if binary == "playerctl" and words and words[0] in (
                "play", "pause", "play-pause", "stop", "next", "previous",
                "position", "volume", "loop", "shuffle", "open"):
            return "controls whatever the user is playing"
        if binary == "mpc" and words and words[0] in (
                "play", "pause", "toggle", "stop", "next", "prev", "volume", "seek"):
            return "controls whatever the user is playing"
        if binary in ("pw-cli", "pw-metadata") and words and words[0] in (
                "set-param", "s", "create-node", "destroy", "d"):
            return "changes the live audio graph"
        return None

    if binary in INPUT_CONFIG:
        if binary == "xinput" and words and words[0] in ("list", "list-props", "query-state"):
            return None
        return "changes keyboard or pointer configuration"

    if binary in PREFS:
        if binary == "gsettings" and not (
                words and words[0] in ("set", "reset", "reset-recursively")):
            return None
        if binary == "dconf" and not (words and words[0] in ("write", "reset", "load")):
            return None
        if binary == "xfconf-query" and not any(
                token in ("-s", "--set", "-r", "--reset") for token in args):
            return None
        if binary == "xdg-settings" and not (words and words[0] == "set"):
            return None
        if binary == "xdg-mime" and not (words and words[0] == "default"):
            return None
        return "rewrites live desktop preferences (theme, defaults, panel settings)"

    if binary in DBUS:
        if binary == "dbus-monitor":
            return None
        if binary == "gdbus" and words and words[0] in ("introspect", "monitor", "wait"):
            return None
        if binary == "busctl" and (not words or words[0] in (
                "list", "status", "tree", "introspect", "monitor", "capture", "get-property")):
            return None
        if binary in ("qdbus", "qdbus6") and len(words) < 3:
            return None
        return "calls a desktop or session bus interface that can act on the session"

    if binary in POWER:
        return "powers off, reboots or suspends the machine"

    if binary == "systemctl":
        lowered = [token.lower() for token in args]
        flagless = [token for token in lowered if not token.startswith("-")]
        verb = flagless[0] if flagless else ""
        if verb in SYSTEMCTL_SESSION:
            return "powers off, suspends or replaces the running session"
        if verb in SYSTEMCTL_UNIT_ACTIONS:
            units = " ".join(flagless[1:])
            if any(word in units for word in DESKTOP_UNIT_WORDS):
                return "starts, stops or restarts a desktop, compositor, bar or session service"
        return None

    if binary == "loginctl":
        return ("locks, activates or terminates a login session"
                if words and words[0] in LOGINCTL_WRITE else None)

    if binary == "systemd-inhibit":
        return "changes idle, lid or power inhibition"

    if binary not in GUI_NEVER and binary in gui_commands(cache_dir):
        return "launches an installed graphical application"
    return None


def classify_bash(command, cache_dir):
    found, blobs, parsed_cleanly = invocations(command)
    for binary, args in found:
        reason = judge(binary, args, cache_dir)
        if reason:
            return reason
    for blob in blobs:
        match = BLOB_RE.search(blob)
        if match and EXEC_INTENT_RE.search(blob):
            return f"runs a desktop-control command ({match.group(1)}) from inside inline code"
    if not parsed_cleanly:
        match = BLOB_RE.search(command)
        if match:
            return f"looks like it runs a desktop-control command ({match.group(1)})"
    return None


def flatten(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return "\n".join(flatten(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return "\n".join(flatten(item) for item in value)
    return ""


def classify(tool_name, tool_input, cache_dir=None):
    """Reason this tool call reaches the user's desktop, or None.

    `tool_name` is whatever the host calls it: Bash, shell, exec, an MCP name,
    a plugin tool. Shell-shaped tools are parsed; everything else is matched on
    name and payload.
    """
    tool_name = tool_name or ""
    # Writing a file is explicitly unprompted work, and a file's *contents* are
    # never a command. Without this, writing a document about desktop control
    # reads as performing it - which is exactly what happened while writing the
    # Codex half of this gate.
    if tool_name in FILE_TOOLS:
        return None
    if tool_name in ("Bash", "BashOutput", "shell", "exec", "local_shell",
                     "container.exec"):
        if isinstance(tool_input, dict):
            command = tool_input.get("command") or tool_input.get("cmd") or ""
            if isinstance(command, (list, tuple)):
                command = " ".join(str(part) for part in command)
        else:
            command = flatten(tool_input)
        return classify_bash(command, cache_dir) if command else None

    payload = flatten(tool_input)
    if DESKTOP_TOOL_RE.search(tool_name):
        if DESKTOP_ACTION_RE.search(payload) or not payload:
            return "drives the desktop through a computer-control tool"
        return "uses a desktop-control tool"
    if BROWSER_TOOL_RE.search(tool_name) and DESKTOP_ACTION_RE.search(payload):
        return "raises, clicks or types in a visible browser window"
    if tool_name.startswith("mcp__") and DESKTOP_ACTION_RE.search(payload):
        return "drives a visible application through an MCP tool"
    if DESKTOP_TOOL_RE.search(payload) and DESKTOP_ACTION_RE.search(payload):
        return "drives the desktop through a tool payload"
    return None


# ---------------------------------------------------------------------------
# Request identity and the user-facing banner
# ---------------------------------------------------------------------------

def new_code():
    return "DSK-" + secrets.token_hex(3).upper()


def parse_answer(prompt):
    """('yes'|'no', 'DSK-XXXXXX') if the message answers a request, else None."""
    match = ANSWER_RE.search(prompt or "")
    if not match:
        return None
    code = match.group("code1") or match.group("code2")
    decision = "no" if (match.group("no1") or match.group("no2")) else "yes"
    return decision, code.upper()


def fingerprint(payload):
    """Pin an approval to one exact call: same tool, same input, same cwd."""
    material = {
        "tool_name": payload.get("tool_name", ""),
        "tool_input": payload.get("tool_input"),
        "cwd": payload.get("cwd", ""),
    }
    encoded = json.dumps(material, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def summarise(payload):
    tool = str(payload.get("tool_name") or "tool")
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, dict) and tool_input.get("command"):
        detail = str(tool_input.get("command"))
    else:
        detail = flatten(tool_input)
    detail = " ".join(detail.split())
    if len(detail) > 300:
        detail = detail[:297] + "..."
    return f"{tool}: {detail}" if detail else tool


def banner(code, reason, action, headline, footer, agent=None):
    width = 68
    bar = "═" * width
    title = "🚨  DESKTOP CONTROL - APPROVAL REQUIRED  🚨"
    lines = []
    fields = [("What", reason), ("Action", action)]
    if agent:
        fields.insert(0, ("Agent", agent))
    for label, text in fields:
        line = f"{label}:".ljust(9) + str(text)
        while len(line) > width:
            cut = line.rfind(" ", 0, width)
            cut = cut if cut > 20 else width
            lines.append(line[:cut])
            line = " " * 9 + line[cut:].lstrip()
        lines.append(line)
    return (
        f"\n╔{bar}╗\n"
        f"║{title.center(width - 2)}║\n"
        f"╚{bar}╝\n"
        f"{headline}\n\n"
        + "\n".join(lines) +
        f"\n\n  ►  Reply  YES {code}   to allow this one action, once\n"
        f"  ►  Reply  NO {code}    to refuse it\n\n"
        f"{footer}\n"
    )


def audit(agent, line):
    """Append to the one log both agents share.

    Two agents can reach this desktop. One log means one place to answer "what
    tried to touch my screen, and did I say yes?" - per-agent logs would need
    interleaving by hand at exactly the moment something has gone wrong.
    """
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    directory = os.path.join(base, "agent-guards")
    try:
        os.makedirs(directory, mode=0o700, exist_ok=True)
        with open(os.path.join(directory, "desktop-requests.log"), "a") as handle:
            handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {agent} {line}\n")
    except OSError:
        pass


AGENT_RULES = (
    "STOP. Do not run any other tool call - every tool in this session is "
    "blocked until the user answers. Do not retry, reword, split, wrap or "
    "substitute this action, and do not look for another way to produce the "
    "same effect. Show the user the banner above verbatim, say in one line what "
    "you wanted to do and why, then wait for their reply."
)
