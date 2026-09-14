"""Exercise release activation in a fake home; no live session files are used."""
from __future__ import annotations

import contextlib
import io
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

import deploy
import recovery
import verify_install


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.candidate = self.base / "candidate"
        self.candidate.mkdir()
        for name in deploy.PACKAGE:
            shutil.copyfile(Path(__file__).parent / name, self.candidate / name)
        originals = {
            ".claude/hooks/desktop-control-gate.py": "# old claude\n",
            ".codex/hooks/desktop-control-gate.py": "# old codex\n",
            ".claude/CLAUDE.md": "Unrelated rule\nThe desktop bullet is enforced, not just written down.\nold\n## Context discipline\nPreserved rule\n",
            ".codex/AGENTS.md": "Unrelated rule\n## Desktop Control Hard Gate\nold\n## Communication\nPreserved rule\n",
            ".claude/settings.json": '{"hooks": {}}', ".codex/config.toml": "[features]\nhooks=true\n",
            ".claude/hooks/tests/test_desktop_gate.py": "# old claude tests\n",
            ".codex/hooks/test_desktop_control_gate.py": "# old codex tests\n", ".gitignore": "/*\n",
        }
        for name, text in originals.items():
            target = self.home / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        self.source_patch = mock.patch.object(deploy, "SOURCE", self.candidate)
        self.plan_patch = mock.patch.object(deploy, "PLAN", self.candidate / "installation-plan.json")
        self.source_patch.start(); self.plan_patch.start()
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()

    def tearDown(self):
        self.output.__exit__(None, None, None)
        self.source_patch.stop(); self.plan_patch.stop()
        self.tmp.cleanup()

    def test_prepare_preserves_active_files_and_apply_preserves_registration(self):
        old = (self.home / ".claude/hooks/desktop-control-gate.py").read_bytes()
        plan = deploy.prepare(self.home)
        self.assertEqual((self.home / ".claude/hooks/desktop-control-gate.py").read_bytes(), old)
        deploy.apply(plan, check_legacy=False)
        self.assertEqual((self.home / ".claude/settings.json").read_text(), '{"hooks": {}}')
        self.assertIn("Preserved rule", (self.home / ".codex/AGENTS.md").read_text())
        self.assertTrue(os.access(self.home / ".local/bin/desktop-guard", os.X_OK))
        backups = list((self.home / ".local/state/desktop-guard/backups").iterdir())
        self.assertEqual((backups[0] / ".claude/hooks/desktop-control-gate.py").read_bytes(), old)
        # This runs only the newly installed Python hooks with fake JSON payloads.
        verify_install.verify(self.home)
        base = self.home / ".local/lib/desktop-guard"
        current = (base / "current").resolve()
        previous = (base / "previous").resolve()
        self.assertNotEqual(current, previous)
        recovery.rollback(base)
        self.assertEqual((base / "current").resolve(), previous)

    def test_concurrent_edit_aborts_before_activation(self):
        plan = deploy.prepare(self.home)
        target = self.home / ".codex/AGENTS.md"
        target.write_text(target.read_text() + "\nConcurrent user edit\n")
        with self.assertRaisesRegex(RuntimeError, "Concurrent edit preserved"):
            deploy.apply(plan, check_legacy=False)
        self.assertIn("Concurrent user edit", target.read_text())
        self.assertFalse((self.home / ".local/lib/desktop-guard/current").exists())

    def test_candidate_change_requires_new_validation_and_plan(self):
        plan = deploy.prepare(self.home)
        target = self.candidate / "policy.py"
        target.write_text(target.read_text() + "\n# changed after preparation\n")
        with self.assertRaisesRegex(RuntimeError, "Candidate changed"):
            deploy.preflight(plan, check_legacy=False)

    def test_first_install_failure_restores_targets_and_can_retry(self):
        plan = deploy.prepare(self.home)
        originals = {name: deploy.content(self.home / name) for name in deploy.TARGETS}
        write = deploy.atomic

        def fail_one_target(path, data, mode=0o644):
            if path == self.home / ".codex/AGENTS.md":
                raise OSError("simulated target write failure")
            return write(path, data, mode)

        with mock.patch.object(deploy, "atomic", side_effect=fail_one_target):
            with self.assertRaisesRegex(OSError, "simulated target write failure"):
                deploy.apply(plan, check_legacy=False)
        self.assertEqual({name: deploy.content(self.home / name) for name in deploy.TARGETS}, originals)
        base = self.home / ".local/lib/desktop-guard"
        self.assertFalse((base / "current").is_symlink())
        self.assertFalse((base / "previous").is_symlink())
        deploy.apply(plan, check_legacy=False)
        verify_install.verify(self.home)


if __name__ == "__main__":
    unittest.main(verbosity=2)
