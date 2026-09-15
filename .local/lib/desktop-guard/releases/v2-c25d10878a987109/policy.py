"""Pure policy for the candidate desktop guard.

The shell decoder covers direct commands, common wrappers, substitutions and
shell-consuming heredocs.  It deliberately does not inspect arbitrary script
files or broad text inside ``functions.exec``: downstream canonical tool hooks
must classify those nested calls.  ``bindings`` hashes only directly invoked
script paths; an unknown script's later behaviour is outside this boundary.
"""
from __future__ import annotations

import ast
import hashlib
import os
import re
import shutil
from functools import lru_cache

from shellparse import decode, direct_program_paths

HOME = os.path.expanduser("~")
HYPR_MAIN = {os.path.join(HOME, ".config/hypr/hyprland.lua"), os.path.join(HOME, ".config/hypr/hyprland.conf")}
DEFERRED_HYPR = {os.path.join(HOME, ".config/hypr", name) for name in ("local.lua", "carry.lua", "borders.lua", "dms/colors.lua")}
DMS_SETTINGS = {
    os.path.join(HOME, ".config/hyprpanel/config.json"),
    os.path.join(HOME, ".config/DankMaterialShell/settings.json"),
    os.path.join(HOME, ".config/quickshell/settings.json"),
}
SHELL_TOOLS = {"bash", "shell", "exec", "exec_command", "container.exec", "local_shell", "terminal"}
FILE_TOOLS = {"write", "edit", "apply_patch", "functions.apply_patch"}
INPUT = {"ydotool", "xdotool", "wtype", "dotool", "wlrctl", "cua-driver"}
OPENERS = {"xdg-open", "gtk-launch", "gio", "kioclient", "gnome-open", "flatpak", "uwsm"}
KILL = {"kill", "skill", "pkill", "killall", "xkill"}
DESKTOP_UNITS = ("hypr", "waybar", "quickshell", "dms", "mako", "dunst", "portal", "pipewire", "wireplumber", "sway", "gdm", "greetd", "sddm", "graphical")
INLINE_NAMES = {"hyprctl", "swaymsg", "ydotool", "xdotool", "wtype", "xdg-open", "systemctl", "notify-send", "wl-copy", "gsettings", "pactl", "wpctl", "brightnessctl", "swww", "hyprpaper"}
GUI_NEVER = {"bash", "sh", "zsh", "python", "python3", "node", "gjs", "java", "env", "sudo", "systemd-run", "xargs", "git", "make", "cargo", "npm", "true", "false", "claude", "codex"}
XRANDR_MUTATING = {"--mode", "--off", "--rate", "--primary", "--rotate", "--reflect", "--brightness", "--gamma", "--auto", "--dpi", "--fb", "--newmode", "--addmode", "--rmmode", "--delmode", "--scale", "--panning", "--pos", "--left-of", "--right-of", "--above", "--below", "--same-as", "-s"}
WLR_RANDR_MUTATING = {"--output", "--on", "--off", "--mode", "--pos", "--scale", "--transform"}


