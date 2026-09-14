"""Small, desktop-only shell decoder.

This is intentionally not the shared ``_cmdparse`` module: other guards depend
on that module's more general behaviour.  It identifies executable command
positions and inline code bodies; it does not execute anything.
"""
from __future__ import annotations

import re
import shlex

SHELLS = {"bash", "sh", "zsh", "dash", "ash", "ksh"}
INTERPRETERS = {"python", "python3", "python2", "node", "gjs"}
WRAPPERS = {
    "sudo", "doas", "env", "timeout", "nohup", "nice", "stdbuf",
    "setsid", "command", "exec", "systemd-run", "xargs",
}
VALUE_FLAGS = {
    "sudo": {"-u", "-g", "-p", "--user", "--group"},
    "doas": {"-u", "-C"}, "env": {"-u", "-C", "--chdir", "-S"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "xargs": {"-I", "-n", "-L", "-P", "-d", "-E", "-s", "-a", "--replace"},
    "stdbuf": {"-i", "-o", "-e"}, "nice": {"-n"},
}
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*", re.S)
HEREDOC = re.compile(r"<<-?\s*(?:'([^']+)'|\"([^\"]+)\"|([A-Za-z_][A-Za-z0-9_]*))")


def _separate_newlines(text: str):
    """Make unquoted newlines command separators without extending comments."""
    out, quote, index = [], None, 0
    while index < len(text):
        char = text[index]
        if char in "'\"" and (index == 0 or text[index - 1] != "\\"):
            quote = None if quote == char else (char if quote is None else quote)
        if char == "\n" and quote is None:
            # Keep the newline: shlex uses it to end a ``#`` comment.  The
            # following semicolon supplies the command boundary.
            out.append("\n; ")
        else:
            out.append(char)
        index += 1
    return "".join(out)


def _tokens(text: str):
    lexer = shlex.shlex(_separate_newlines(text), posix=True, punctuation_chars=";|&()<>")
    lexer.whitespace_split = True
    try:
        return list(lexer), True
    except ValueError:
        return text.replace("'", " ").replace('"', " ").split(), False


def _substitutions(text: str):
    """Return command substitutions, ignoring literal single quoted prose."""
    out, index, quote = [], 0, None
    while index < len(text):
        char = text[index]
        if char in "'\"":
            if quote == char:
                quote = None
            elif quote is None:
                quote = char
            index += 1
            continue
        if quote == "'":
            index += 1
            continue
        if text.startswith("$(", index):
            depth, start, cursor = 1, index + 2, index + 2
            while cursor < len(text) and depth:
                if text[cursor] == "(":
                    depth += 1
                elif text[cursor] == ")":
                    depth -= 1
                cursor += 1
            if not depth:
                out.append(text[start:cursor - 1])
                index = cursor
                continue
        if char == "`":
            end = text.find("`", index + 1)
            if end != -1:
                out.append(text[index + 1:end])
                index = end + 1
                continue
        index += 1
    return out


def _heredocs(command: str):
    """Split heredoc bodies according to the command that consumes them."""
    lines, kept, blobs, i = command.splitlines(), [], [], 0
    while i < len(lines):
        line = lines[i]
        matches = list(HEREDOC.finditer(line))
        kept.append(line)
        if not matches:
            i += 1
            continue
        consumer = line.lower()
        fate = "shell" if re.search(r"(?:^|[|;&\s])(bash|sh|zsh|dash)\b", consumer) else (
            "code" if re.search(r"\b(?:python(?:2|3)?|node|gjs)\b", consumer) else "data")
        i += 1
        for match in matches:
            delim = match.group(1) or match.group(2) or match.group(3)
            body = []
            while i < len(lines) and lines[i].strip(" \t") != delim:
                body.append(lines[i])
                i += 1
            if i < len(lines):
                i += 1
            # An unquoted data heredoc expands command substitutions even when
            # its consumer merely writes data.  Quoted delimiters keep prose
            # literal and must not be walked as a shell script.
            if fate != "data":
                blobs.append((fate, "\n".join(body)))
            elif match.group(3):
                blobs.append(("substitutions", "\n".join(body)))
    return "\n".join(kept), blobs


def _segments(tokens):
    current = []
    for token in tokens:
        if token and all(char in ";|&()<>" for char in token):
            if current:
                yield current
            current = []
        else:
            current.append(token)
    if current:
        yield current


def _command_from(segment):
    index = 0
    while index < len(segment) and (segment[index] in {"!", "do", "then", "if", "for", "while", "until"} or ASSIGNMENT.fullmatch(segment[index])):
        index += 1
    while index < len(segment):
        base = segment[index].rsplit("/", 1)[-1]
        if base not in WRAPPERS:
            return base, segment[index + 1:]
        index += 1
        while index < len(segment):
            token = segment[index]
            if token in VALUE_FLAGS.get(base, set()):
                index += 2
            elif token.startswith("-") or ASSIGNMENT.fullmatch(token):
                index += 1
            else:
                break
    return None, []


def direct_program_paths(command: str):
    """Absolute or relative program paths in command position (no script scan)."""
    stripped, _ = _heredocs(command)
    tokens, _ = _tokens(stripped)
    paths = []
    for segment in _segments(tokens):
        index = 0
        while index < len(segment) and (segment[index] in {"!", "do", "then", "if", "for", "while", "until"} or ASSIGNMENT.fullmatch(segment[index])):
            index += 1
        while index < len(segment):
            base = segment[index].rsplit("/", 1)[-1]
            if base not in WRAPPERS:
                if "/" in segment[index]:
                    paths.append(segment[index])
                break
            index += 1
            while index < len(segment):
                token = segment[index]
                if token in VALUE_FLAGS.get(base, set()):
                    index += 2
                elif token.startswith("-") or ASSIGNMENT.fullmatch(token):
                    index += 1
                else:
                    break
    return paths


def _shell_code(args):
    for index, arg in enumerate(args):
        if arg == "-c" and index + 1 < len(args):
            return args[index + 1]
        # ``bash -lc script`` is just as executable as ``bash -c script``.
        if arg.startswith("-") and "c" in arg[1:]:
            if arg.endswith("c") and index + 1 < len(args):
                return args[index + 1]
            position = arg.find("c", 1)
            if position + 1 < len(arg):
                return arg[position + 1:]
    return None


def _inline_code(binary, args):
    flags = {"python": {"-c"}, "python2": {"-c"}, "python3": {"-c"},
             "node": {"-e", "--eval"}, "gjs": {"-c"}}.get(binary, set())
    for index, arg in enumerate(args):
        if arg in flags and index + 1 < len(args):
            return args[index + 1]
        if any(arg.startswith(flag + "=") for flag in flags):
            return arg.split("=", 1)[1]
    return None


def decode(command: str, depth: int = 0):
    """Return ``(invocations, code_blobs, parsed_cleanly)`` for a shell line."""
    if depth > 5:
        return [], [], False
    stripped, heredocs = _heredocs(command)
    found, code, ok = [], [], True
    for fate, body in heredocs:
        if fate == "shell":
            nested, nested_code, nested_ok = decode(body, depth + 1)
            found.extend(nested); code.extend(nested_code); ok = ok and nested_ok
        elif fate == "code":
            code.append(("heredoc", body))
        elif fate == "substitutions":
            for substitution in _substitutions(body):
                nested, nested_code, nested_ok = decode(substitution, depth + 1)
                found.extend(nested); code.extend(nested_code); ok = ok and nested_ok
    tokens, parsed = _tokens(stripped)
    ok = ok and parsed
    for segment in _segments(tokens):
        binary, args = _command_from(segment)
        if not binary:
            continue
        found.append((binary, args))
        if binary == "eval":
            nested, nested_code, nested_ok = decode(" ".join(args), depth + 1)
            found.extend(nested); code.extend(nested_code); ok = ok and nested_ok
        elif binary in SHELLS:
            script = _shell_code(args)
            if script is not None:
                nested, nested_code, nested_ok = decode(script, depth + 1)
                found.extend(nested); code.extend(nested_code); ok = ok and nested_ok
        elif binary in INTERPRETERS:
            inline = _inline_code(binary, args)
            if inline is not None:
                code.append((binary, inline))
    for substitution in _substitutions(stripped):
        nested, nested_code, nested_ok = decode(substitution, depth + 1)
        found.extend(nested); code.extend(nested_code); ok = ok and nested_ok
    return found, code, ok
