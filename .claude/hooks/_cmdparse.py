"""Shared shell-command walker for the PreToolUse guards.

A guard that greps the raw command string loses to quoting: `grep "terraform
destroy" README.md` and `echo "run apply"` both trip it, which is how the old
terraform-guard ended up blocking prose three times in one session. A guard that
only inspects the first word loses to `cd x && terraform destroy`.

This module does the one thing every command guard needs and nothing else: it
enumerates the positions in a command line where a binary is actually being
*invoked*. It is quote-aware, so text inside a quoted argument is never mistaken
for a command; it steps over `VAR=value` prefixes, shell keywords (`do`,
`then`, `if`) and wrappers (`sudo`, `env`,
`timeout`, `xargs`...); and it descends into nested shells, so `bash -c '...'`
and `$(...)` are walked rather than guessed at.

It never decides policy. Callers get `(binary, args)` pairs and judge for
themselves.

Deliberate limits, stated rather than hidden:

  * A wrapper that reads its command from stdin (`echo apply | xargs terraform`)
    supplies the subcommand after this module has stopped looking.
  * Code passed to a non-shell interpreter (`python3 -c "subprocess.run([...])"`)
    is not a shell command and cannot be tokenized as one. Those strings are
    returned separately as `code_blobs` so a caller can pattern-match them, which
    is cruder but is confined to the one place crudeness is warranted.
  * Nothing here sees a command a script file runs. Only a PATH shim on the
    binary itself closes that, which is a root-owned install, not a hook.
"""
import re
import shlex

MAX_DEPTH = 4

# Punctuation that shell tokenization groups into standalone tokens. A token
# made up entirely of these characters is a separator, never a command.
_PUNCT = "();<>|&`"

ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=.*", re.S)
# `<<EOF`, `<<-'EOF'`, `<<"EOF"` — but never the `<<<` herestring.
HEREDOC = re.compile(
    r"(?<!<)<<-?[ \t]*(?:(?:'([^']+)')|(?:\"([^\"]+)\")|([A-Za-z_][A-Za-z0-9_]*))")
NUMERIC = re.compile(r"[0-9]+(?:\.[0-9]+)?[smhd]?")

# Commands that run another command given as their arguments.
WRAPPERS = {
    "nohup", "timeout", "sudo", "doas", "env", "time", "stdbuf", "nice",
    "ionice", "xargs", "command", "exec", "setsid", "script", "unbuffer",
    "strace", "ltrace", "watch", "chrt", "taskset", "proxychains",
}

# Wrapper flags that consume the following token, so it is not the binary.
WRAPPER_VALUE_FLAGS = {
    "sudo": {"-u", "-g", "-p", "-r", "-t", "-U", "-C", "-h", "--user", "--group"},
    "doas": {"-u", "-C"},
    "env": {"-u", "--unset", "-C", "--chdir", "-S"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "xargs": {"-I", "-i", "-n", "-L", "-P", "-d", "-E", "-s", "-a", "--replace"},
    "nice": {"-n"},
    "ionice": {"-c", "-n", "-p"},
    "chrt": {"-p"},
    "taskset": {"-c", "-p"},
    "watch": {"-n", "--interval"},
    "stdbuf": {"-i", "-o", "-e"},
}

# Shell keywords occupy the position a command name would, so a binary run as
# the body of a loop or conditional (`for x in 1 2; do hyprctl ...; done`) is
# only visible if they are stepped over first.
KEYWORDS = {
    "do", "done", "then", "fi", "else", "elif", "if", "while", "until", "for",
    "select", "case", "esac", "function", "!", "coproc", "{", "}",
}

SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "ash", "busybox"}

# Interpreters whose inline-code flag carries something this module cannot
# tokenize as shell. The string is handed back for pattern matching instead.
INTERPRETERS = {
    "python": ("-c",), "python2": ("-c",), "python3": ("-c",),
    "node": ("-e", "--eval", "-p", "--print"),
    "perl": ("-e", "-E"), "ruby": ("-e",), "php": ("-r",),
    "deno": ("eval",), "bun": ("-e",),
}


def _is_separator(token):
    return bool(token) and all(ch in _PUNCT for ch in token)


def _tokenize(command):
    """Tokenize like a shell would. Returns (tokens, ok)."""
    text = command.replace("\n", " ; ")
    lexer = shlex.shlex(text, posix=True, punctuation_chars=_PUNCT)
    lexer.whitespace_split = True
    try:
        return list(lexer), True
    except ValueError:
        # Unbalanced quote. Fall back to a naive split so a caller can still
        # apply a coarse check, and tell it the parse was not trustworthy.
        return text.replace("'", " ").replace('"', " ").split(), False


def _heredoc_fate(text):
    """What the shell will do with a heredoc body: run it, read it, or neither.

    Decided from every command on the line that opened it, so `cat <<EOF | bash`
    is read as a script even though `cat` is what holds the heredoc.
    """
    line = text.rsplit("\n", 1)[-1]
    tokens, _ = _tokenize(line)
    consumers = []
    for segment in _split_segments(tokens):
        for token in segment:
            if ASSIGN.fullmatch(token):
                continue
            base = token.rsplit("/", 1)[-1]
            if base in WRAPPERS or base in KEYWORDS:
                continue
            consumers.append(base)
            break
    if any(base in SHELLS for base in consumers):
        return "shell"
    if any(base in INTERPRETERS for base in consumers):
        return "code"
    return "data"


