#!/usr/bin/env python3
"""Offline tests for published DMS bundle selection and stock recovery."""

import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


TOOLING = Path(__file__).resolve().parents[1]
STATE = TOOLING / "bin/dms-bundle-state"
RUNNER = TOOLING / "bin/dms-run-patched"
BUILDER = TOOLING / "bin/dms-network-build"
THUMB = TOOLING / "bin/dms-matugen-thumb"


def sha(data):
    return hashlib.sha256(data).hexdigest()


class BundleStateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.stock = self.root / "stock-dms"
        self.stock.write_text("#!/bin/sh\nprintf 'stock %s\\n' \"$*\"\n")
        self.stock.chmod(0o755)
        self.env = dict(os.environ, DMS_NETWORK_CACHE=str(self.cache), DMS_STOCK_BINARY=str(self.stock))

    def command(self, program, *args, env=None):
        return subprocess.run([str(program), *map(str, args)], text=True, capture_output=True, env=env or self.env)

    def bundle(self, seed):
        key = sha(seed.encode())
        path = self.cache / key
        (path / "shell/scripts").mkdir(parents=True)
        (path / "shell/shell.qml").write_text("// shell " + seed)
        (path / "shell/scripts/helper").write_text("helper " + seed)
        (path / "dms").write_text("#!/bin/sh\nprintf 'patched %s\\n' \"$*\"\n")
        (path / "dms").chmod(0o755)
        (path / ".ready").write_text(key + "\n")
        (path / ".package-version").write_text("1.0.gabcdef0-1\n")
        return path

    def register(self, path):
        result = self.command(STATE, "register", path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(path))

    def test_select_only_registered_bundle_and_ignore_incomplete_staging(self):
        path = self.bundle("ready")
        (self.cache / ".build.incomplete").mkdir()
        self.assertNotEqual(self.command(STATE, "select").returncode, 0)
        self.register(path)
        result = self.command(STATE, "select")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(path) + "\n")
        (self.root / "patch-change").write_text("changed")
        self.assertEqual(self.command(STATE, "select").stdout, str(path) + "\n")

    def test_corrupt_active_uses_verified_previous(self):
        old = self.bundle("old")
        new = self.bundle("new")
        self.register(old)
        self.register(new)
        (new / "shell/shell.qml").write_text("corrupted")
        result = self.command(STATE, "select")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(old))
        self.assertIn("active rejected", result.stderr)

    def test_torn_registration_and_escaped_symlink_are_rejected(self):
        path = self.bundle("torn")
        (self.cache / "active").write_text(path.name + "\n")
        self.assertNotEqual(self.command(STATE, "select").returncode, 0)
        (path / "shell/scripts/helper").unlink()
        (path / "shell/scripts/helper").symlink_to(self.stock)
        self.assertNotEqual(self.command(STATE, "register", path).returncode, 0)
        (path / "shell/scripts/helper").unlink()
        (path / "shell/scripts/helper").write_text("restored")
        self.register(path)
        (self.cache / "active").unlink()
        (self.cache / "active").symlink_to(self.stock)
        self.assertNotEqual(self.command(STATE, "select").returncode, 0)

    def test_register_rejects_symlinked_bundle_and_markers_without_reselecting(self):
        active = self.bundle("active")
        self.register(active)
        candidate = self.bundle("candidate")
        outside = self.root / "outside-bundle"
        candidate.rename(outside)
        candidate.symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.command(STATE, "register", candidate).returncode, 0)
        self.assertEqual((self.cache / "active").read_text().strip(), active.name)
        candidate.unlink()
        outside.rename(candidate)
        ready = candidate / ".ready"
        ready.rename(self.root / "outside-ready")
        ready.symlink_to(self.root / "outside-ready")
        self.assertNotEqual(self.command(STATE, "register", candidate).returncode, 0)
        self.assertEqual((self.cache / "active").read_text().strip(), active.name)
        ready.unlink()
        (self.root / "outside-ready").rename(ready)
        version = candidate / ".package-version"
        version.rename(self.root / "outside-version")
        version.symlink_to(self.root / "outside-version")
        self.assertNotEqual(self.command(STATE, "register", candidate).returncode, 0)
        self.assertEqual((self.cache / "active").read_text().strip(), active.name)

    def test_mode_change_invalidates_registered_shell(self):
        path = self.bundle("mode")
        self.register(path)
        helper = path / "shell/scripts/helper"
        helper.chmod(0o600)
        result = self.command(STATE, "select")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("differs from registered manifest", result.stderr)

    def test_cache_root_symlink_is_rejected(self):
        path = self.bundle("root")
        self.register(path)
        link = self.root / "cache-link"
        link.symlink_to(self.cache, target_is_directory=True)
        env = dict(self.env, DMS_NETWORK_CACHE=str(link))
        self.assertNotEqual(self.command(STATE, "select", env=env).returncode, 0)
        self.assertNotEqual(self.command(STATE, "register", link / path.name, env=env).returncode, 0)

    def test_stock_upgrade_rejects_old_bundle(self):
        path = self.bundle("old-stock")
        self.register(path)
        self.stock.write_text("#!/bin/sh\nprintf 'new stock %s\\n' \"$*\"\n")
        self.assertNotEqual(self.command(STATE, "select").returncode, 0)
        self.assertIn("matches the installed stock binary", self.command(STATE, "select").stderr)

    def test_runner_launches_pair_offline_and_falls_back_to_stock(self):
        path = self.bundle("launcher")
        self.register(path)
        env = dict(self.env, DMS_BUNDLE_STATE=str(STATE), HOME=str(self.root))
        (self.root / ".local/bin").mkdir(parents=True)
        builder_marker = self.root / "builder-invoked"
        fake_builder = self.root / ".local/bin/dms-network-build"
        fake_builder.write_text(f"#!/bin/sh\ntouch '{builder_marker}'\nexit 99\n")
        fake_builder.chmod(0o755)
        result = self.command(RUNNER, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "patched run --session\n")
        self.assertFalse(builder_marker.exists())
        (path / "dms").write_text("corrupted")
        result = self.command(RUNNER, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "stock run --session\n")
        self.assertIn("no valid local patched bundle", result.stderr)
        result = self.command(RUNNER, env=dict(env, DMS_NETWORK_STOCK="1"))
        self.assertEqual(result.stdout, "stock run --session\n")
        self.assertFalse(builder_marker.exists())

    def test_builder_rejects_ready_bundle_without_requested_theme_sync(self):
        patch_dir = self.root / "patches"
        patch_dir.mkdir()
        for name in ("network-core.patch", "network-shell.patch"):
            (patch_dir / name).write_text(name)
        ui_builder = self.root / "ui-builder"
        ui_builder.write_text("#!/bin/sh\nexit 0\n")
        state = self.root / "state"
        marker = self.root / "registered"
        state.write_text(f"#!/bin/sh\ntouch '{marker}'\n")
        state.chmod(0o755)
        commands = self.root / "commands"
        commands.mkdir()
        pacman = commands / "pacman"
        pacman.write_text("#!/bin/sh\nprintf 'dms-shell-git 1.0.gabcdef0-1\\n'\n")
        pacman.chmod(0o755)
        inputs = [self.stock, ui_builder, state, THUMB, BUILDER, *sorted(patch_dir.iterdir())]
        lines = b"".join(
            hashlib.sha256(path.read_bytes()).hexdigest().encode() + b"  " + os.fsencode(path) + b"\n"
            for path in inputs
        )
        key = hashlib.sha256(lines + b"THEME_SYNC=1\n").hexdigest()
        bundle = self.cache / key
        (bundle / "shell").mkdir(parents=True)
        (bundle / "shell/shell.qml").write_text("// no sync")
        (bundle / "dms").write_text("#!/bin/sh\nexit 0\n")
        (bundle / "dms").chmod(0o755)
        (bundle / ".ready").write_text(key + "\n")
        env = dict(
            self.env,
            PATH=str(commands) + os.pathsep + os.environ["PATH"],
            DMS_PATCH_DIR=str(patch_dir),
            DMS_UI_BUILDER=str(ui_builder),
            DMS_BUNDLE_STATE=str(state),
            THEME_SYNC="1",
        )
        result = self.command(BUILDER, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("thumbnail helper is missing", result.stderr)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
