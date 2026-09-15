"""Independent black-box regression corpus; desktop command strings never run."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

import core
import policy


def call(command="pwd", **fields):
    return {"hook_event_name": "PreToolUse", "tool_name": "Bash",
            "tool_input": {"command": command}, "cwd": "/home/archie",
            "session_id": "acceptance-parent", "agent_id": "acceptance-actor", **fields}


def request_id(output):
    return re.search(r"YES (DSK-[A-F0-9]{6})", output["systemMessage"]).group(1)


class Acceptance(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def handle(self, payload, provider="codex"):
        return core.handle(payload, provider, self.root)

    def confirm(self, code, decision="YES", provider="codex"):
        return self.handle({"hook_event_name": "UserPromptSubmit",
                            "session_id": "acceptance-parent", "prompt": f"{decision} {code}"}, provider)

    def test_benign_work_in_both_providers(self):
        commands = [
            "cd ~/.claude && ls; find . -maxdepth 2 -name '*.json' | head -10",
            "rg -n 'hyprctl dispatch|pkill' README.md",
            "cat <<'EOF' > /tmp/notes.md\nhyprctl dispatch workspace 2\nEOF",
            "python3 - <<'PY'\np='README.md'\ns=open(p).read()\ns=s.replace('gsettings set','gsettings write')\nopen(p,'w').write(s)\nPY",
            "python3 -c \"import subprocess; subprocess.run(['hyprctl','clients'])\"",
            "gjs ./build-helper.js", "npm run build", "cargo test",
            "claude auth status", "codex login status",
            "java -version", "false", "true",
            "hyprctl -j clients", "hyprctl --batch 'clients; monitors'",
            "loginctl show-session", "systemctl --user status dms.service",
            "xrandr --query", "kill -0 1234",
            "cat < ~/.config/hypr/hyprland.lua",
        ]
        for provider in ("claude", "codex"):
            for command in commands:
                with self.subTest(provider=provider, command=command):
                    self.assertIsNone(self.handle(call(command), provider))

    def test_required_protection_in_both_providers(self):
        commands = [
            "hyprctl -i 0 dispatch movewindow l", "hyprctl reload",
            "hyprctl --batch 'clients; dispatch workspace 2'",
            "bash -lc 'hyprctl dispatch workspace 2'",
            "bash -o errexit -c 'hyprctl reload'",
            "systemd-run --user --scope hyprctl dispatch workspace 2",
            "eval 'hyprctl dispatch workspace 2'",
            "cat <<'EOF' | bash\nhyprctl reload\nEOF",
            "python3 -c \"import os; os.system('swww img /tmp/a.png')\"",
            "kill -9 4242", "pkill -f claude", "killall codex",
            "systemctl --user reload waybar.service",
            "systemctl --user reload-or-restart dms.service",
            "systemctl --user try-restart dms.service",
            "sudo systemctl restart greetd", "kitty", "workspace-switch 3",
            "setxkbmap us", "hyprpm reload", "hypridle", "theme-apply",
            "wtype hello", "xdg-open /tmp/example.pdf",
            "tmux kill-session -t other-work", "tmux send-keys -t other 'exit' Enter",
            "zellij kill-all-sessions --yes",
            "codex-desktop", "claude-desktop",
            "claude --handle-uri claude://callback", "claude auth login",
        ]
        for provider in ("claude", "codex"):
            for command in commands:
                with self.subTest(provider=provider, command=command):
                    result = self.handle(call(command), provider)
                    self.assertIsNotNone(result)
                    self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")
                    self.assertNotIn("continue", result)
                    self.assertNotIn("stopReason", result)
                    request_id(result)

    def test_prose_in_non_desktop_tools(self):
        for tool in ("Write", "Edit", "mcp__github__create_issue", "mcp__session__rename"):
            item = call(tool_name=tool, tool_input={"file_path": "/tmp/report.md", "body": "Example: tab.click(); hyprctl dispatch workspace 2"})
            self.assertIsNone(self.handle(item))

    def test_operator_approval_is_not_an_automatic_model_escape(self):
        self.assertIsNone(self.handle(call("desktop-guard status")))
        self.assertIsNone(self.handle(call("desktop-guard show DSK-ABCDEF")))
        self.assertIsNotNone(self.handle(call("desktop-guard approve DSK-ABCDEF")))
        self.assertIsNotNone(self.handle(call("desktop-guard run DSK-ABCDEF")))
        self.assertIsNotNone(self.handle(call("desktop-guard rollback")))

    def test_watched_file_and_native_patch_syntax(self):
        watched = str(Path.home() / ".config/hypr/hyprland.lua")
        items = [call(tool_name="Write", tool_input={"file_path": watched, "content": "-- test"}),
                 call(tool_name="apply_patch", tool_input={"command": f"*** Begin Patch\n*** Update File: {watched}\n@@\n-old\n+new\n*** End Patch"}),
                 call(tool_name="Edit", tool_input={"file_path": ".config/hypr/hyprland.lua"}),
                 call("printf '%s' '-- test' > ~/.config/hypr/hyprland.lua")]
        for item in items:
            self.assertIsNotNone(self.handle(item))
        for path in ("/tmp/staging/hyprland.lua", str(Path.home() / ".config/hypr/carry.lua")):
            self.assertIsNone(self.handle(call(tool_name="Write", tool_input={"file_path": path, "content": "hl.dsp.workspace(3)"})))

    def test_permit_is_action_scoped_not_a_session_lock(self):
        original = call("hyprctl reload")
        code = request_id(self.handle(original))
        self.assertIsNone(self.handle(call("pwd")))
        self.confirm(code)
        self.assertIsNone(self.handle(call("rg reload README.md")))
        self.assertIsNotNone(self.handle(call("hyprctl reload", cwd="/tmp")))
        self.assertIsNotNone(self.handle(call("hyprctl reload", agent_id="another-child")))
        self.assertIsNotNone(self.handle(call("hyprctl reload", session_id="another-session")))
        self.assertIsNone(self.handle(original))
        self.assertIsNotNone(self.handle(original))

    def test_binding_changes_prevent_consumption(self):
        script = self.root / "workspace-switch"
        script.write_text("#!/bin/sh\n# original test fixture\n")
        item = call(str(script))
        code = request_id(self.handle(item))
        self.confirm(code)
        script.write_text("#!/bin/sh\n# changed fixture\n")
        self.assertIsNotNone(self.handle(item))

    def test_plain_interpreter_script_is_bound_without_shebang(self):
        script = self.root / "prepare.py"
        script.write_text("# source fixture, never executed\n")
        item = call(f"python3 {script}; hyprctl reload")
        code = request_id(self.handle(item))
        self.confirm(code)
        script.write_text("# changed source fixture\n")
        self.assertIsNotNone(self.handle(item))

    def test_numeric_signal_snapshots_process_identity_without_sending_signal(self):
        bindings = policy.bindings(call(f"kill -TERM {os.getpid()}"))
        self.assertEqual(bindings["processes"][0]["pid"], os.getpid())
        record = {"bindings": bindings}
        self.assertTrue(core._bound_action_is_current(record))
        bindings["processes"][0]["start_time"] = "not-the-same-process"
        self.assertFalse(core._bound_action_is_current(record))

    def test_broken_policy_can_be_approved_but_never_auto_allows(self):
        with mock.patch.object(core, "_policy_decision", side_effect=NameError("FILE_TOOLS")):
            original = call("example-unclassified-command")
            code = request_id(self.handle(original))
            self.confirm(code)
            self.assertIsNone(self.handle(original))
            self.assertIsNone(self.handle(call(tool_name="Read", tool_input={"file_path": "/tmp/log"})))

    def test_unavailable_ledger_allows_safe_shell_inspection(self):
        root_file = self.root / "file-not-directory"
        root_file.write_text("fixture")
        self.assertIsNone(core.handle(call("pwd"), "codex", root_file))
        blocked = core.handle(call("hyprctl reload"), "codex", root_file)
        self.assertEqual(blocked["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_cancel_wrong_code_and_expiry_do_not_freeze_work(self):
        code = request_id(self.handle(call("hyprctl reload")))
        wrong = self.confirm("DSK-000000")
        self.assertEqual(wrong["hookSpecificOutput"]["hookEventName"], "UserPromptSubmit")
        self.assertIsNone(self.handle(call("pwd")))
        self.confirm(code, "NO")
        self.assertIsNone(self.handle(call("pwd")))
        new_code = request_id(self.handle(call("hyprctl reload")))
        self.assertNotEqual(code, new_code)
        self.confirm(new_code)
        with mock.patch.object(core.time, "time", return_value=core.time.time() + 3600):
            self.assertIsNotNone(self.handle(call("hyprctl reload")))

    def test_bootstrap_error_uses_event_specific_output(self):
        spec = importlib.util.spec_from_file_location("candidate_bootstrap", Path(__file__).with_name("bootstrap.py"))
        bootstrap = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bootstrap)
        for event in ("PreToolUse", "UserPromptSubmit"):
            output = io.StringIO()
            with mock.patch("sys.stdin", io.StringIO(json.dumps(call(hook_event_name=event)))), contextlib.redirect_stdout(output):
                bootstrap.launch("codex", self.root / "missing-installation")
            data = json.loads(output.getvalue())
            self.assertEqual(data["hookSpecificOutput"]["hookEventName"], event)
            self.assertNotIn("continue", data)


if __name__ == "__main__":
    unittest.main(verbosity=2)