def _extract_heredocs(command):
    """Lift heredoc bodies out of a command line.

    A heredoc body is not a command line: `cat <<'EOF' … EOF` writing a document
    that happens to mention `hyprctl` is not running hyprctl. Left in the token
    stream, every word of that body sits where a command name could be, and any
    guard reading command positions fires on prose. So bodies come out here and
    are classified by what actually consumes them:

      shell  (`bash <<EOF`, `cat <<EOF | sh`)  walked as commands
      code   (`python3 - <<PY`)                returned as a code blob to
                                               pattern-match, as `python3 -c`
                                               already is
      data   (`cat > file <<EOF`, `jq <<EOF`)  dropped; nothing executes it

    Returns (command_without_bodies, [(fate, body), ...]).
    """
    bodies, text = [], command
    while True:
        match = HEREDOC.search(text)
        if not match:
            return text, bodies
        delimiter = match.group(1) or match.group(2) or match.group(3)
        fate = _heredoc_fate(text[:match.start()])
        newline = text.find("\n", match.end())
        tail = text[match.end():newline] if newline != -1 else text[match.end():]
        head = text[:match.start()] + tail
        if newline == -1:
            text = head
            continue
        rest = text[newline + 1:]
        terminator = re.compile(r"^[\t ]*" + re.escape(delimiter) + r"[\t ]*$", re.M)
        end = terminator.search(rest)
        if end:
            bodies.append((fate, rest[:end.start()]))
            text = head + "\n" + rest[end.end():]
        else:
            bodies.append((fate, rest))
            text = head


def _split_segments(tokens):
    segments, current = [], []
    for token in tokens:
        if _is_separator(token):
            if current:
                segments.append(current)
            current = []
        else:
            current.append(token)
    if current:
        segments.append(current)
    return segments


def _shell_script_arg(args):
    """The script string a shell was handed with -c, or None."""
    for index, token in enumerate(args):
        if token == "--":
            continue
        if token.startswith("--"):
            continue
        if token.startswith("-") and "c" in token[1:]:
            if index + 1 < len(args):
                return args[index + 1]
            return None
        if not token.startswith("-"):
            return None  # first positional is the script *file*, not inline code
    return None


def _interpreter_code_arg(base, args):
    flags = INTERPRETERS[base]
    for index, token in enumerate(args):
        if token in flags and index + 1 < len(args):
            return args[index + 1]
        for flag in flags:
            if token.startswith(flag + "="):
                return token[len(flag) + 1:]
    return None


def _walk_segment(tokens, depth, found, code_blobs):
    index, count = 0, len(tokens)
    while index < count:
        token = tokens[index]
        if token in KEYWORDS:
            index += 1
            continue
        if ASSIGN.fullmatch(token):
            index += 1
            continue
        base = token.rsplit("/", 1)[-1]
        if base in WRAPPERS:
            value_flags = WRAPPER_VALUE_FLAGS.get(base, set())
            index += 1
            while index < count:
                nxt = tokens[index]
                if nxt in value_flags:
                    index += 2
                elif nxt.startswith("-") or NUMERIC.fullmatch(nxt):
                    index += 1
                else:
                    break
            continue
        break

    if index >= count:
        return

    base = tokens[index].rsplit("/", 1)[-1]
    args = tokens[index + 1:]
    found.append((base, args))

    if base in SHELLS and depth < MAX_DEPTH:
        script = _shell_script_arg(args)
        if script:
            _walk(script, depth + 1, found, code_blobs)
    elif base in INTERPRETERS:
        code = _interpreter_code_arg(base, args)
        if code:
            code_blobs.append(code)


def _walk(command, depth, found, code_blobs):
    command, heredocs = _extract_heredocs(command)
    for fate, body in heredocs:
        if fate == "shell" and depth < MAX_DEPTH:
            _walk(body, depth + 1, found, code_blobs)
        elif fate == "code":
            code_blobs.append(body)
    tokens, ok = _tokenize(command)
    if not ok:
        code_blobs.append(command)
    for segment in _split_segments(tokens):
        _walk_segment(segment, depth, found, code_blobs)
    return ok


def invocations(command):
    """Walk a command line.

    Returns (found, code_blobs, parsed_cleanly):
      found          - list of (binary_basename, args) in command position
      code_blobs     - inline code handed to a non-shell interpreter, plus the
                       raw text of anything that failed to tokenize
      parsed_cleanly - False if any part had unbalanced quoting
    """
    found, code_blobs = [], []
    ok = _walk(command, 0, found, code_blobs)
    return found, code_blobs, ok


def subcommand(args):
    """First non-flag argument, plus the non-flag arguments after it."""
    for index, token in enumerate(args):
        if token.startswith("-"):
            continue
        rest = [a.lower() for a in args[index + 1:] if not a.startswith("-")]
        return token.lower(), rest
    return None, []
