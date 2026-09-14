import os
import tempfile
import unittest

import policy


def bash(command, **extra):
    return {"tool_name": "exec_command", "tool_input": {"command": command}, "cwd": "/tmp", **extra}


class PolicyTests(unittest.TestCase):
    def blocked(self, command, **extra):
        self.assertIsNotNone(policy.classify(bash(command, **extra)), command)

    def allowed(self, command, **extra):
        self.assertIsNone(policy.classify(bash(command, **extra)), command)

    def test_normal_work_and_prose_pass(self):
        for command in (
            "ls -la /tmp", "grep -rn 'hyprctl dispatch' README.md",
            "cat <<'EOF' > /tmp/note\nhyprctl dispatch workspace 2\nEOF",
            "python3 - <<'PY'\nprint('hyprctl dispatch')\nPY",
            "gjs build-helper.js", "node build.js", "kill -0 1234",
        ):
            self.allowed(command)

    def test_desktop_actions_and_wrappers_block(self):
        for command in (
            "hyprctl dispatch workspace 2", "hyprctl -i 0 dispatch movewindow l", "hyprpm reload",
            "hypridle", "hyprsunset -t 4000", "theme-apply", "workspace-switch 3", "kitty",
            "eval 'hyprctl reload'", "bash -lc 'hyprctl dispatch workspace 2'",
            "systemd-run --user hyprctl dispatch workspace 2",
            "xargs -n1 hyprctl dispatch workspace 2",
            "cat <<'EOF' | bash\nhyprctl dispatch workspace 2\nEOF",
            "echo $(hyprctl dispatch workspace 2)", "systemctl --user reload waybar.service",
            "kill -9 4242", "pkill kitty", "wtype hello", "xdg-open /tmp/a.pdf", "sudo systemctl restart greetd",
            "setxkbmap us", "gdbus call --session --dest org.example --object-path /x --method x.Y",
        ):
            self.blocked(command)

    def test_inline_execution_is_semantic(self):
        self.blocked("python3 -c \"import subprocess; subprocess.run(['hyprctl', 'reload'])\"")
        self.blocked("python3 -c \"import os; os.system('swww img /tmp/a.png')\"")
        self.blocked("node -e \"require('child_process').execSync('hyprctl reload')\"")
        self.allowed("python3 -c \"s='hyprctl reload'; print(s)\"")
        self.allowed("python3 -c \"import subprocess; subprocess.run(['hyprctl', 'clients'])\"")

    def test_eval_batch_and_headless_edges(self):
        self.blocked("hyprctl eval 'return os.execute(\\\"hyprctl reload\\\")'")
        self.blocked("hyprctl -b 'dispatch workspace 2'")
        self.allowed("hyprctl eval 'return (2 + 2) * 3'")
        self.allowed("chromium --headless --dump-dom https://example.invalid")
        self.allowed("node -e \"console.log('hyprctl reload')\"")

    def test_unverified_owned_pid_never_passes(self):
        self.blocked("kill -TERM 4242", tool_owned_pids=[{"pid": 4242, "start_time": 10}])
        self.blocked("kill -TERM 4242")

    def test_watched_files_block_deferred_files_pass(self):
        self.assertIsNotNone(policy.classify({"tool_name": "Write", "tool_input": {"file_path": "~/.config/hypr/hyprland.lua"}}))
        self.assertIsNone(policy.classify({"tool_name": "Edit", "tool_input": {"file_path": "~/.config/hypr/local.lua"}}))
        self.blocked("sed -i 's/a/b/' ~/.config/hypr/hyprland.lua")
        self.allowed("cp x ~/.config/hypr/carry.lua")
        self.blocked("printf x > ~/.config/hypr/hyprland.lua")
        self.allowed("cat < ~/.config/hypr/hyprland.lua")
        self.assertIsNotNone(policy.classify({"tool_name": "apply_patch", "cwd": "~/.config/hypr", "tool_input": {"patch": "*** Update File: hyprland.lua\n"}}))

    def test_narrow_desktop_reads_pass(self):
        for command in ("hyprctl clients", "hyprctl eval 'return 2 + 2'", "dms ipc call settings get", "loginctl show-session", "grim /tmp/shot.png", "kitty --version", "xclip -o -selection clipboard", "xrandr --query", "wlr-randr --json"):
            self.allowed(command)

    def test_read_flags_do_not_override_desktop_mutations(self):
        for command in (
            "xclip -selection clipboard",
            "xrandr --query --output DP-1 --mode 1920x1080",
            "wlr-randr --json --output DP-1 --off",
            "hyprctl -b 'notify 1 2000 rgb(ff0000) hello'",
            "kill -0 -9 4242",
            "kill -l -TERM 4242",
        ):
            self.blocked(command)

    def test_cua_and_outer_exec_boundaries(self):
        self.assertIsNone(policy.classify({"tool_name": "mcp__cua_repl", "tool_input": {"code": "await cua.getState()"}}))
        self.assertIsNotNone(policy.classify({"tool_name": "mcp__cua_repl", "tool_input": {"code": "await cua.createBrowserTab('chrome', url, {visible: true})"}}))
        self.assertIsNone(policy.classify({"tool_name": "functions.exec", "tool_input": {"code": "hyprctl dispatch workspace 2"}}))
        self.assertIsNotNone(policy.classify({"tool_name": "functions.exec_command", "tool_input": {"command": "hyprctl reload"}}))
        self.assertIsNone(policy.classify({"tool_name": "mcp__other", "tool_input": {"text": "click hyprctl dispatch"}}))
        self.assertIsNone(policy.classify({"tool_name": "mcp__cua_repl", "tool_input": {"code": "await cua.createBrowserTab('iab', url, {visible: false})"}}))
        self.assertIsNotNone(policy.classify({"tool_name": "mcp__cua_repl", "tool_input": {"code": "await cua.createBrowserTab('iab', url, {visible: false}); await cua.click(1, 2)"}}))
        self.assertIsNotNone(policy.classify({"tool_name": "mcp__computer__click", "tool_input": {}}))

    def test_newline_comments_and_unquoted_heredoc_substitutions(self):
        self.blocked("# comment\nhyprctl reload")
        self.allowed("cat <<'EOF'\n$(hyprctl reload)\nEOF")
        self.blocked("cat <<EOF\n$(hyprctl reload)\nEOF")

    def test_bindings_hash_direct_script_only(self):
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as handle:
            handle.write("#!/bin/sh\n")
            path = handle.name
        try:
            result = policy.bindings(bash(path, process_identity={"pid": 1, "start_time": 2}))
            self.assertIn(path, result["scripts"])
            self.assertEqual(result["process_identity"]["pid"], 1)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