def _flatten(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return "\n".join(_flatten(item) for item in value.values())
    if isinstance(value, (list, tuple)):
        return "\n".join(_flatten(item) for item in value)
    return ""


def _command(payload):
    data = payload.get("tool_input") or {}
    if isinstance(data, dict):
        value = data.get("command", data.get("cmd", ""))
    else:
        value = data
    return " ".join(map(str, value)) if isinstance(value, (list, tuple)) else str(value or "")


def _words(args):
    return [arg.lower() for arg in args if not arg.startswith("-")]


@lru_cache(maxsize=1)
def _gui_programs():
    """Installed GUI launcher commands; terminal launchers are excluded."""
    programs = {"kitty", "foot", "alacritty", "firefox", "nautilus", "gnome-calculator"}
    for directory in ("/usr/share/applications", "/usr/local/share/applications", os.path.join(HOME, ".local/share/applications")):
        try:
            names = os.listdir(directory)
        except OSError:
            continue
        for name in names:
            if not name.endswith(".desktop"):
                continue
            try:
                with open(os.path.join(directory, name), encoding="utf-8", errors="replace") as handle:
                    entry = handle.read()
            except OSError:
                continue
            if re.search(r"^Terminal\s*=\s*true\s*$", entry, re.I | re.M):
                continue
            for match in re.finditer(r"^Exec\s*=\s*(.+)$", entry, re.M):
                # Decode executable positions, including env wrappers. Launcher
                # arguments such as focus-or-launch's app ID are not programs.
                programs.update(binary for binary, _ in decode(match.group(1))[0])
    return frozenset(programs - GUI_NEVER)


def _judge(binary, args, payload):
    words = _words(args)
    if binary in {"claude", "codex"}:
        if "--handle-uri" in args or words[:2] == ["auth", "login"] or (words[:1] == ["login"] and words[:2] != ["login", "status"]) or (binary == "codex" and words[:1] == ["app"]):
            return "opens a provider desktop or browser authentication surface"
        return None
    if binary == "desktop-guard" and words[:1] and words[0] in {"approve", "run", "rollback"}:
        return "uses an operator-only approval or guard recovery command"
    if binary in INPUT:
        return "synthesises keyboard, pointer or window input"
    if binary == "hyprctl":
        flagless, index = [], 0
        while index < len(args):
            if args[index] in {"-i", "--instance", "-r"}:
                index += 2
            elif args[index].startswith("-"):
                index += 1
            else:
                flagless.append(args[index]); index += 1
        first = flagless[0].lower() if flagless else ""
        if first in {"eval", "repl"}:
            lua = " ".join(flagless[1:])
            # Only a literal arithmetic expression is a proven query.  A
            # ``return`` expression can call os.execute or any loaded module.
            if first == "eval" and re.fullmatch(r"\s*return\s+[0-9\s+*/%().-]+\s*", lua):
                return None
            return "changes Hyprland through its live Lua interface"
        if first in {"dispatch", "keyword", "reload", "setcursor", "output", "switchxkblayout", "notify", "plugin", "kill", "setprop"}:
            return "changes Hyprland windows, workspaces, outputs or live configuration"
        if "--batch" in args or "-b" in args:
            batch_flag = "--batch" if "--batch" in args else "-b"
            batch = args[args.index(batch_flag) + 1] if args.index(batch_flag) + 1 < len(args) else ""
            if re.search(r"\b(dispatch|keyword|reload|output|kill|setprop|setcursor|switchxkblayout|notify|plugin)\b", batch):
                return "changes Hyprland through a batch command"
        return None
    if binary == "hyprpm":
        return None if words[:1] == ["list"] else "loads, reloads or disables Hyprland plugins"
    if binary == "swaymsg":
        return None if words[:1] and words[0].startswith("get_") else "drives the window manager"
    if binary in {"wmctrl", "riverctl", "i3-msg"}:
        return "drives the window manager"
    if binary == "tmux":
        actions = {"kill-server", "kill-session", "kill-window", "kill-pane", "killw", "killp",
                   "send-keys", "send", "send-prefix", "switch-client", "switchc", "attach-session",
                   "attach", "attach-session", "select-window", "select-pane", "detach-client"}
        if any(word in actions for word in words):
            return "controls or terminates a terminal session that may contain other work"
    if binary == "zellij" and words[:1] and words[0] in {
        "action", "attach", "kill-session", "kill-all-sessions", "delete-session", "delete-all-sessions",
    }:
        return "controls or terminates terminal sessions that may contain other work"
    if binary in {"hyprlock", "swaylock", "i3lock"}:
        return "locks the screen the user is working on"
    if binary == "loginctl":
        return "locks, activates or terminates the active session" if words[:1] and words[0] in {"activate", "lock-session", "lock-sessions", "terminate-session", "terminate-user", "kill-session", "kill-user", "suspend", "reboot", "poweroff"} else None
    if binary in {"slurp", "grimblast", "wf-recorder", "wayfreeze", "satty"}:
        return None if "--help" in args else "captures, records, overlays or freezes the visible screen"
    if binary == "grim":
        return "captures the visible screen through a selector or clipboard" if any(flag in args for flag in {"-g", "--geometry", "-"}) else None
    if binary in {"hypridle", "hyprsunset", "swayidle", "wlsunset"}:
        return "changes idle, blanking or screen-colour behaviour"
    if binary in {"dms", "qs", "quickshell", "waybar", "ags", "eww", "hyprpanel", "swww", "hyprpaper", "matugen", "theme-apply", "workspace-switch"}:
        if binary == "dms" and words[:3] == ["ipc", "call", "settings"] and len(words) > 3 and words[3] in {"get", "list", "status", "info"}:
            return None
        return "starts or changes a visible desktop shell, panel or appearance"
    if binary in OPENERS:
        if binary == "gio" and words[:1] != ["open"]:
            return None
        if binary == "flatpak" and words[:1] != ["run"]:
            return None
        return "opens a visible application or window"
    if binary in KILL:
        if binary in {"kill", "skill"} and ("-0" in args or "-l" in args):
            # Probe/list mode is harmless only when it is not mixed with a
            # second signal selector such as ``-9`` or ``-TERM``.
            if not any(arg.startswith("-") and arg not in {"-0", "-l"} for arg in args):
                return None
        return "signals a process without a proven tool-owned handle"
    if binary in {"systemctl", "systemd-run"}:
        action = next((word for word in words if word in {"start", "stop", "restart", "reload", "try-restart", "reload-or-restart", "kill", "suspend", "reboot", "poweroff"}), "")
        if action in {"suspend", "reboot", "poweroff"}:
            return "changes machine power or the active session"
        if action and any(unit in " ".join(words) for unit in DESKTOP_UNITS):
            return "starts, stops or reloads a desktop session service"
        return None
    if binary in {"shutdown", "reboot", "poweroff", "suspend", "hibernate", "chvt", "openvt"}:
        return "changes machine power or the active session"
    if binary in {"xrandr", "wlr-randr", "brightnessctl"}:
        if binary == "xrandr" and not any(flag in args for flag in XRANDR_MUTATING) and (not args or "--query" in args or "--current" in args or "--listmonitors" in args):
            return None
        if binary == "wlr-randr" and not any(flag in args for flag in WLR_RANDR_MUTATING) and (not args or "--json" in args):
            return None
        if binary == "brightnessctl" and words[:1] == ["get"]:
            return None
        return "changes display layout or brightness"
    if binary in {"wl-copy", "xclip", "xsel", "cliphist"}:
        # xclip reads stdin (and therefore writes the selected clipboard) by
        # default.  Only its explicit output modes are passive.
        if binary == "xclip" and any(flag in args for flag in {"-o", "-out", "--out", "--output"}):
            return None
        return "replaces or clears the shared clipboard"
    if binary in {"notify-send", "dunstify"}:
        return "shows a notification on the user's screen"
    if binary in {"gsettings", "dconf"}:
        if words[:1] in (["set"], ["reset"], ["write"], ["load"]):
            return "changes live desktop preferences"
        return None
    if binary in {"pactl", "wpctl", "amixer", "playerctl"}:
        if any(word.startswith(("set", "mute", "play", "pause", "next", "previous")) for word in words):
            return "changes shared audio state or playback"
    if binary in {"setxkbmap", "xmodmap", "xkbcomp", "xinput", "xhost"}:
        if binary == "xinput" and words[:1] and words[0] in {"list", "list-props", "query-state"}:
            return None
        return "changes keyboard or pointer configuration"
    if binary in {"gdbus", "dbus-send", "qdbus", "qdbus6", "busctl"}:
        if binary == "busctl" and words[:1] and words[0] in {"list", "status", "tree", "introspect", "monitor", "get-property"}:
            return None
        if binary == "gdbus" and words[:1] and words[0] in {"introspect", "monitor", "wait"}:
            return None
        return "calls a session bus interface that can change the desktop"
    if binary in _gui_programs():
        return None if any(flag in args for flag in {"--help", "--version", "-h", "-V", "--headless"}) else "launches an installed graphical application"
    return None


def _literal_command(node):
    if not node.args:
        return None
    value = node.args[0]
    if isinstance(value, ast.Constant) and isinstance(value.value, str):
        return value.value
    if isinstance(value, (ast.List, ast.Tuple)) and all(isinstance(item, ast.Constant) and isinstance(item.value, str) for item in value.elts):
        return " ".join(item.value for item in value.elts)
    return None


def _python_execs(source, payload):
    """Detect actual Python process execution calls, not command-shaped prose."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return None
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if not isinstance(node.func, ast.Attribute):
            continue
        receiver = node.func.value.id if isinstance(node.func.value, ast.Name) else ""
        allowed = (receiver == "os" and node.func.attr in {"system", "popen", "execv", "execvp"}) or (receiver == "subprocess" and node.func.attr in {"Popen", "run", "call", "check_call", "check_output"})
        command = _literal_command(node) if allowed else None
        if command:
            for binary, args in decode(command)[0]:
                if _judge(binary, args, payload):
                    return "runs a desktop-control command from Python inline code"
    return None


def _js_exec(source):
    # Bounded deliberately: direct child_process execution only, no generic JS scan.
    if re.search(r"(?:child_process\s*\.\s*)?(?:execSync|execFileSync|spawnSync)\s*\(", source) and any(re.search(r"(?<![\w-])" + re.escape(command) + r"(?![\w-])", source) for command in INLINE_NAMES):
        return "runs a desktop-control command from JavaScript inline code"
    return None


def _static_hypr_modules():
    """Bounded static require() map; io/load modules remain deliberately deferred."""
    main = os.path.join(HOME, ".config/hypr/hyprland.lua")
    try:
        with open(main, encoding="utf-8") as handle:
            source = handle.read()
    except OSError:
        return set()
    modules = set()
    for name in re.findall(r"\brequire\s*\(?\s*['\"]([^'\"]+)['\"]", source):
        modules.add(_path(os.path.join(os.path.dirname(main), name + ("" if name.endswith(".lua") else ".lua"))))
    return modules


def _path(value, cwd=""):
    if not isinstance(value, str):
        return None
    expanded = os.path.expanduser(value)
    if not os.path.isabs(expanded):
        expanded = os.path.join(os.path.expanduser(cwd or os.getcwd()), expanded)
    return os.path.realpath(os.path.normpath(expanded))


def _protected_paths():
    return {_path(item) for item in HYPR_MAIN | DMS_SETTINGS} | _static_hypr_modules()


def _protected_path(path):
    return _path(path) in _protected_paths()


WRITE_REASON = "writes a desktop configuration file that is applied to the active session"
_PATH_TYPES = {"Path", "PurePath", "PosixPath", "PurePosixPath"}
_PASSTHROUGH = {"os.path.expanduser", "os.path.abspath", "os.path.normpath", "os.path.realpath", "os.fspath", "str"}
_OS_WRITE_FLAGS = {"O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_APPEND"}
_VALUE_LIMIT = 64


def _dotted(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
        return ".".join(reversed(parts))
    return ""


def _const(node):
    return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None


def _arg(call, index, keyword):
    if len(call.args) > index and not isinstance(call.args[index], ast.Starred):
        return call.args[index]
    return next((item.value for item in call.keywords if item.arg == keyword), None)


def _combine(options, join):
    result = {""} if join is None else None
    for values in options:
        if not values:
            return set()
        if result is None:
            result = set(values)
        else:
            result = {(join(a, b) if join else a + b) for a in result for b in values}
        if len(result) > _VALUE_LIMIT:
            result = set(list(result)[:_VALUE_LIMIT])
    return result or set()


def _py_values(node, env, depth=0):
    """Possible literal string values of a bounded Python path expression.

    Only literals, simple assigned names, f-strings of those, ``/`` and ``+``
    joins, ``os.path`` helpers, ``pathlib`` constructors and HOME lookups are
    resolved.  Anything else is dynamic and yields an empty set.
    """
    if node is None or depth > 25:
        return set()

    def values(child):
        return _py_values(child, env, depth + 1)

    if _const(node) is not None:
        return {node.value}
    if isinstance(node, ast.Name):
        return set(env.get(node.id, ()))
    if isinstance(node, ast.JoinedStr):
        parts = []
        for part in node.values:
            if _const(part) is not None:
                parts.append({part.value})
            elif isinstance(part, ast.FormattedValue) and part.format_spec is None and part.conversion in (-1, 115):
                parts.append(values(part.value))
            else:
                return set()
        return _combine(parts, None)
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Div, ast.Add)):
        return _combine([values(node.left), values(node.right)], os.path.join if isinstance(node.op, ast.Div) else None)
    if isinstance(node, ast.Subscript) and _dotted(node.value) == "os.environ" and _const(node.slice) == "HOME":
        return {HOME}
    if not isinstance(node, ast.Call):
        return set()
    name = _dotted(node.func)
    tail = name.rsplit(".", 1)[-1]
    if name in {"os.getenv", "os.environ.get"} and node.args and _const(node.args[0]) == "HOME":
        return {HOME}
    if tail == "home" and name.rsplit(".", 1)[0].rsplit(".", 1)[-1] in _PATH_TYPES:
        return {HOME}
    if name in _PASSTHROUGH and node.args:
        return values(node.args[0])
    if name in {"os.path.join", "posixpath.join"} or (tail in _PATH_TYPES and name in {tail, "pathlib." + tail}):
        if not node.args:
            return {"."} if tail in _PATH_TYPES else set()
        return _combine([values(item) for item in node.args], os.path.join)
    if isinstance(node.func, ast.Attribute):
        if node.func.attr in {"expanduser", "resolve", "absolute", "__fspath__"} and not node.args:
            return values(node.func.value)
        if node.func.attr == "joinpath":
            return _combine([values(node.func.value)] + [values(item) for item in node.args], os.path.join)
    return set()


def _py_env(tree):
    """Names assigned a resolvable path anywhere in the blob (all candidates kept)."""
    env = {}
    assigns = [node for node in ast.walk(tree) if isinstance(node, (ast.Assign, ast.AnnAssign, ast.NamedExpr))]
    for _ in range(3):  # resolve short chains such as ``base = ...; p = base / "x"``
        for node in assigns:
            found = _py_values(node.value, env)
            if not found:
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    known = env.setdefault(target.id, set())
                    for value in found:
                        if len(known) >= _VALUE_LIMIT:
                            break
                        known.add(value)
    return env


def _mode_writes(node, env):
    if node is None:
        return False  # open() defaults to read-only
    modes = _py_values(node, env)
    # A dynamic mode on a watched file fails closed.
    return not modes or any(re.search(r"[wax+]", mode) for mode in modes)


def _os_open_writes(node):
    if node is None:
        return False
    for item in ast.walk(node):
        if (isinstance(item, ast.Attribute) and item.attr in _OS_WRITE_FLAGS) or (isinstance(item, ast.Name) and item.id in _OS_WRITE_FLAGS):
            return True
        if isinstance(item, ast.Constant) and isinstance(item.value, int) and item.value & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND):
            return True
    return False


def _raw_python_write(source, protected):
    """Fail closed for unparseable blobs: a watched path plus an obvious write token."""
    forms = set()
    for item in protected | HYPR_MAIN | DMS_SETTINGS:
        forms.add(item)
        if item.startswith(HOME + os.sep):
            forms.add(item[len(HOME) + 1:])
    if not any(form in source for form in forms):
        return None
    opens_for_write = re.search(r"\bopen\s*\(", source) and re.search(r"['\"][rbt]*[wax+][rbt+]*['\"]", source)
    if opens_for_write or re.search(r"\b(?:write_text|write_bytes)\b|\bos\s*\.\s*(?:replace|rename|remove|unlink)\s*\(|\bshutil\s*\.\s*(?:copy\w*|move)\s*\(", source):
        return WRITE_REASON
    return None


def _python_writes(source, payload):
    """Detect Python file writes that target a watched desktop configuration file."""
    cwd = str(payload.get("cwd") or "")
    protected = _protected_paths()
    try:
        tree = ast.parse(source)
    except (SyntaxError, ValueError):
        return _raw_python_write(source, protected)
    env = _py_env(tree)

    def watched(node):
        for value in _py_values(node, env):
            value = re.sub(r"^\$(?:HOME|\{HOME\})(?=/|$)", lambda _: HOME, value)
            if _path(value, cwd) in protected:
                return True
        return False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = _dotted(node.func)
        receiver = node.func.value if isinstance(node.func, ast.Attribute) else None
        attr = node.func.attr if receiver is not None else ""
        hit = False
        if name in {"open", "io.open", "codecs.open", "builtins.open"}:
            hit = watched(_arg(node, 0, "file")) and _mode_writes(_arg(node, 1, "mode"), env)
        elif name == "os.open":
            hit = watched(_arg(node, 0, "path")) and _os_open_writes(_arg(node, 1, "flags"))
        elif name in {"os.replace", "os.rename", "os.renames", "shutil.move"}:
            hit = watched(_arg(node, 0, "src")) or watched(_arg(node, 1, "dst"))
        elif name in {"shutil.copy", "shutil.copy2", "shutil.copyfile", "shutil.copytree", "os.symlink", "os.link"}:
            hit = watched(_arg(node, 1, "dst"))
        elif name in {"os.remove", "os.unlink", "os.truncate"}:
            hit = watched(_arg(node, 0, "path"))
        elif name in {"fileinput.input", "fileinput.FileInput"}:
            inplace = _arg(node, 99, "inplace")
            if inplace is not None and not (isinstance(inplace, ast.Constant) and not inplace.value):
                files = _arg(node, 0, "files")
                items = files.elts if isinstance(files, (ast.List, ast.Tuple)) else [files]
                hit = any(watched(item) for item in items)
        elif receiver is not None and attr in {"write_text", "write_bytes", "unlink", "touch", "symlink_to", "hardlink_to"}:
            hit = watched(receiver)
        elif receiver is not None and attr in {"rename", "replace"} and len(node.args) + len(node.keywords) == 1:
            # Path.rename/replace(target); str.replace always takes two arguments.
            hit = watched(receiver) or watched(_arg(node, 0, "target"))
        elif receiver is not None and attr == "open":
            hit = watched(receiver) and _mode_writes(_arg(node, 0, "mode"), env)
        if hit:
            return WRITE_REASON
    return None


def _file_paths(payload):
    data = payload.get("tool_input") or {}
    cwd = str(payload.get("cwd") or "")
    if isinstance(data, dict):
        for key in ("path", "file_path", "filename", "target"):
            if key in data:
                yield _path(str(data[key]), cwd)
    if str(payload.get("tool_name", "")).lower().endswith("apply_patch"):
        for name in re.findall(r"^\*\*\*\s+(?:Update|Add|Delete|Move)\s+File:\s*(.+?)\s*$", _flatten(data), re.M):
            yield _path(name.strip(), cwd)
        for name in re.findall(r"(?:\+\+\+|---)\s+(?:[ab]/)?([^\n]+)", _flatten(data)):
            yield _path(name.strip(), cwd)


def _write_target(binary, args, cwd):
    if binary in {"cp", "mv"} and len(args) >= 2:
        return _path(args[-1], cwd)
    if binary == "sed" and "-i" in args:
        return _path(args[-1], cwd)
    if binary == "tee" and args:
        return _path(args[-1], cwd)
    return None


def _shell_policy(command, payload):
    found, blobs, _ = decode(command)
    for binary, args in found:
        reason = _judge(binary, args, payload)
        if reason:
            return reason
        target = _write_target(binary, args, str(payload.get("cwd") or ""))
        if target and _protected_path(target):
            return "writes a desktop configuration file that is applied to the active session"
    for target in re.findall(r"(?:^|[;|&\s])(?:>>?|<>)\s*([^\s;|&]+)", command):
        if _protected_path(_path(target.strip("'\""), str(payload.get("cwd") or ""))):
            return "writes a desktop configuration file that is applied to the active session"
    for kind, source in blobs:
        if kind.startswith("python") or kind == "heredoc":
            reason = _python_execs(source, payload) or _python_writes(source, payload)
        else:
            reason = _js_exec(source)
        if reason:
            return reason
    return None


_CUA_MUTATION = re.compile(r"\b(?:createBrowserTab|click|pressKey|typeText|moveMouse|drag|activate|close|goto|navigate|setValue|scroll)\s*\(")
_HIDDEN_IAB = re.compile(r"^\s*(?:(?:let|const|var)\s+\w+\s*=\s*)?await\s+cua\.createBrowserTab\(\s*['\"]iab['\"]\s*,\s*[^,;]+\s*,\s*\{\s*visible\s*:\s*false\s*\}\s*\)\s*;?\s*$")


def _cua_policy(payload, require_known_action=False):
    data = payload.get("tool_input") or {}
    text = _flatten(data)
    # Check mutations before reads: a combined snapshot plus click is not read-only.
    if _CUA_MUTATION.search(text):
        if _HIDDEN_IAB.fullmatch(text):
            return None
        if re.search(r"\bcreateBrowserTab\s*\(", text):
            return "opens a visible browser tab or window"
        return "manipulates the visible desktop or browser"
    if re.fullmatch(r"\s*(?:(?:let|const|var)\s+\w+\s*=\s*)?(?:await\s+)?cua\.(?:getState|getTab|getBrowser)\([^;]*\)\s*;?\s*", text):
        return None
    if require_known_action:
        return "uses a desktop-control tool with an unrecognised operation"
    return None


def classify(payload: dict) -> str | None:
    """Return an approval reason for one payload, otherwise ``None``."""
    tool = str(payload.get("tool_name") or "").lower()
    if tool == "functions.exec":
        # The outer orchestration source is opaque; nested canonical calls are hooked.
        return None
    if tool.startswith("functions."):
        tool = tool.split(".", 1)[1]
    if tool in FILE_TOOLS:
        return next(("writes a desktop configuration file that is applied to the active session" for path in _file_paths(payload) if path and _protected_path(path)), None)
    if tool in SHELL_TOOLS:
        return _shell_policy(_command(payload), payload)
    if "cua_repl" in tool:
        return _cua_policy(payload, require_known_action=True)
    if tool.startswith("mcp__") and re.search(r"(?:^|__)(?:computer|desktop|native)(?:__|_|$)", tool):
        action = tool.rsplit("__", 1)[-1]
        if action in {"get_state", "getstate", "snapshot", "get_tab", "gettab"}:
            return None
        return _cua_policy(payload, require_known_action=True)
    return None


def bindings(payload: dict) -> dict:
    """Bind gated direct script invocations and explicit provider process identity.

    Unknown scripts are intentionally not scanned: hashing a directly invoked
    file detects changes between approval and execution without pretending to
    understand arbitrary future child processes.
    """
    scripts = {}
    processes = []
    interpreter_scripts = set()
    tool = str(payload.get("tool_name") or "").lower()
    if tool.startswith("functions."):
        tool = tool.split(".", 1)[1]
    if tool in SHELL_TOOLS:
        command = _command(payload)
        candidates = list(direct_program_paths(command))
        for binary, args in decode(command)[0]:
            if binary in {"bash", "sh", "zsh", "dash", "python", "python2", "python3", "node", "gjs"}:
                for arg in args:
                    path = _path(arg, str(payload.get("cwd") or ""))
                    if not arg.startswith("-") and os.path.isfile(path):
                        candidates.append(path)
                        interpreter_scripts.add(path)
            if binary in {"kill", "skill"}:
                for arg in args:
                    if arg.isdecimal() and int(arg) > 0:
                        pid = int(arg)
                        try:
                            with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
                                start = handle.read().rsplit(")", 1)[1].split()[19]
                        except (OSError, IndexError):
                            start = "unavailable"
                        processes.append({"pid": pid, "start_time": start})
            resolved = shutil.which(binary)
            if resolved:
                candidates.append(resolved)
        for binary in candidates:
            candidate = _path(binary, str(payload.get("cwd") or ""))
            if candidate and os.path.isfile(candidate):
                try:
                    with open(candidate, "rb") as handle:
                        content = handle.read()
                    if candidate in interpreter_scripts or content.startswith(b"#!"):
                        scripts[candidate] = hashlib.sha256(content).hexdigest()
                except OSError:
                    pass
    result = {"scripts": scripts, "processes": processes}
    if payload.get("process_identity") is not None:
        result["process_identity"] = payload["process_identity"]
    return result
